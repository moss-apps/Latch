package receiver

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"latchd/internal/backup"
)

func TestReceiverPushRoundtrip(t *testing.T) {
	dir := t.TempDir()
	tgt := backup.Target{Dir: dir}
	r, err := Start(tgt, "127.0.0.1", 0, ModePush, nil)
	if err != nil {
		t.Fatal(err)
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", r.Port())
	client := &http.Client{}

	put := func(path string, body []byte, authed bool) *http.Response {
		t.Helper()
		req, _ := http.NewRequest(http.MethodPut, base+path, bytes.NewReader(body))
		if authed {
			req.Header.Set("Authorization", "Bearer "+r.Token())
		}
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { res.Body.Close() })
		return res
	}
	get := func(path string, authed bool) *http.Response {
		t.Helper()
		req, _ := http.NewRequest(http.MethodGet, base+path, nil)
		if authed {
			req.Header.Set("Authorization", "Bearer "+r.Token())
		}
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { res.Body.Close() })
		return res
	}

	// No token → 401 before anything flows.
	if res := get("/info", false); res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unauthenticated /info: %d, want 401", res.StatusCode)
	}
	// Wrong token → 401 (constant-time path, same answer).
	req, _ := http.NewRequest(http.MethodGet, base+"/info", nil)
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("0", 64))
	if res, err := client.Do(req); err != nil || res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("wrong token: %v %v", err, res)
	} else {
		res.Body.Close()
	}

	// Fresh info: nothing on disk.
	res := get("/info", true)
	var info struct {
		HasManifest  bool     `json:"hasManifest"`
		HasKeybundle bool     `json:"hasKeybundle"`
		Hashes       []string `json:"hashes"`
	}
	if err := jsonDecode(res.Body, &info); err != nil {
		t.Fatal(err)
	}
	if info.HasManifest || info.HasKeybundle || len(info.Hashes) != 0 {
		t.Fatalf("fresh info: %+v", info)
	}

	// Tampered blob: hash mismatch → 422, nothing written.
	if res := put("/blob/"+strings.Repeat("a", 64), []byte("not the hash of this"), true); res.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("tampered blob: %d, want 422", res.StatusCode)
	}
	if hashes, _ := tgt.Hashes(); len(hashes) != 0 {
		t.Fatal("tampered blob touched disk")
	}

	// Valid keybundle.
	kb := []byte(`{"wrappedKey":"AAAA","wrapSalt":"BBBB","wrapIv":"CCCC","argon2":{"t":3,"m":16384,"p":1}}`)
	if res := put("/keybundle", kb, true); res.StatusCode != http.StatusOK {
		t.Fatalf("keybundle: %d", res.StatusCode)
	}
	if res := put("/keybundle", []byte(`{"nope":true}`), true); res.StatusCode != http.StatusBadRequest {
		t.Fatalf("bad keybundle: %d, want 400", res.StatusCode)
	}

	// Valid blob.
	blob := []byte("hello encrypted world")
	h := sha256.Sum256(blob)
	sha := hex.EncodeToString(h[:])
	if res := put("/blob/"+sha, blob, true); res.StatusCode != http.StatusOK {
		t.Fatalf("blob: %d", res.StatusCode)
	}
	raw, err := os.ReadFile(tgt.BlobPath(sha))
	if err != nil || !bytes.Equal(raw, blob) {
		t.Fatalf("stored blob: %v", err)
	}

	// Info now lists the hash.
	res = get("/info", true)
	if err := jsonDecode(res.Body, &info); err != nil {
		t.Fatal(err)
	}
	if len(info.Hashes) != 1 || info.Hashes[0] != sha || !info.HasKeybundle {
		t.Fatalf("info after push: %+v", info)
	}

	// Manifest completes the session.
	if res := put("/manifest", []byte("manifest-envelope-bytes"), true); res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(res.Body)
		t.Fatalf("manifest: %d %s", res.StatusCode, body)
	}
	deadline := time.Now().Add(2 * time.Second)
	for r.Active() && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if r.Active() {
		t.Fatal("receiver still active after completion")
	}
	st := r.Stats()
	if st.State != StateComplete || st.Received != 1 || st.Files != 1 {
		t.Fatalf("stats: %+v", st)
	}
	env, _ := tgt.StoredManifest()
	if string(env) != "manifest-envelope-bytes" {
		t.Fatal("manifest not stored")
	}
	stored, _ := tgt.StoredKeybundle()
	if !bytes.Equal(stored, kb) {
		t.Fatal("keybundle not stored verbatim")
	}

	// After completion the listener is closed: further requests fail.
	if _, err := client.Get(base + "/info"); err == nil {
		t.Fatal("listener should be closed after completion")
	}
}

