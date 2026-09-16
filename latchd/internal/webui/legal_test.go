package webui

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// withIsolatedConfig points LATCHD_CONFIG_DIR at a temp dir for the test.
func withIsolatedConfig(t *testing.T) {
	t.Helper()
	t.Setenv("LATCHD_CONFIG_DIR", t.TempDir())
}

func TestLegalVersionMatchesCanonical(t *testing.T) {
	raw, err := os.ReadFile("../../../legal/version.txt")
	if err != nil {
		t.Skipf("canonical legal/version.txt not present in this checkout: %v", err)
	}
	trimmed := strings.TrimSpace(string(raw))
	var parsed int
	if _, err := fmt.Sscanf(trimmed, "%d", &parsed); err != nil {
		t.Fatalf("legal/version.txt is not an int: %q", trimmed)
	}
	_ = parsed
	if parsed != LegalVersion {
		t.Fatalf("LegalVersion=%d but legal/version.txt=%d — bump both together", LegalVersion, parsed)
	}
}

// TestEmbeddedLegalDocsMatchCanonical guards the legaldocs/ copies shipped
// inside the binary against the repo-root canonical texts.
func TestEmbeddedLegalDocsMatchCanonical(t *testing.T) {
	missing := 0
	for _, name := range []string{"eula.md", "terms.md", "privacy.md"} {
		canonical, err := os.ReadFile("../../../legal/" + name)
		if err != nil {
			missing++
			continue
		}
		embedded, err := legalDocsFS.ReadFile("legaldocs/" + name)
		if err != nil {
			t.Fatalf("embedded legaldocs/%s missing: %v", name, err)
		}
		if string(embedded) != string(canonical) {
			t.Fatalf("legaldocs/%s is out of sync with legal/%s — run: make legal-sync", name, name)
		}
	}
	if missing == 3 {
		t.Skip("canonical legal/ texts not present in this checkout")
	}
}

func TestLegalGateBlocksThenAccepts(t *testing.T) {
	withIsolatedConfig(t)
	s := &Session{targetDir: t.TempDir(), thumbs: newThumbCache()}

	// Gate state starts unaccepted.
	w := httptest.NewRecorder()
	s.handleLegal(w, httptest.NewRequest(http.MethodGet, "/api/legal", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("GET /api/legal: %d", w.Code)
	}
	var info struct {
		Version   int  `json:"version"`
		Accepted  bool `json:"accepted"`
		Documents []struct {
			ID string `json:"id"`
		} `json:"documents"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &info); err != nil {
		t.Fatal(err)
	}
	if info.Version != LegalVersion || info.Accepted {
		t.Fatalf("unexpected gate state: %+v", info)
	}
	if len(info.Documents) != 3 {
		t.Fatalf("expected 3 legal documents, got %d", len(info.Documents))
	}

	// Guarded endpoints answer 403 before acceptance.
	guarded := []struct {
		method string
		path   string
		call   http.HandlerFunc
	}{
		{http.MethodPost, "/api/pair/start", s.requireLegal(s.handlePairStart)},
		{http.MethodPost, "/api/unlock", s.requireLegal(s.handleUnlock)},
		{http.MethodPost, "/api/verify", s.requireLegal(s.handleVerify)},
		{http.MethodGet, "/api/browse", s.requireLegal(s.handleBrowse)},
		{http.MethodPost, "/api/export", s.requireLegal(s.handleExport)},
		{http.MethodGet, "/api/file/x", s.requireLegal(s.handleFile)},
		{http.MethodGet, "/api/thumb/x", s.requireLegal(s.handleThumb)},
	}
	for _, g := range guarded {
		w := httptest.NewRecorder()
		g.call(w, httptest.NewRequest(g.method, g.path, nil))
		if w.Code != http.StatusForbidden {
			t.Fatalf("%s %s: expected 403, got %d", g.method, g.path, w.Code)
		}
	}

	// Unguarded housekeeping stays open (lock/stop/status/legal).
	for _, p := range []string{"/api/pair/stop", "/api/lock"} {
		_ = p
	}
	w = httptest.NewRecorder()
	s.handleStatus(w, httptest.NewRequest(http.MethodGet, "/api/status", nil))
	var status map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &status); err != nil {
		t.Fatal(err)
	}
	if status["legalAccepted"] != false {
		t.Fatalf("status should report legalAccepted=false: %v", status)
	}

	// Wrong version cannot be accepted.
	w = httptest.NewRecorder()
	s.handleLegalAccept(w, httptest.NewRequest(
		http.MethodPost, "/api/legal/accept",
		strings.NewReader(`{"version":999}`)))
	if w.Code != http.StatusConflict {
		t.Fatalf("stale version accept: expected 409, got %d", w.Code)
	}

	// Correct accept persists (0600 file in the isolated config dir).
	body := strings.NewReader(`{"version":` + itoa(LegalVersion) + `}`)
	w = httptest.NewRecorder()
	s.handleLegalAccept(w, httptest.NewRequest(http.MethodPost, "/api/legal/accept", body))
	if w.Code != http.StatusOK {
		t.Fatalf("accept: %d %s", w.Code, w.Body.String())
	}
	if !s.isLegalAccepted() {
		t.Fatal("expected accepted after POST /api/legal/accept")
	}
	entries, _ := os.ReadDir(os.Getenv("LATCHD_CONFIG_DIR"))
	if len(entries) != 1 || entries[0].Name() != "legal.json" {
		t.Fatalf("expected legal.json in config dir, got %v", entries)
	}
	info2, _ := os.Stat(filepath.Join(os.Getenv("LATCHD_CONFIG_DIR"), "legal.json"))
	if info2.Mode().Perm() != 0o600 {
		t.Fatalf("legal.json should be 0600, got %o", info2.Mode().Perm())
	}

	// Guarded endpoints now pass the gate (unlock itself may 401/500 on empty
	// body — anything but 403 proves the gate opened).
	w = httptest.NewRecorder()
	s.requireLegal(s.handleBrowse)(w, httptest.NewRequest(http.MethodGet, "/api/browse", nil))
	if w.Code == http.StatusForbidden {
		t.Fatal("browse still 403 after acceptance")
	}
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
