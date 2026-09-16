// Legal acceptance gate for Latch Web.
//
// The desktop owner must accept the EULA / Terms / Privacy Policy (versioned
// in legal/version.txt at the repo root, mirrored here as LegalVersion)
// before latchd does anything sensitive. Enforcement is server-side: the
// pairing, unlock, browse, file, thumbnail, verify, and export endpoints
// answer 403 until POST /api/legal/accept records the current version.
//
// Acceptance is persisted outside the backup directory so changing --dir
// does not reset it: %AppData%/latchd/legal.json on Windows,
// ~/.config/latchd/legal.json on Linux, overridable with LATCHD_CONFIG_DIR
// (used by tests). Bumping LegalVersion forces every installation through
// the gate again.
package webui

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// LegalVersion mirrors legal/version.txt at the repo root. Bump both
// together — a mismatch fails TestLegalVersionMatchesCanonical.
const LegalVersion = 1

// LegalDocs lists the markdown documents served from /legal/ (static files
// copied from legal/ into the web dist by the web-src build).
var LegalDocs = []map[string]string{
	{"id": "eula", "title": "License Agreement (EULA)", "path": "/legal/eula.md"},
	{"id": "terms", "title": "Terms and Conditions", "path": "/legal/terms.md"},
	{"id": "privacy", "title": "Privacy Policy", "path": "/legal/privacy.md"},
}

type legalRecord struct {
	Version    int    `json:"version"`
	AcceptedAt string `json:"acceptedAt"`
}

// errLegalRequired is the 403 body when the gate blocks an endpoint.
var errLegalRequired = fmt.Errorf("legal acceptance required — accept version %d at /api/legal/accept first", LegalVersion)

// legalConfigDir resolves where legal.json lives.
func legalConfigDir(targetDir string) string {
	if override := os.Getenv("LATCHD_CONFIG_DIR"); override != "" {
		return override
	}
	if dir, err := os.UserConfigDir(); err == nil && dir != "" {
		return filepath.Join(dir, "latchd")
	}
	return targetDir
}

// legalAcceptancePath is the JSON file recording acceptance.
func legalAcceptancePath(targetDir string) string {
	return filepath.Join(legalConfigDir(targetDir), "legal.json")
}

// acceptedLegalVersion returns the persisted accepted version, or 0 if none.
func acceptedLegalVersion(targetDir string) int {
	raw, err := os.ReadFile(legalAcceptancePath(targetDir))
	if err != nil {
		return 0
	}
	var rec legalRecord
	if err := json.Unmarshal(raw, &rec); err != nil {
		return 0
	}
	return rec.Version
}

// AcceptLegal records acceptance headlessly (CLI --accept-legal flag).
func AcceptLegal(targetDir string) error {
	s := &Session{targetDir: targetDir}
	return s.acceptLegal()
}

// isLegalAccepted reports whether the current LegalVersion was accepted.
func (s *Session) isLegalAccepted() bool {
	return acceptedLegalVersion(s.targetDir) >= LegalVersion
}

// acceptLegal persists acceptance of the current version.
func (s *Session) acceptLegal() error {
	path := legalAcceptancePath(s.targetDir)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	rec := legalRecord{
		Version:    LegalVersion,
		AcceptedAt: time.Now().UTC().Format(time.RFC3339),
	}
	raw, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o600)
}

// requireLegal wraps a handler, answering 403 until the EULA is accepted.
func (s *Session) requireLegal(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.isLegalAccepted() {
			writeErr(w, http.StatusForbidden, errLegalRequired)
			return
		}
		next(w, r)
	}
}

// handleLegal answers GET /api/legal with the gate state.
func (s *Session) handleLegal(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("GET only"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"version":   LegalVersion,
		"accepted":  s.isLegalAccepted(),
		"documents": LegalDocs,
	})
}

// handleLegalAccept records acceptance: POST /api/legal/accept {"version": N}.
// The version must equal LegalVersion — stale clients cannot accept an old
// text, and future texts cannot be pre-accepted.
func (s *Session) handleLegalAccept(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	var req struct {
		Version int `json:"version"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, fmt.Errorf("bad JSON: %w", err))
		return
	}
	if req.Version != LegalVersion {
		writeErr(w, http.StatusConflict, fmt.Errorf(
			"version mismatch: current legal version is %d, got %d — reload the page",
			LegalVersion, req.Version))
		return
	}
	if err := s.acceptLegal(); err != nil {
		writeErr(w, http.StatusInternalServerError, fmt.Errorf("could not record acceptance: %w", err))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "version": LegalVersion})
}