func TestReceiverCreatesMissingBackupDir(t *testing.T) {
	// Regression: keybundle is the first push and used to 500 when the
	// backup dir did not exist yet.
	tgt := backup.Target{Dir: filepath.Join(t.TempDir(), "latch-backup")}
	r, err := Start(tgt, "127.0.0.1", 0, ModePush, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Stop("")
	base := fmt.Sprintf("http://127.0.0.1:%d", r.Port())

	kb := []byte(`{"wrappedKey":"AAAA","wrapSalt":"BBBB","wrapIv":"CCCC","argon2":{"t":3,"m":16384,"p":1}}`)
	req, _ := http.NewRequest(http.MethodPut, base+"/keybundle", bytes.NewReader(kb))
	req.Header.Set("Authorization", "Bearer "+r.Token())
	res, err := (&http.Client{}).Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("keybundle into missing dir: %d, want 200", res.StatusCode)
	}
	stored, err := tgt.StoredKeybundle()
	if err != nil || !bytes.Equal(stored, kb) {
		t.Fatalf("stored keybundle: %v", err)
	}
}

func TestReceiverCompletionVerifyFailsOnCorruptBlob(t *testing.T) {
	dir := t.TempDir()
	tgt := backup.Target{Dir: dir}
	r, err := Start(tgt, "127.0.0.1", 0, ModePush, nil)
	if err != nil {
		t.Fatal(err)
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", r.Port())

	// A blob that lied about its name on a previous run (simulated by
	// writing it directly to disk).
	lie := []byte("corrupt content")
	h := sha256.Sum256([]byte("honest content"))
	sha := hex.EncodeToString(h[:])
	p := tgt.BlobPath(sha)
	os.MkdirAll(filepath.Dir(p), 0o700)
	os.WriteFile(p, lie, 0o600)

	req, _ := http.NewRequest(http.MethodPut, base+"/manifest", bytes.NewReader([]byte("env")))
	req.Header.Set("Authorization", "Bearer "+r.Token())
	res, err := (&http.Client{}).Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusInternalServerError {
		t.Fatalf("manifest over corrupt blob: %d, want 500", res.StatusCode)
	}
	if st := r.Stats(); st.State != StateError {
		t.Fatalf("state: %s, want error", st.State)
	}
}

func TestRestoreSessionServesBackup(t *testing.T) {
	// Build a backup snapshot on disk, then open a restore session and
	// pull it back: GET set only, PUTs rejected, missing things 404,
	// session never auto-completes.
	dir := t.TempDir()
	tgt := backup.Target{Dir: dir}

	kb := []byte(`{"wrappedKey":"AAAA","wrapSalt":"BBBB","wrapIv":"CCCC","argon2":{"t":3,"m":16384,"p":1}}`)
	if err := atomicWrite(tgt.KeybundlePath(), kb); err != nil {
		t.Fatal(err)
	}
	manifest := []byte("manifest-envelope-bytes")
	if err := atomicWrite(filepath.Join(dir, "manifest.enc"), manifest); err != nil {
		t.Fatal(err)
	}
	blob := []byte("hello encrypted world")
	h := sha256.Sum256(blob)
	sha := hex.EncodeToString(h[:])
	bp := tgt.BlobPath(sha)
	os.MkdirAll(filepath.Dir(bp), 0o700)
	if err := os.WriteFile(bp, blob, 0o600); err != nil {
		t.Fatal(err)
	}

	r, err := Start(tgt, "127.0.0.1", 0, ModeRestore, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Stop("")
	base := fmt.Sprintf("http://127.0.0.1:%d", r.Port())
	client := &http.Client{}

	do := func(method, path string, body []byte, authed bool) *http.Response {
		t.Helper()
		var rdr io.Reader
		if body != nil {
			rdr = bytes.NewReader(body)
		}
		req, _ := http.NewRequest(method, base+path, rdr)
		if authed {
			req.Header.Set("Authorization", "Bearer "+r.Token())
		}
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { res.Body.Close() })
		return res
	}
	body := func(res *http.Response) []byte {
		t.Helper()
		b, err := io.ReadAll(res.Body)
		if err != nil {
			t.Fatal(err)
		}
		return b
	}

	if r.Mode() != ModeRestore {
		t.Fatalf("mode: %s, want restore", r.Mode())
	}

	// Token gate first: no token and wrong token both 401.
	if res := do(http.MethodGet, "/info", nil, false); res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unauthenticated /info: %d, want 401", res.StatusCode)
	}
	req, _ := http.NewRequest(http.MethodGet, base+"/info", nil)
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("0", 64))
	if res, err := client.Do(req); err != nil || res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("wrong token: %v %v", err, res)
	} else {
		res.Body.Close()
	}

	// Info announces the restore mode and the stored snapshot.
	var info struct {
		Mode         string   `json:"mode"`
		HasManifest  bool     `json:"hasManifest"`
		HasKeybundle bool     `json:"hasKeybundle"`
		Hashes       []string `json:"hashes"`
	}
	if res := do(http.MethodGet, "/info", nil, true); res.StatusCode != http.StatusOK {
		t.Fatalf("info: %d", res.StatusCode)
	} else if err := jsonDecode(res.Body, &info); err != nil {
		t.Fatal(err)
	}
	if info.Mode != ModeRestore || !info.HasManifest || !info.HasKeybundle ||
		len(info.Hashes) != 1 || info.Hashes[0] != sha {
		t.Fatalf("restore info: %+v", info)
	}
	if st := r.Stats(); st.Files != 1 {
		t.Fatalf("pre-filled files stat: %+v", st)
	}

	// The pull set serves exactly what is on disk.
	if res := do(http.MethodGet, "/keybundle", nil, true); res.StatusCode != http.StatusOK || !bytes.Equal(body(res), kb) {
		t.Fatalf("keybundle: %d", res.StatusCode)
	}
	if res := do(http.MethodGet, "/manifest", nil, true); res.StatusCode != http.StatusOK || !bytes.Equal(body(res), manifest) {
		t.Fatalf("manifest: %d", res.StatusCode)
	}
	if res := do(http.MethodGet, "/blob/"+sha, nil, true); res.StatusCode != http.StatusOK || !bytes.Equal(body(res), blob) {
		t.Fatalf("blob: %d", res.StatusCode)
	}

	// Missing or malformed requests.
	if res := do(http.MethodGet, "/blob/"+strings.Repeat("a", 64), nil, true); res.StatusCode != http.StatusNotFound {
		t.Fatalf("missing blob: %d, want 404", res.StatusCode)
	}
	if res := do(http.MethodGet, "/blob/not-a-sha", nil, true); res.StatusCode != http.StatusBadRequest {
		t.Fatalf("bad digest: %d, want 400", res.StatusCode)
	}

	// The push set is closed: nothing can be written through a restore
	// session.
	for _, path := range []string{"/keybundle", "/manifest", "/blob/" + sha} {
		if res := do(http.MethodPut, path, []byte("x"), true); res.StatusCode != http.StatusMethodNotAllowed {
			t.Fatalf("put %s in restore session: %d, want 405", path, res.StatusCode)
		}
	}

	// Restore sessions have no completion signal: after serving
	// everything the listener is still up, and stats count what was
	// served.
	if !r.Active() {
		t.Fatal("restore session closed itself after serving")
	}
	st := r.Stats()
	if st.Served < 1 || st.ServedBytes < int64(len(blob)) {
		t.Fatalf("served stats: %+v", st)
	}

	// An empty backup dir yields clean 404s, not 500s.
	empty, err := Start(backup.Target{Dir: t.TempDir()}, "127.0.0.1", 0, ModeRestore, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer empty.Stop("")
	emptyBase := fmt.Sprintf("http://127.0.0.1:%d", empty.Port())
	for _, path := range []string{"/keybundle", "/manifest"} {
		req, _ := http.NewRequest(http.MethodGet, emptyBase+path, nil)
		req.Header.Set("Authorization", "Bearer "+empty.Token())
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		if res.StatusCode != http.StatusNotFound {
			t.Fatalf("empty backup %s: %d, want 404", path, res.StatusCode)
		}
		res.Body.Close()
	}
}

