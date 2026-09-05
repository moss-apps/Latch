// Package receiver hosts the pairing receiver: a token-gated LAN listener
// that exists only while a pairing session is active. The phone scans the
// QR shown in the web UI and pushes the encrypted snapshot here:
//
//	GET  /info                 blob digests already on disk (phone diffs)
//	PUT  /keybundle            password-wrapped master key (validated shape)
//	PUT  /blob/<sha256>        one ciphertext blob, sha-verified on arrival
//	PUT  /manifest             completion signal: atomic swap + verify
//
// Every request carries `Authorization: Bearer <session token>`. The
// listener closes on manifest completion, on Stop, or after the idle
// timeout — never long-running.
package receiver

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"latchd/internal/backup"
)

const (
	idleTimeout    = 5 * time.Minute
	maxKeybundle   = 64 << 10
	maxManifest    = 16 << 20
	maxBlobPreview = 8 << 30 // blobs stream to disk; cap is sanity, not memory

	// PreferredPortFirst/Last: the receiver tries these ports in order
	// before falling back to an ephemeral one, so the user can punch one
	// hole through a firewall (e.g. `ufw allow 7810:7820/tcp`) instead of
	// chasing a port that changes every session.
	PreferredPortFirst = 7810
	PreferredPortLast  = 7820
)

// Session states reported to the web UI.
const (
	StateWaiting   = "waiting"
	StateReceiving = "receiving"
	StateVerifying = "verifying"
	StateComplete  = "complete"
	StateError     = "error"
	StateStopped   = "stopped"
)

// Stats is a point-in-time snapshot for the web UI.
type Stats struct {
	State     string `json:"state"`
	Received  int    `json:"received"` // blobs accepted this session
	Bytes     int64  `json:"bytes"`    // blob bytes accepted this session
	Files     int    `json:"files"`    // blobs on disk after the verify pass
	LastError string `json:"lastError,omitempty"`
}

// Receiver is one pairing session.
type Receiver struct {
	mu       sync.Mutex
	ln       net.Listener
	srv      *http.Server
	token    string
	target   backup.Target
	stats    Stats
	lastSeen time.Time
	closed   bool

	onComplete func() // optional, called once when a push verifies
	done       chan struct{}
}

var shaHex = regexp.MustCompile(`^[0-9a-f]{64}$`)

// lg is the session log; pairing problems are diagnosable from it.
var lg = log.New(os.Stdout, "latchd receiver: ", log.LstdFlags)

// Start binds host:port (port 0 = ephemeral) with a fresh 256-bit token.
func Start(target backup.Target, host string, port int, onComplete func()) (*Receiver, error) {
	tokenRaw := make([]byte, 32)
	if _, err := rand.Read(tokenRaw); err != nil {
		return nil, err
	}
	ln, err := net.Listen("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		return nil, err
	}
	r := &Receiver{
		ln:         ln,
		token:      hex.EncodeToString(tokenRaw),
		target:     target,
		stats:      Stats{State: StateWaiting},
		lastSeen:   time.Now(),
		onComplete: onComplete,
		done:       make(chan struct{}),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/info", r.gated(r.handleInfo))
	mux.HandleFunc("/keybundle", r.gated(r.handleKeybundle))
	mux.HandleFunc("/manifest", r.gated(r.handleManifest))
	mux.HandleFunc("/blob/", r.gated(r.handleBlob))
	r.srv = &http.Server{Handler: mux}
	go r.srv.Serve(ln)
	go r.idleWatch()
	lg.Printf("listening on %s", ln.Addr().String())
	return r, nil
}

// StartPreferred binds host on the first free port in the preferred range
// (7810-7820), falling back to an ephemeral port if all are taken.
func StartPreferred(target backup.Target, host string, onComplete func()) (*Receiver, error) {
	for p := PreferredPortFirst; p <= PreferredPortLast; p++ {
		r, err := Start(target, host, p, onComplete)
		if err == nil {
			return r, nil
		}
	}
	return Start(target, host, 0, onComplete)
}

// Addr is the listener address (host:port as bound).
func (r *Receiver) Addr() string { return r.ln.Addr().String() }

// Port is the bound TCP port.
func (r *Receiver) Port() int { return r.ln.Addr().(*net.TCPAddr).Port }

// Token is the hex session token shown in the QR.
func (r *Receiver) Token() string { return r.token }

// PairingURL builds `http://<host>:<port>/#<token>` for the QR.
func (r *Receiver) PairingURL(host string) string {
	return fmt.Sprintf("http://%s/#%s",
		net.JoinHostPort(host, strconv.Itoa(r.Port())), r.token)
}

// Stats snapshots session progress.
func (r *Receiver) Stats() Stats {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.stats
}

// Active reports whether the listener is still up.
func (r *Receiver) Active() bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return !r.closed
}

// Stop closes the listener. reason lands in LastError unless the session
// already completed.
func (r *Receiver) Stop(reason string) {
	r.mu.Lock()
	if r.closed {
		r.mu.Unlock()
		return
	}
	r.closed = true
	state := r.stats.State
	if r.stats.State != StateComplete && r.stats.State != StateError {
		r.stats.State = StateStopped
		if reason != "" {
			r.stats.LastError = reason
		}
	}
	lastErr := r.stats.LastError
	r.mu.Unlock()
	switch {
	case reason != "":
		lg.Printf("stopped: %s", reason)
	case state == StateComplete:
		lg.Printf("stopped: session complete")
	case state == StateError:
		lg.Printf("stopped: session failed: %s", lastErr)
	default:
		lg.Printf("stopped")
	}
	r.ln.Close()
	close(r.done)
}

