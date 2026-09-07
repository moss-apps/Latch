// Package receiver hosts the pairing receiver: a token-gated LAN listener
// that exists only while a pairing session is active. In push mode the
// phone scans the QR shown in the web UI and pushes the encrypted
// snapshot here:
//
//	GET  /info                 blob digests already on disk (phone diffs)
//	PUT  /keybundle            password-wrapped master key (validated shape)
//	PUT  /blob/<sha256>        one ciphertext blob, sha-verified on arrival
//	PUT  /manifest             completion signal: atomic swap + verify
//
// In restore mode the same listener serves the stored snapshot back to
// the phone (which pulls it):
//
//	GET  /info                 blob digests on disk (+ session mode)
//	GET  /keybundle            stored keybundle (404 if absent)
//	GET  /manifest             stored manifest envelope (404 if absent)
//	GET  /blob/<sha256>        one stored ciphertext blob (404 if absent)
//
// Either mode additionally serves the tap-to-approve USB handshake:
//
//	POST /usb-hello            {device, mode} → pending until the desktop
//	                           owner taps Allow, then the session token.
//	                           Loopback-only (i.e. via `adb reverse`);
//	                           non-loopback callers get a bare 404.
//
// Every request carries `Authorization: Bearer <session token>`. The
// listener closes on manifest completion (push), on Stop, or after the
// idle timeout — never long-running. Restore sessions have no completion
// signal; the phone finishes pulling and the idle timeout reaps the
// listener.
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

// Session modes. Push = phone→desktop backup; Restore = desktop→phone
// pull of the stored snapshot.
const (
	ModePush    = "push"
	ModeRestore = "restore"
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
	Received  int    `json:"received"`     // blobs accepted this session (push)
	Bytes     int64  `json:"bytes"`        // blob bytes accepted this session (push)
	Files     int    `json:"files"`        // blobs on disk after the verify pass
	Served    int    `json:"served"`      // blobs served this session (restore)
	ServedBytes int64 `json:"servedBytes"` // blob bytes served this session (restore)
	LastError string `json:"lastError,omitempty"`
}

// Receiver is one pairing session.
type Receiver struct {
	mu       sync.Mutex
	ln       net.Listener
	srv      *http.Server
	token    string
	mode     string
	target   backup.Target
	stats    Stats
	lastSeen time.Time
	closed   bool

	// Tap-to-approve USB state. A phone on the cable announces itself via
	// /usb-hello (reachable without the token, but only from loopback —
	// i.e. through `adb reverse`); the desktop owner taps Allow in the
	// web UI and the phone picks up the session token. No typing.
	usbPending     *UsbRequest
	usbApproved    bool
	usbDeniedUntil time.Time

	onComplete func() // optional, called once when a push verifies
	done       chan struct{}
}

// UsbRequest is a tap-to-approve request from a phone on the USB cable.
type UsbRequest struct {
	Device string    `json:"device"`
	Since  time.Time `json:"since"`
}

var shaHex = regexp.MustCompile(`^[0-9a-f]{64}$`)

// lg is the session log; pairing problems are diagnosable from it.
var lg = log.New(os.Stdout, "latchd receiver: ", log.LstdFlags)

// Start binds host:port (port 0 = ephemeral) with a fresh 256-bit token.
// mode selects the request set: ModePush (PUT set, phone→desktop) or
// ModeRestore (GET set, desktop→phone). Empty mode defaults to ModePush.
func Start(target backup.Target, host string, port int, mode string, onComplete func()) (*Receiver, error) {
	if mode != ModeRestore {
		mode = ModePush
	}
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
		mode:       mode,
		target:     target,
		stats:      Stats{State: StateWaiting},
		lastSeen:   time.Now(),
		onComplete: onComplete,
		done:       make(chan struct{}),
	}
	if mode == ModeRestore {
		// Surface what the session can serve before the first request.
		if hashes, err := target.Hashes(); err == nil {
			r.stats.Files = len(hashes)
		}
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/info", r.gated(r.handleInfo))
	mux.HandleFunc("/keybundle", r.gated(r.handleKeybundle))
	mux.HandleFunc("/manifest", r.gated(r.handleManifest))
	mux.HandleFunc("/blob/", r.gated(r.handleBlob))
	// Deliberately ungated (the phone has no token yet) but loopback-only:
	// over `adb reverse` the phone arrives as 127.0.0.1, while LAN callers
	// get a 404 and learn nothing.
	mux.HandleFunc("/usb-hello", r.handleUsbHello)
	r.srv = &http.Server{Handler: mux}
	go r.srv.Serve(ln)
	go r.idleWatch()
	lg.Printf("listening on %s (%s mode)", ln.Addr().String(), mode)
	return r, nil
}

// StartPreferred binds host on the first free port in the preferred range
// (7810-7820), falling back to an ephemeral port if all are taken.
func StartPreferred(target backup.Target, host string, mode string, onComplete func()) (*Receiver, error) {
	for p := PreferredPortFirst; p <= PreferredPortLast; p++ {
		r, err := Start(target, host, p, mode, onComplete)
		if err == nil {
			return r, nil
		}
	}
	return Start(target, host, 0, mode, onComplete)
}

// Addr is the listener address (host:port as bound).
func (r *Receiver) Addr() string { return r.ln.Addr().String() }

// Port is the bound TCP port.
func (r *Receiver) Port() int { return r.ln.Addr().(*net.TCPAddr).Port }

// Token is the hex session token shown in the QR.
func (r *Receiver) Token() string { return r.token }

// Mode is the session mode (push or restore).
func (r *Receiver) Mode() string { return r.mode }

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

