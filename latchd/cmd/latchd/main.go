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
	"os"
	"strings"

	"latchd/internal/backup"
	"latchd/internal/webui"
)

const defaultDir = "latch-backup"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "serve":
		err = cmdServe(os.Args[2:])
	case "verify":
		err = cmdVerify(os.Args[2:])
	case "export-decrypted":
		err = cmdExport(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "latchd: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `latchd — Latch desktop backup companion

  latchd serve [addr]             loopback web UI (default 127.0.0.1:7800);
                                  pairing QR + credentials live there
  latchd verify [--dir D]         verify a local backup
  latchd export-decrypted --out O [--dir D]
                                  decrypt a local backup to plaintext

Backups arrive over Wi-Fi: start a pairing session in the web UI and scan
the QR from the phone (Latch → Settings → Storage → Desktop Backup).

Credential: --password flag or LATCHD_PASSWORD env (never stored).`)
}

func cmdServe(args []string) error {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	addr := fs.String("addr", "127.0.0.1:7800", "loopback listen address")
	dir := fs.String("dir", defaultDir, "local backup directory")
	if err := fs.Parse(args); err != nil {
		return err
	}
	listen := *addr
	if fs.NArg() > 0 {
		listen = fs.Arg(0)
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
