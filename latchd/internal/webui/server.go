// Package webui serves the loopback web UI (default 127.0.0.1:7800). The
// UI creates the pairing credentials: it starts a token-gated LAN receiver
// and shows the QR the phone scans. The vault credential and master key
// live in server memory only and are dropped on shutdown.
package webui

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"latchd/internal/backup"
	"latchd/internal/receiver"
)

//go:embed all:web
var webFS embed.FS

// Session holds pairing-session + unlocked state in memory only.
type Session struct {
	mu        sync.Mutex
	targetDir string
	master    []byte
	manifest  *backup.Manifest
	recv      *receiver.Receiver
	thumbs    *thumbCache
}

func (s *Session) target() backup.Target { return backup.Target{Dir: s.targetDir} }

// dropUnlock clears the in-memory master key + manifest (lock, or a fresh
// push made them stale) and drops the session thumbnail cache.
func (s *Session) dropUnlock() {
	s.master = nil
	s.manifest = nil
	if s.thumbs != nil {
		s.thumbs.clear()
	}
}

// Serve binds a loopback-only HTTP server and blocks.
func Serve(addr, targetDir string) error {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("bad addr %q: %w", addr, err)
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return fmt.Errorf("refusing non-loopback addr %q (loopback only)", addr)
	}
	// Fail fast on an unwritable backup dir instead of 500ing mid-pairing.
	if err := os.MkdirAll(targetDir, 0o700); err != nil {
		return fmt.Errorf("backup dir %q: %w", targetDir, err)
	}
	s := &Session{targetDir: targetDir, thumbs: newThumbCache()}
	mux := http.NewServeMux()

	webRoot, err := fs.Sub(webFS, "web")
	if err != nil {
		return err
	}
	mux.Handle("/", http.FileServer(http.FS(webRoot)))
	mux.HandleFunc("/api/pair/start", s.handlePairStart)
	mux.HandleFunc("/api/pair/stop", s.handlePairStop)
	mux.HandleFunc("/api/pair/status", s.handlePairStatus)
	mux.HandleFunc("/api/unlock", s.handleUnlock)
	mux.HandleFunc("/api/lock", s.handleLock)
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/verify", s.handleVerify)
	mux.HandleFunc("/api/browse", s.handleBrowse)
	mux.HandleFunc("/api/export", s.handleExport)
	mux.HandleFunc("/api/file/", s.handleFile)
	mux.HandleFunc("/api/thumb/", s.handleThumb)

	fmt.Printf("latchd web UI on http://%s (loopback only)\n", addr)
	return http.ListenAndServe(addr, mux)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]string{"error": err.Error()})
}

// pairingPort is the preferred receiver port; one firewall rule
// (`ufw allow 7801/tcp`) then covers every pairing session.
const pairingPort = 7801

// virtualIface prefixes never carry the LAN the phone is on.
var virtualIface = []string{
	"docker", "veth", "virbr", "br-", "tun", "tap", "zt", "wg", "vmnet", "vboxnet",
}

func isVirtual(name string) bool {
	for _, p := range virtualIface {
		if strings.HasPrefix(name, p) {
			return true
		}
	}
	return false
}

// lanIPs lists candidate LAN IPv4s: up, non-loopback, real interfaces
// first (interface order), virtual bridges/VPNs last.
func lanIPs() []string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var real, virtual []string
	for _, iface := range ifaces {
		if iface.Flags&net.FlagLoopback != 0 || iface.Flags&net.FlagUp == 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			if ipn, ok := a.(*net.IPNet); ok {
				if v4 := ipn.IP.To4(); v4 != nil && !v4.IsLoopback() {
					if isVirtual(iface.Name) {
						virtual = append(virtual, v4.String())
					} else {
						real = append(real, v4.String())
					}
					break
				}
			}
		}
	}
	return append(real, virtual...)
}

// lanIP returns the best-guess LAN address for the QR.
func lanIP() string {
	if ips := lanIPs(); len(ips) > 0 {
		return ips[0]
	}
	return "127.0.0.1"
}

var webuiLog = log.New(os.Stdout, "latchd webui: ", log.LstdFlags)