// poke refreshes the idle deadline without changing session state.
func (r *Receiver) poke() {
	r.mu.Lock()
	r.lastSeen = time.Now()
	r.mu.Unlock()
}

// fromLoopback reports whether req arrived over loopback. Connections via
// `adb reverse` are opened by the host adb server, so a phone on the cable
// always looks like 127.0.0.1 — as does the desktop itself, which is
// equally trusted here (it already owns the backup dir).
func fromLoopback(req *http.Request) bool {
	host, _, err := net.SplitHostPort(req.RemoteAddr)
	if err != nil {
		return false
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// UsbPending snapshots the current tap-to-approve request, if any.
func (r *Receiver) UsbPending() *UsbRequest {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.usbPending == nil {
		return nil
	}
	cp := *r.usbPending
	return &cp
}

// UsbApproved reports whether the desktop owner already tapped Allow.
func (r *Receiver) UsbApproved() bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.usbApproved
}

// UsbAllow approves the pending USB request (web UI "Allow once").
// Idempotent: allowing twice keeps the session approved.
func (r *Receiver) UsbAllow() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.usbPending = nil
	r.usbApproved = true
	r.lastSeen = time.Now()
}

// UsbDeny rejects the pending USB request. Hellos during the cooldown get
// an explicit denial instead of silently re-creating the prompt.
func (r *Receiver) UsbDeny() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.usbPending = nil
	r.usbDeniedUntil = time.Now().Add(time.Minute)
}

// handleUsbHello serves the tap-to-approve handshake for phones on the USB
// cable: POST {"device","mode"} → pending until the desktop allows, then
// the session token. Loopback-only; anything else gets a bare 404.
func (r *Receiver) handleUsbHello(w http.ResponseWriter, req *http.Request) {
	if !fromLoopback(req) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
		return
	}
	if req.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "POST only"})
		return
	}
	var hello struct {
		Device string `json:"device"`
		Mode   string `json:"mode"`
	}
	if err := json.NewDecoder(io.LimitReader(req.Body, 1<<10)).Decode(&hello); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad JSON"})
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed {
		writeJSON(w, http.StatusGone, map[string]string{"error": "session closed"})
		return
	}
	if hello.Mode != "" && hello.Mode != r.mode {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": fmt.Sprintf(
				"the computer is in %q mode — switch its session to %q and try again",
				r.mode, hello.Mode),
		})
		return
	}
	if !r.usbDeniedUntil.IsZero() && time.Now().Before(r.usbDeniedUntil) {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"status": "denied",
			"error":  "denied on the computer — tap Connect via USB on the phone to ask again",
		})
		return
	}
	if r.usbApproved {
		writeJSON(w, http.StatusOK, map[string]string{
			"status": "approved", "token": r.token,
		})
		return
	}
	device := strings.TrimSpace(hello.Device)
	if device == "" {
		device = "USB phone"
	}
	if len(device) > 80 {
		device = device[:80]
	}
	if r.usbPending == nil {
		r.usbPending = &UsbRequest{Device: device, Since: time.Now()}
		lg.Printf("usb approval requested by %q (%s mode) — waiting for Allow in the web UI",
			device, r.mode)
	} else {
		r.usbPending.Device = device
	}
	r.lastSeen = time.Now()
	writeJSON(w, http.StatusOK, map[string]string{"status": "pending"})
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
		"mode":         r.mode,
		"hasManifest":  manifest != nil,
		"hasKeybundle": kb != nil,
		"hashes":       hashes,
	})
}

// readOnly rejects the push (PUT) set in a restore session.
func (r *Receiver) readOnly(w http.ResponseWriter) {
	writeJSON(w, http.StatusMethodNotAllowed, map[string]string{
		"error": "restore session is read-only — nothing can be pushed while it is open"})
}

// serveStored streams stored bytes back to the phone.
func serveStored(w http.ResponseWriter, data []byte) {
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	w.WriteHeader(http.StatusOK)
	w.Write(data)
}

func (r *Receiver) handleKeybundle(w http.ResponseWriter, req *http.Request) {
	if r.mode == ModeRestore {
		if req.Method != http.MethodGet {
			r.readOnly(w)
			return
		}
		kb, err := r.target.StoredKeybundle()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		if kb == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "no keybundle in the backup"})
			return
		}
		r.touch(StateReceiving)
		serveStored(w, kb)
		return
	}
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
	if r.mode == ModeRestore {
		if req.Method != http.MethodGet {
			r.readOnly(w)
			return
		}
		sha := filepath.Base(req.URL.Path)
		if !shaHex.MatchString(sha) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid blob digest"})
			return
		}
		f, err := os.Open(r.target.BlobPath(sha))
		if err != nil {
			if os.IsNotExist(err) {
				writeJSON(w, http.StatusNotFound, map[string]string{"error": "blob not in the backup"})
				return
			}
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		defer f.Close()
		st, err := f.Stat()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		r.touch(StateReceiving)
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Length", strconv.FormatInt(st.Size(), 10))
		n, err := io.Copy(w, f)
		if err == nil {
			r.mu.Lock()
			r.stats.Served++
			r.stats.ServedBytes += n
			r.mu.Unlock()
		}
		return
	}
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
	if r.mode == ModeRestore {
		if req.Method != http.MethodGet {
			r.readOnly(w)
			return
		}
		envelope, err := r.target.StoredManifest()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		if envelope == nil {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "no manifest in the backup"})
			return
		}
		r.touch(StateReceiving)
		serveStored(w, envelope)
		return
	}
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
