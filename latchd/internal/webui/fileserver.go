// Per-file serving for the browser UI: GET /api/file/<id> streams decrypted
// plaintext (Range-capable, so video seeking works) and GET /api/thumb/<id>
// renders a small in-memory jpeg thumbnail. Plaintext never touches disk.
package webui

import (
	"bytes"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"latchd/internal/backup"
	"latchd/internal/cryptoutil"
)

var (
	errUnsupportedBlob = errors.New(
		"legacy encrypted blob — this file predates GCM encryption; use Export decrypted for it")
	errBlobUnavailable = errors.New(
		"blob missing or corrupt — pair the phone again to re-send it")
)

func (s *Session) handleFile(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/file/")
	if id == "" || strings.Contains(id, "/") {
		writeErr(w, http.StatusNotFound, fmt.Errorf("no such file"))
		return
	}
	s.mu.Lock()
	master, m := s.master, s.manifest
	s.mu.Unlock()
	if master == nil || m == nil {
		writeErr(w, http.StatusConflict, fmt.Errorf("unlock first"))
		return
	}
	e := findLiveEntry(m, id)
	if e == nil {
		writeErr(w, http.StatusNotFound, fmt.Errorf("unknown file — refresh the browser"))
		return
	}
	pt, err := decryptEntry(s.target(), master, e)
	if err != nil {
		switch {
		case errors.Is(err, errUnsupportedBlob):
			writeErr(w, http.StatusUnprocessableEntity, err)
		case errors.Is(err, errBlobUnavailable):
			writeErr(w, http.StatusNotFound, err)
		default:
			writeErr(w, http.StatusInternalServerError, err)
		}
		return
	}
	name := entryName(e)
	h := w.Header()
	h.Set("Content-Type", contentTypeFor(e, name))
	h.Set("X-Content-Type-Options", "nosniff")
	// Even a hostile html/svg blob must not run script on this origin (it
	// could reach the unlock/export APIs). No "sandbox" token though — it
	// breaks the browser's built-in PDF viewer inside the preview iframe.
	h.Set("Content-Security-Policy", "default-src 'none'")
	disp := "inline"
	if r.URL.Query().Get("dl") == "1" {
		disp = "attachment"
	}
	h.Set("Content-Disposition", fmt.Sprintf("%s; filename=\"%s\"", disp, quoteSafe(name)))
	http.ServeContent(w, r, name, time.Time{}, bytes.NewReader(pt))
}

func (s *Session) handleThumb(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/thumb/")
	if id == "" || strings.Contains(id, "/") {
		writeErr(w, http.StatusNotFound, fmt.Errorf("no such file"))
		return
	}
	s.mu.Lock()
	master, m := s.master, s.manifest
	s.mu.Unlock()
	if master == nil || m == nil {
		writeErr(w, http.StatusConflict, fmt.Errorf("unlock first"))
		return
	}
	e := findLiveEntry(m, id)
	if e == nil || !isImageEntry(e) {
		writeErr(w, http.StatusNotFound, fmt.Errorf("no thumbnail for this file"))
		return
	}
	etag := thumbETag(id, *e.ContentHash)
	if r.Header.Get("If-None-Match") == etag {
		w.Header().Set("ETag", etag)
		w.WriteHeader(http.StatusNotModified)
		return
	}
	if s.thumbs != nil {
		if jpg := s.thumbs.get(id); jpg != nil {
			serveThumb(w, r, etag, jpg)
			return
		}
	}
	pt, err := decryptEntry(s.target(), master, e)
	if err != nil {
		writeErr(w, http.StatusNotFound, err)
		return
	}
	jpg, err := makeThumbnail(pt)
	if err != nil {
		// Not decodeable here (HEIC, svg, corrupt): the UI falls back to
		// the type glyph.
		writeErr(w, http.StatusNotFound, fmt.Errorf("no thumbnail: %v", err))
		return
	}
	if s.thumbs != nil {
		s.thumbs.put(id, jpg)
	}
	serveThumb(w, r, etag, jpg)
}

func serveThumb(w http.ResponseWriter, r *http.Request, etag string, jpg []byte) {
	h := w.Header()
	h.Set("Content-Type", "image/jpeg")
	h.Set("ETag", etag)
	h.Set("Cache-Control", "private, max-age=3600")
	h.Set("X-Content-Type-Options", "nosniff")
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(jpg))
}