func TestUsbHelloApprove(t *testing.T) {
	// Tap-to-approve: the phone announces itself without a token, waits,
	// and picks up the session token once the desktop allows.
	r, err := Start(backup.Target{Dir: t.TempDir()}, "127.0.0.1", 0, ModePush, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Stop("")
	base := fmt.Sprintf("http://127.0.0.1:%d", r.Port())
	client := &http.Client{}

	hello := func(device, mode string) (int, map[string]string) {
		t.Helper()
		req, _ := http.NewRequest(http.MethodPost, base+"/usb-hello",
			strings.NewReader(fmt.Sprintf(`{"device":%q,"mode":%q}`, device, mode)))
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]string
		if err := jsonDecode(res.Body, &out); err != nil {
			t.Fatal(err)
		}
		return res.StatusCode, out
	}

	if code, out := hello("Test Phone", ModePush); code != http.StatusOK || out["status"] != "pending" {
		t.Fatalf("hello: %d %+v, want pending", code, out)
	}
	if p := r.UsbPending(); p == nil || p.Device != "Test Phone" {
		t.Fatalf("pending: %+v", p)
	}
	// Re-polls stay pending without spamming new requests.
	if code, out := hello("Test Phone", ModePush); code != http.StatusOK || out["status"] != "pending" {
		t.Fatalf("re-poll: %d %+v", code, out)
	}

	// Wrong mode is rejected so the phone can say which tab to open.
	if code, _ := hello("Test Phone", ModeRestore); code != http.StatusConflict {
		t.Fatalf("mode mismatch: %d, want 409", code)
	}

	// Non-loopback callers learn nothing: bare 404, no pending change.
	req, _ := http.NewRequest(http.MethodPost, "/usb-hello",
		strings.NewReader(`{"device":"LAN stranger","mode":"push"}`))
	req.RemoteAddr = "192.168.1.50:1234"
	rec := httptest.NewRecorder()
	r.handleUsbHello(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("LAN usb-hello: %d, want 404", rec.Code)
	}
	if p := r.UsbPending(); p == nil || p.Device != "Test Phone" {
		t.Fatalf("LAN hello touched state: %+v", p)
	}

	// Allow hands over the session token, and the token works.
	r.UsbAllow()
	if p := r.UsbPending(); p != nil {
		t.Fatalf("pending after allow: %+v", p)
	}
	code, out := hello("Test Phone", ModePush)
	if code != http.StatusOK || out["status"] != "approved" || out["token"] != r.Token() {
		t.Fatalf("approved: %d %+v", code, out)
	}
	infoReq, _ := http.NewRequest(http.MethodGet, base+"/info", nil)
	infoReq.Header.Set("Authorization", "Bearer "+out["token"])
	infoRes, err := client.Do(infoReq)
	if err != nil {
		t.Fatal(err)
	}
	infoRes.Body.Close()
	if infoRes.StatusCode != http.StatusOK {
		t.Fatalf("bearer /info with USB token: %d, want 200", infoRes.StatusCode)
	}
}

func TestUsbHelloDeny(t *testing.T) {
	r, err := Start(backup.Target{Dir: t.TempDir()}, "127.0.0.1", 0, ModeRestore, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer r.Stop("")
	base := fmt.Sprintf("http://127.0.0.1:%d", r.Port())

	hello := func() (int, map[string]string) {
		t.Helper()
		req, _ := http.NewRequest(http.MethodPost, base+"/usb-hello",
			strings.NewReader(`{"device":"Test Phone","mode":"restore"}`))
		res, err := (&http.Client{}).Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		var out map[string]string
		if err := jsonDecode(res.Body, &out); err != nil {
			t.Fatal(err)
		}
		return res.StatusCode, out
	}

	if code, out := hello(); code != http.StatusOK || out["status"] != "pending" {
		t.Fatalf("hello: %d %+v, want pending", code, out)
	}
	r.UsbDeny()
	if code, out := hello(); code != http.StatusForbidden || out["status"] != "denied" {
		t.Fatalf("denied: %d %+v, want 403 denied", code, out)
	}
}

func jsonDecode(r io.Reader, v any) error {
	return json.NewDecoder(r).Decode(v)
}