func (s *Session) handlePairStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.recv != nil && s.recv.Active() {
		writeJSON(w, http.StatusOK, s.pairState(s.recv))
		return
	}
	// A completed/stopped session's credentials are dead by definition;
	// a new push also invalidates any unlocked state from the old one.
	s.dropUnlock()
	onComplete := func() {
		s.mu.Lock()
		s.dropUnlock()
		s.mu.Unlock()
	}
	// Prefer the fixed pairing port so a single firewall rule covers every
	// session; fall back to ephemeral if it is taken.
	recv, err := receiver.Start(s.target(), "0.0.0.0", pairingPort, onComplete)
	if err != nil {
		recv, err = receiver.Start(s.target(), "0.0.0.0", 0, onComplete)
	}
	if err != nil {
		writeErr(w, http.StatusInternalServerError, fmt.Errorf(
			"could not start the pairing receiver: %w", err))
		return
	}
	s.recv = recv
	fwHint := ""
	if ufwActive() {
		subnet := lanSubnet(lanIP())
		fwHint = fmt.Sprintf("; ufw is active: run `sudo ufw allow from %s "+
			"to any port %d proto tcp` if the phone cannot connect",
			subnet, recv.Port())
	}
	webuiLog.Printf("pairing session started: advertising http://%s:%d "+
		"(LAN candidates: %s%s)",
		lanIP(), recv.Port(), strings.Join(lanIPs(), ", "), fwHint)
	writeJSON(w, http.StatusOK, s.pairState(recv))
}

// ufwActive reports whether the ufw firewall service is running.
func ufwActive() bool {
	err := exec.Command("systemctl", "is-active", "--quiet", "ufw").Run()
	return err == nil
}

// lanSubnet maps 192.168.68.109 to 192.168.68.0/24 (best effort).
func lanSubnet(ip string) string {
	v4 := net.ParseIP(ip).To4()
	if v4 == nil {
		return ip + "/32"
	}
	return v4.Mask(net.CIDRMask(24, 32)).String() + "/24"
}

