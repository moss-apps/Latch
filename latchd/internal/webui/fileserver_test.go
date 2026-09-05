package webui

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/pbkdf2"

	"latchd/internal/backup"
	"latchd/internal/cryptoutil"
)

// --- fixture builders (mirror the phone's push format) ---

func seal(t *testing.T, key, nonce, pt []byte) []byte {
	t.Helper()
	ct, err := cryptoutil.GcmSeal(key, nonce, pt)
	if err != nil {
		t.Fatal(err)
	}
	return ct
}

func fileBlob(t *testing.T, master, salt, iv []byte, iters int, pt []byte) []byte {
	t.Helper()
	fileKey := pbkdf2.Key(master, salt, iters, 32, sha256.New)
	ct := seal(t, fileKey, iv, pt)
	out := make([]byte, 8+len(ct))
	copy(out, "LKRG")
	binary.LittleEndian.PutUint32(out[4:8], uint32(len(pt)))
	copy(out[8:], ct)
	return out
}

// fixtureSession builds a backup dir (keybundle + manifest + blobs) and a
// Session over it, unlocked through the real /api/unlock handler.
func fixtureSession(t *testing.T) *Session {
	t.Helper()
	dir := t.TempDir()
	tgt := backup.Target{Dir: dir}
	cred := "correct-horse"

	master := make([]byte, 32)
	wrapSalt := make([]byte, 32)
	wrapIV := make([]byte, 16)
	rand.Read(master)
	rand.Read(wrapSalt)
	rand.Read(wrapIV)
	kwk := argon2.IDKey([]byte(cred), wrapSalt, 3, 16384, 1, 32)
	kb, _ := json.Marshal(map[string]any{
		"wrappedKey": base64.StdEncoding.EncodeToString(seal(t, kwk, wrapIV, master)),
		"wrapSalt":   base64.StdEncoding.EncodeToString(wrapSalt),
		"wrapIv":     base64.StdEncoding.EncodeToString(wrapIV),
		"argon2":     map[string]any{"t": 3, "m": 16384, "p": 1},
	})
	if err := os.WriteFile(filepath.Join(dir, "keybundle.json"), kb, 0o600); err != nil {
		t.Fatal(err)
	}

	str := func(s string) *string { return &s }
	iters := 1000
	added := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	modified := time.Date(2026, 8, 2, 11, 30, 0, 0, time.UTC)
	size := int64(11)

	newEntry := func(id, name, typ, mime string, pt []byte, legacy bool) backup.ManifestEntry {
		salt := make([]byte, 32)
		iv := make([]byte, 16)
		rand.Read(salt)
		rand.Read(iv)
		var blob []byte
		if legacy {
			blob = []byte("LKRBlegacyjunk")
		} else {
			blob = fileBlob(t, master, salt, iv, iters, pt)
		}
		h := cryptoutil.Sha256Hex(blob)
		p := tgt.BlobPath(h)
		if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, blob, 0o600); err != nil {
			t.Fatal(err)
		}
		e := backup.ManifestEntry{
			ID: id, ContentHash: &h, OriginalName: str(name),
			Type: str(typ), MimeType: str(mime), FileSize: &size,
			IsEncrypted: true, EncryptionIv: str(base64.StdEncoding.EncodeToString(iv)),
			KeyDerivationSalt: str(base64.StdEncoding.EncodeToString(salt)),
			KdfIterations:     &iters,
			DateAdded:         &backup.ManifestTime{Time: added},
			DateModified:      &backup.ManifestTime{Time: modified},
		}
		return e
	}

	plainEntry := func(id, name, typ, mime string, pt []byte) backup.ManifestEntry {
		h := cryptoutil.Sha256Hex(pt)
		p := tgt.BlobPath(h)
		if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, pt, 0o600); err != nil {
			t.Fatal(err)
		}
		return backup.ManifestEntry{
			ID: id, ContentHash: &h, OriginalName: str(name),
			Type: str(typ), MimeType: str(mime), FileSize: &size,
			IsEncrypted:  false,
			DateAdded:    &backup.ManifestTime{Time: added},
			DateModified: &backup.ManifestTime{Time: modified},
		}
	}

	img := image.NewRGBA(image.Rect(0, 0, 400, 250))
	var pngBuf bytes.Buffer
	if err := png.Encode(&pngBuf, img); err != nil {
		t.Fatal(err)
	}

	m := backup.Manifest{Version: 2, Entries: []backup.ManifestEntry{
		newEntry("a", "hello.txt", "document", "", []byte("hello world"), false),
		newEntry("b", "photo.png", "image", "image/png", pngBuf.Bytes(), false),
		newEntry("c", "old.bin", "document", "", []byte("legacy"), true),
		plainEntry("d", "plain.txt", "document", "text/plain", []byte("plain bytes")),
	}}
	manifestIV := make([]byte, 16)
	rand.Read(manifestIV)
	manifestJSON, _ := json.Marshal(m)
	envelope := append(manifestIV, seal(t, master, manifestIV, manifestJSON)...)
	if err := os.WriteFile(filepath.Join(dir, "manifest.enc"), envelope, 0o600); err != nil {
		t.Fatal(err)
	}

	s := &Session{targetDir: dir, thumbs: newThumbCache()}
	body := strings.NewReader(`{"credential":"correct-horse"}`)
	w := httptest.NewRecorder()
	s.handleUnlock(w, httptest.NewRequest(http.MethodPost, "/api/unlock", body))
	if w.Code != http.StatusOK {
		t.Fatalf("unlock failed: %d %s", w.Code, w.Body.String())
	}
	return s
}