func findLiveEntry(m *backup.Manifest, id string) *backup.ManifestEntry {
	for i := range m.Entries {
		e := &m.Entries[i]
		if e.ID == id && !e.Deleted && e.ContentHash != nil && *e.ContentHash != "" {
			return e
		}
	}
	return nil
}

func decryptEntry(t backup.Target, master []byte, e *backup.ManifestEntry) ([]byte, error) {
	raw, err := os.ReadFile(t.BlobPath(*e.ContentHash))
	if err != nil {
		return nil, errBlobUnavailable
	}
	if cryptoutil.Sha256Hex(raw) != *e.ContentHash {
		return nil, errBlobUnavailable
	}
	// The vault stores unencrypted files as-is; the pushed blob is the
	// plaintext and there is no container to open.
	if !e.IsEncrypted {
		return raw, nil
	}
	iters := 0
	if e.KdfIterations != nil {
		iters = *e.KdfIterations
	}
	pt, err := cryptoutil.DecryptFileBlob(raw, master,
		strOr(e.EncryptionIv, ""), strOr(e.KeyDerivationSalt, ""), iters,
		strOr(e.EncryptionAlgorithm, ""))
	if err != nil {
		if strings.Contains(err.Error(), "unsupported blob format") {
			return nil, errUnsupportedBlob
		}
		return nil, fmt.Errorf("cannot decrypt file: %w", err)
	}
	return pt, nil
}

func entryName(e *backup.ManifestEntry) string {
	if e.OriginalName != nil && *e.OriginalName != "" {
		return sanitizeName(*e.OriginalName)
	}
	return e.ID
}

func isImageEntry(e *backup.ManifestEntry) bool {
	if e.Type != nil && *e.Type == "image" {
		return true
	}
	return e.MimeType != nil && strings.HasPrefix(*e.MimeType, "image/")
}

func thumbETag(id, hash string) string {
	short := hash
	if len(short) > 12 {
		short = short[:12]
	}
	return `"` + id + "-" + short + `"`
}

func strOr(s *string, fallback string) string {
	if s == nil {
		return fallback
	}
	return *s
}

func sanitizeName(name string) string {
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	name = strings.TrimSpace(name)
	if name == "" || name == "." || name == ".." {
		return "unnamed"
	}
	return name
}

func quoteSafe(name string) string {
	return strings.Map(func(r rune) rune {
		if r < 32 || r == '"' || r == '\\' {
			return '_'
		}
		return r
	}, name)
}

// extMime is the fallback when the manifest carries no mimeType — only the
// extensions the browser viewer special-cases. html/svg are deliberately
// not served as markup (see the CSP header in handleFile).
var extMime = map[string]string{
	"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
	"gif": "image/gif", "webp": "image/webp", "bmp": "image/bmp",
	"svg": "image/svg+xml",
	"mp4": "video/mp4", "m4v": "video/mp4", "webm": "video/webm",
	"mov": "video/quicktime", "mkv": "video/x-matroska", "3gp": "video/3gpp",
	"mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac",
	"flac": "audio/flac", "wav": "audio/wav", "ogg": "audio/ogg",
	"oga": "audio/ogg", "opus": "audio/opus",
	"pdf": "application/pdf",
	"txt": "text/plain", "md": "text/plain", "csv": "text/csv",
	"json": "application/json", "log": "text/plain",
	"htm": "text/plain", "html": "text/plain",
}

func contentTypeFor(e *backup.ManifestEntry, name string) string {
	if mt := strOr(e.MimeType, ""); mt != "" {
		mt = strings.TrimSpace(strings.ToLower(mt))
		if mt == "text/html" {
			mt = "text/plain" // never hand this origin executable markup
		}
		if strings.HasPrefix(mt, "text/") && !strings.Contains(mt, "charset") {
			mt += "; charset=utf-8"
		}
		return mt
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))
	mt, ok := extMime[ext]
	if !ok {
		return "application/octet-stream"
	}
	if strings.HasPrefix(mt, "text/") {
		return mt + "; charset=utf-8"
	}
	return mt
}