func (s *Session) handlePairStop(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.recv != nil {
		s.recv.Stop("cancelled on the desktop")
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// pairState is the wire shape for pair/start + pair/status. Credentials
// are included only while the session is live.
func (s *Session) pairState(recv *receiver.Receiver) map[string]any {
	st := recv.Stats()
	active := recv.Active()
	out := map[string]any{
		"active":    active,
		"state":     st.State,
		"received":  st.Received,
		"bytes":     st.Bytes,
		"files":     st.Files,
		"lastError": st.LastError,
	}
	if active {
		ip := lanIP()
		out["host"] = ip
		out["port"] = recv.Port()
		out["token"] = recv.Token()
		out["url"] = recv.PairingURL(ip)
	}
	return out
}

func (s *Session) handlePairStatus(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.recv == nil {
		writeJSON(w, http.StatusOK, map[string]any{"active": false})
		return
	}
	writeJSON(w, http.StatusOK, s.pairState(s.recv))
}

// unlockStored unlocks the stored backup with a credential; shared by
// /api/unlock and /api/verify. Caller holds s.mu or passes a fresh copy.
func (s *Session) unlockStored(credential string) ([]byte, backup.Manifest, error) {
	t := s.target()
	envelope, err := t.StoredManifest()
	if err != nil {
		return nil, backup.Manifest{}, err
	}
	if envelope == nil {
		return nil, backup.Manifest{}, errNoBackup
	}
	kb, err := t.StoredKeybundle()
	if err != nil {
		return nil, backup.Manifest{}, err
	}
	if kb == nil {
		return nil, backup.Manifest{}, errIncomplete
	}
	master, m, err := backup.UnlockManifest(envelope, kb, credential)
	if err != nil {
		return nil, backup.Manifest{}, err
	}
	if err := backup.VerifyManifest(t, m); err != nil {
		return nil, backup.Manifest{}, fmt.Errorf(
			"the received backup is incomplete: %w — pair the phone again to re-send the missing blobs", err)
	}
	return master, m, nil
}

var (
	errNoBackup   = errors.New("no backup on this machine yet — pair with your phone first")
	errIncomplete = errors.New("backup incomplete: no key bundle received yet")
)

func (s *Session) handleUnlock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	var req struct {
		Credential string `json:"credential"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, fmt.Errorf("bad JSON: %w", err))
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	master, m, err := s.unlockStored(req.Credential)
	if err != nil {
		switch {
		case errors.Is(err, errNoBackup):
			writeErr(w, http.StatusNotFound, err)
		case errors.Is(err, errIncomplete):
			writeErr(w, http.StatusConflict, err)
		case errors.Is(err, backup.ErrUnlock):
			writeErr(w, http.StatusUnauthorized, err)
		default:
			writeErr(w, http.StatusInternalServerError, err)
		}
		return
	}
	backup.ReapOrphans(s.target(), m) // best effort; superseded blobs
	s.master = master
	s.manifest = &m
	writeJSON(w, http.StatusOK, map[string]any{
		"ok": true, "files": len(backup.LiveHashes(m)),
	})
}

func (s *Session) handleLock(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.dropUnlock()
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Session) handleStatus(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	unlocked := s.manifest != nil
	files := 0
	if s.manifest != nil {
		files = len(backup.LiveHashes(*s.manifest))
	}
	s.mu.Unlock()
	t := s.target()
	out := map[string]any{
		"unlocked": unlocked, "files": files, "dir": s.targetDir,
		"hasLocal": false,
	}
	if raw, _ := t.StoredManifest(); raw != nil {
		out["hasLocal"] = true
		if st, err := os.Stat(filepath.Join(s.targetDir, "manifest.enc")); err == nil {
			out["lastBackup"] = st.ModTime().Format(time.RFC3339)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Session) handleVerify(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	var req struct {
		Credential string `json:"credential"`
	}
	json.NewDecoder(r.Body).Decode(&req) // body optional; unlock may be in memory
	s.mu.Lock()
	defer s.mu.Unlock()
	if req.Credential != "" {
		_, m, err := s.unlockStored(req.Credential)
		if err != nil {
			if errors.Is(err, backup.ErrUnlock) {
				writeErr(w, http.StatusUnauthorized, err)
				return
			}
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		// Credential-only verify: do not retain the master key.
		if err := backup.VerifyManifest(s.target(), m); err != nil {
			writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "files": len(backup.LiveHashes(m))})
		return
	}
	m := s.manifest
	if m == nil {
		writeErr(w, http.StatusConflict, fmt.Errorf("unlock first"))
		return
	}
	if err := backup.VerifyManifest(s.target(), *m); err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"ok": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "files": len(backup.LiveHashes(*m))})
}

func datePtr(t *backup.ManifestTime) *time.Time {
	if t == nil {
		return nil
	}
	u := t.Time
	return &u
}

func (s *Session) handleBrowse(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	m := s.manifest
	s.mu.Unlock()
	if m == nil {
		writeErr(w, http.StatusConflict, fmt.Errorf("unlock first"))
		return
	}
	type row struct {
		ID           string     `json:"id"`
		Name         string     `json:"name"`
		Type         string     `json:"type"`
		Size         *int64     `json:"size"`
		Favorite     bool       `json:"favorite"`
		MimeType     string     `json:"mimeType"`
		DateAdded    *time.Time `json:"dateAdded"`
		DateModified *time.Time `json:"dateModified"`
	}
	rows := []row{}
	for _, e := range m.Entries {
		if e.Deleted || e.ContentHash == nil || *e.ContentHash == "" {
			continue
		}
		name := e.ID
		if e.OriginalName != nil && *e.OriginalName != "" {
			name = *e.OriginalName
		}
		typ := ""
		if e.Type != nil {
			typ = *e.Type
		}
		rows = append(rows, row{
			ID: e.ID, Name: name, Type: typ, Size: e.FileSize,
			Favorite: e.IsFavorite, MimeType: strOr(e.MimeType, ""),
			DateAdded: datePtr(e.DateAdded), DateModified: datePtr(e.DateModified),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"files": rows})
}

func (s *Session) handleExport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, fmt.Errorf("POST only"))
		return
	}
	var req struct {
		Credential string `json:"credential"`
		Subdir     string `json:"subdir"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, fmt.Errorf("bad JSON: %w", err))
		return
	}
	// The export target is always a subdirectory of the latchd data dir —
	// never an absolute path — so the UI cannot be tricked into writing
	// plaintext anywhere else.
	clean := filepath.Clean("/" + req.Subdir)
	if clean == "/" || strings.Contains(clean, "..") {
		writeErr(w, http.StatusBadRequest, fmt.Errorf("subdir must be a plain folder name"))
		return
	}
	base, err := os.UserHomeDir()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	out := filepath.Join(base, "latchd-exports", filepath.Base(clean))
	if req.Credential == "" {
		// Unlock-once flow: reuse the in-memory master key.
		s.mu.Lock()
		master, m := s.master, s.manifest
		s.mu.Unlock()
		if master == nil || m == nil {
			writeErr(w, http.StatusConflict, fmt.Errorf("unlock first"))
			return
		}
		exported, skipped, err := backup.ExportWithMaster(s.target(), master, *m, out, nil)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"exported": exported, "skipped": skipped, "out": out,
		})
		return
	}
	exported, skipped, err := backup.ExportDir(
		s.target(), req.Credential, out, nil)
	if err != nil {
		if errors.Is(err, backup.ErrUnlock) {
			writeErr(w, http.StatusUnauthorized, err)
			return
		}
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"exported": exported, "skipped": skipped, "out": out,
	})
}