func get(t *testing.T, s *Session, path string, header map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, path, nil)
	for k, v := range header {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	srv := s.handleFile
	if strings.HasPrefix(path, "/api/thumb/") {
		srv = s.handleThumb
	}
	srv(w, r)
	return w
}

func TestFileEndpointsLocked(t *testing.T) {
	s := &Session{targetDir: t.TempDir(), thumbs: newThumbCache()}
	for _, p := range []string{"/api/file/a", "/api/thumb/a"} {
		if w := get(t, s, p, nil); w.Code != http.StatusConflict {
			t.Fatalf("%s: expected 409 locked, got %d", p, w.Code)
		}
	}
}

func TestFileRoundtrip(t *testing.T) {
	s := fixtureSession(t)
	w := get(t, s, "/api/file/a", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", w.Code, w.Body.String())
	}
	if w.Body.String() != "hello world" {
		t.Fatalf("bad body: %q", w.Body.String())
	}
	ct := w.Header().Get("Content-Type")
	if !strings.HasPrefix(ct, "text/plain") {
		t.Fatalf("bad content type: %s", ct)
	}
	if w.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("missing nosniff")
	}
	if !strings.Contains(w.Header().Get("Content-Disposition"), "inline") {
		t.Fatalf("expected inline disposition, got %q", w.Header().Get("Content-Disposition"))
	}
}

func TestFileDownloadAttachment(t *testing.T) {
	s := fixtureSession(t)
	w := get(t, s, "/api/file/a?dl=1", nil)
	if !strings.Contains(w.Header().Get("Content-Disposition"), "attachment") {
		t.Fatalf("expected attachment disposition, got %q", w.Header().Get("Content-Disposition"))
	}
}

func TestFileUnknown404(t *testing.T) {
	s := fixtureSession(t)
	if w := get(t, s, "/api/file/nope", nil); w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestFileLegacyBlob422(t *testing.T) {
	s := fixtureSession(t)
	w := get(t, s, "/api/file/c", nil)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected 422 for legacy blob, got %d %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), "Export decrypted") {
		t.Fatalf("error should point at export: %s", w.Body.String())
	}
}

func TestThumbPngToJpeg(t *testing.T) {
	s := fixtureSession(t)
	w := get(t, s, "/api/thumb/b", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/jpeg" {
		t.Fatalf("bad content type: %s", ct)
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(w.Body.Bytes()))
	if err != nil {
		t.Fatalf("thumb not a decodable image: %v", err)
	}
	if cfg.Width > 320 || cfg.Height > 250 {
		t.Fatalf("thumb not scaled: %dx%d", cfg.Width, cfg.Height)
	}
	if cfg.Width != 320 {
		t.Fatalf("long side should hit the 320 cap: %dx%d", cfg.Width, cfg.Height)
	}
	etag := w.Header().Get("ETag")
	if etag == "" {
		t.Fatal("missing etag")
	}
	// Cached path serves the same etag and answers 304 on match.
	w2 := get(t, s, "/api/thumb/b", map[string]string{"If-None-Match": etag})
	if w2.Code != http.StatusNotModified {
		t.Fatalf("expected 304, got %d", w2.Code)
	}
}

func TestFileUnencryptedPlain(t *testing.T) {
	s := fixtureSession(t)
	w := get(t, s, "/api/file/d", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for unencrypted entry, got %d %s", w.Code, w.Body.String())
	}
	if w.Body.String() != "plain bytes" {
		t.Fatalf("bad body: %q", w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/plain") {
		t.Fatalf("bad content type: %s", ct)
	}
}

func TestThumbNonImage404(t *testing.T) {
	s := fixtureSession(t)
	if w := get(t, s, "/api/thumb/a", nil); w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for non-image, got %d", w.Code)
	}
}

func TestBrowseFields(t *testing.T) {
	s := fixtureSession(t)
	w := httptest.NewRecorder()
	s.handleBrowse(w, httptest.NewRequest(http.MethodGet, "/api/browse", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("browse: %d", w.Code)
	}
	var out struct {
		Files []map[string]any `json:"files"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out.Files) != 4 {
		t.Fatalf("expected 4 rows, got %d", len(out.Files))
	}
	first := out.Files[0]
	for _, k := range []string{"id", "name", "type", "size", "favorite", "mimeType", "dateAdded", "dateModified"} {
		if _, ok := first[k]; !ok {
			t.Fatalf("browse row missing %q: %v", k, first)
		}
	}
	if first["id"] != "a" || first["name"] != "hello.txt" {
		t.Fatalf("bad row: %v", first)
	}
}