func (r *Receiver) idleWatch() {
	t := time.NewTicker(10 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-r.done:
			return
		case <-t.C:
			r.mu.Lock()
			idle := !r.closed &&
				(r.stats.State == StateWaiting || r.stats.State == StateReceiving) &&
				time.Since(r.lastSeen) > idleTimeout
			r.mu.Unlock()
			if idle {
				r.Stop("session timed out after 5 minutes of inactivity")
				return
			}
		}
	}
}

func (r *Receiver) authorized(req *http.Request) bool {
	got := req.Header.Get("Authorization")
	want := "Bearer " + r.token
	return len(got) == len(want) &&
		subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}

func (r *Receiver) gated(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, req *http.Request) {
		remote := req.RemoteAddr
		if !r.authorized(req) {
			lg.Printf("%s %s from %s -> 401 (missing or wrong token)",
				req.Method, req.URL.Path, remote)
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "missing or invalid bearer token"})
			return
		}
		r.mu.Lock()
		r.lastSeen = time.Now()
		r.mu.Unlock()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		h(sw, req)
		// Blob success lines would drown everything else out.
		if sw.status >= http.StatusBadRequest || !strings.HasPrefix(req.URL.Path, "/blob/") {
			lg.Printf("%s %s from %s -> %d",
				req.Method, req.URL.Path, remote, sw.status)
		}
	}
}

// statusWriter records the status code a handler wrote, for logging.
type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func (r *Receiver) touch(state string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lastSeen = time.Now()
	if r.stats.State != StateComplete && r.stats.State != StateError {
		r.stats.State = state
	}
}

func (r *Receiver) fail(state, msg string) {
	r.mu.Lock()
	r.stats.State = state
	r.stats.LastError = msg
	r.mu.Unlock()
}

func (r *Receiver) handleInfo(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "GET only"})
		return
	}
	hashes, err := r.target.Hashes()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	manifest, _ := r.target.StoredManifest()
	kb, _ := r.target.StoredKeybundle()
	host, _ := os.Hostname()
	writeJSON(w, http.StatusOK, map[string]any{
		"app":          "latchd",
		"protocol":     2,
		"host":         host,
		"hasManifest":  manifest != nil,
		"hasKeybundle": kb != nil,
		"hashes":       hashes,
	})
}

func (r *Receiver) handleKeybundle(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPut {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "PUT only"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(req.Body, maxKeybundle))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unreadable body"})
		return
	}
	if err := backup.ValidateKeybundle(body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	// The keybundle is the first thing pushed; the backup dir may not
	// exist yet (blobs only create it incidentally, via their shards).
	if err := os.MkdirAll(r.target.Dir, 0o700); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	if err := atomicWrite(r.target.KeybundlePath(), body); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	r.touch(StateReceiving)
	writeJSON(w, http.StatusOK, map[string]string{"stored": "keybundle"})
}

func (r *Receiver) handleBlob(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPut {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "PUT only"})
		return
	}
	sha := filepath.Base(req.URL.Path)
	if !shaHex.MatchString(sha) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid blob digest"})
		return
	}
	dest := r.target.BlobPath(sha)
	if err := os.MkdirAll(filepath.Dir(dest), 0o700); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	tmp, err := os.CreateTemp(filepath.Dir(dest), ".part-*")
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	tmpName := tmp.Name()
	h := sha256.New()
	n, err := io.Copy(tmp, io.TeeReader(io.LimitReader(req.Body, maxBlobPreview), h))
	closeErr := tmp.Close()
	if err != nil || closeErr != nil {
		os.Remove(tmpName)
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unreadable body"})
		return
	}
	if hex.EncodeToString(h.Sum(nil)) != sha {
		os.Remove(tmpName)
		writeJSON(w, http.StatusUnprocessableEntity, map[string]string{
			"error": "content hash mismatch — nothing written"})
		return
	}
	if err := os.Rename(tmpName, dest); err != nil {
		os.Remove(tmpName)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}
	r.mu.Lock()
	r.stats.Received++
	r.stats.Bytes += n
	r.stats.State = StateReceiving
	r.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]string{"stored": sha})
}

func (r *Receiver) handleManifest(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPut {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "PUT only"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(req.Body, maxManifest))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unreadable body"})
		return
	}
	if len(body) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "empty manifest"})
		return
	}
	r.touch(StateVerifying)
	if err := backup.SwapManifest(r.target, body); err != nil {
		r.fail(StateError, err.Error())
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		r.Stop("")
		return
	}
	// Credential-less completion check: every stored blob must hash to its
	// own name. Manifest-coverage verification happens after unlock.
	if err := backup.VerifyDir(r.target); err != nil {
		msg := err.Error()
		r.fail(StateError, msg)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": msg})
		r.Stop("")
		return
	}
	files, err := r.target.Hashes()
	if err != nil {
		files = nil
	}
	r.mu.Lock()
	r.stats.State = StateComplete
	r.stats.Files = len(files)
	received, recvBytes := r.stats.Received, r.stats.Bytes
	r.mu.Unlock()
	lg.Printf("manifest stored; verify passed; %d files on disk "+
		"(%d blobs, %d bytes accepted this session)",
		len(files), received, recvBytes)
	if r.onComplete != nil {
		r.onComplete()
	}
	r.Stop("")
	writeJSON(w, http.StatusOK, map[string]any{"stored": "manifest", "files": len(files)})
}

func atomicWrite(path string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".part-*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(name)
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return err
	}
	return os.Rename(name, path)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
