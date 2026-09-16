// latchd is the Latch desktop backup companion. The phone pushes the
// encrypted vault over a pairing session this process hosts (credentials
// created on the desktop, shown as a QR in the web UI), into a local
// latch-backup/ directory. latchd verifies it and can export plaintext
// for disaster recovery. The loopback web UI mirrors the phone's styling.
//
// Usage:
//
//	latchd serve [addr]                       loopback web UI (default 127.0.0.1:7800)
//	latchd verify [--dir D]                   verify a local backup
//	latchd export-decrypted --out O [--dir D] decrypt a local backup
//
// The vault credential comes from --password or LATCHD_PASSWORD (never
// stored; kept in memory only).
package main

import (
	"bufio"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"latchd/internal/backup"
	"latchd/internal/webui"
)

const defaultDir = "latch-backup"
const defaultAddr = "127.0.0.1:7800"

// version is stamped at release time from the app-version tag:
// -ldflags "-X main.version=0.18.0-beta.1" (mirrors the mobile release).
var version = "dev"

func main() {
	if len(os.Args) < 2 {
		// Double-clicked with no subcommand (typical on Windows): if a
		// Latch Web instance is already up, just open it; otherwise serve
		// and open the browser instead of printing usage and vanishing.
		if ln, err := net.Listen("tcp", defaultAddr); err != nil {
			openBrowser(browserURL(defaultAddr))
			return
		} else {
			_ = ln.Close()
		}
		if err := cmdServe(nil, true); err != nil {
			fmt.Fprintf(os.Stderr, "latchd: %v\n", err)
			if runtime.GOOS == "windows" {
				fmt.Println("Press Enter to close.")
				bufio.NewReader(os.Stdin).ReadString('\n')
			}
			os.Exit(1)
		}
		return
	}
	var err error
	switch os.Args[1] {
	case "serve":
		err = cmdServe(os.Args[2:], false)
	case "verify":
		err = cmdVerify(os.Args[2:])
	case "export-decrypted":
		err = cmdExport(os.Args[2:])
	case "version", "--version":
		fmt.Println(version)
	case "help", "-h", "--help":
		usage()
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "latchd: %v\n", err)
		os.Exit(1)
	}
}

// defaultServeDir keeps double-click runs writable: on Windows the exe may
// live under Program Files, so the backup goes to the user's home instead.
func defaultServeDir() string {
	if runtime.GOOS == "windows" {
		if home, err := os.UserHomeDir(); err == nil && home != "" {
			return filepath.Join(home, "latch-backup")
		}
	}
	return defaultDir
}

// openBrowser is a best-effort launch of the default browser (ignored where
// no opener exists, e.g. headless Linux).
func openBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	case "darwin":
		cmd = exec.Command("open", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	_ = cmd.Start()
}

// browserURL turns a listen address into the URL a browser can reach.
func browserURL(listen string) string {
	host, port, err := net.SplitHostPort(listen)
	if err != nil {
		return "http://" + listen
	}
	if host == "" || host == "0.0.0.0" || host == "::" || host == "[::]" {
		host = "127.0.0.1"
	}
	return "http://" + net.JoinHostPort(host, port)
}

func usage() {
	fmt.Fprintln(os.Stderr, `latchd — Latch desktop backup companion

  latchd (no arguments)         double-click mode: serve + open the browser
  latchd serve [addr] [--open]  loopback web UI (default 127.0.0.1:7800);
                                pairing QR + credentials live there
  latchd verify [--dir D]       verify a local backup
  latchd export-decrypted --out O [--dir D]
                                decrypt a local backup to plaintext
  latchd version                print the build version

Backups arrive over Wi-Fi: start a pairing session in the web UI and scan
the QR from the phone (Latch → Settings → Storage → Desktop Backup).
Over USB: plug the phone in, run the adb reverse command shown in the
web UI, tap Connect via USB on the phone, and tap Allow once here.

Credential: --password flag or LATCHD_PASSWORD env (never stored).`)
}

func cmdServe(args []string, open bool) error {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	addr := fs.String("addr", defaultAddr, "loopback listen address")
	dir := fs.String("dir", defaultServeDir(), "local backup directory")
	acceptLegal := fs.Bool("accept-legal", false, "record acceptance of the current legal version (EULA/Terms/Privacy) without opening the web gate")
	openFlag := fs.Bool("open", false, "open the web UI in the default browser once serving")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *openFlag {
		open = true
	}
	listen := *addr
	if fs.NArg() > 0 {
		listen = fs.Arg(0)
	}
	if *acceptLegal {
		if err := webui.AcceptLegal(*dir); err != nil {
			return err
		}
		fmt.Printf("latchd %s — legal v%d accepted\n", version, webui.LegalVersion)
	}
	url := browserURL(listen)
	fmt.Printf("latchd %s — web UI on %s (loopback only)\n", version, url)
	fmt.Println("By using Latch Web you accept the License Agreement, Terms and Privacy Policy (shown before first use, later in Settings → Legal).")
	if open {
		go func() {
			time.Sleep(400 * time.Millisecond) // let the listener bind first
			openBrowser(url)
		}()
	}
	return webui.Serve(listen, *dir)
}

func credential(fs *flag.FlagSet, password *string) (string, error) {
	_ = fs
	if *password != "" {
		return *password, nil
	}
	if env := os.Getenv("LATCHD_PASSWORD"); env != "" {
		return env, nil
	}
	fmt.Print("Vault password: ")
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimRight(line, "\r\n"), nil
}

func cmdVerify(args []string) error {
	fs := flag.NewFlagSet("verify", flag.ExitOnError)
	dir := fs.String("dir", defaultDir, "local backup directory")
	password := fs.String("password", "", "vault password (or LATCHD_PASSWORD)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	cred, err := credential(fs, password)
	if err != nil {
		return err
	}
	t := backup.Target{Dir: *dir}
	envelope, err := t.StoredManifest()
	if err != nil || envelope == nil {
		return fmt.Errorf("no backup in %s", *dir)
	}
	kb, err := t.StoredKeybundle()
	if err != nil || kb == nil {
		return fmt.Errorf("no keybundle in %s", *dir)
	}
	_, manifest, err := backup.UnlockManifest(envelope, kb, cred)
	if err != nil {
		return err
	}
	if err := backup.VerifyManifest(t, manifest); err != nil {
		return err
	}
	fmt.Printf("Verify OK: %d live blobs match the manifest.\n",
		len(backup.LiveHashes(manifest)))
	return nil
}

func cmdExport(args []string) error {
	fs := flag.NewFlagSet("export-decrypted", flag.ExitOnError)
	dir := fs.String("dir", defaultDir, "local backup directory")
	out := fs.String("out", "", "plaintext output directory (required)")
	password := fs.String("password", "", "vault password (or LATCHD_PASSWORD)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *out == "" {
		return fmt.Errorf("--out is required")
	}
	cred, err := credential(fs, password)
	if err != nil {
		return err
	}
	exported, skipped, err := backup.ExportDir(
		backup.Target{Dir: *dir}, cred, *out,
		func(pr backup.Progress) {
			fmt.Printf("\rDecrypting… %d/%d", pr.Done, pr.Total)
		})
	if err != nil {
		fmt.Println()
		return err
	}
	fmt.Printf("\nExported %d files to %s (%d legacy blobs skipped).\n",
		exported, *out, skipped)
	return nil
}
