// Command locker-pb is the embedded PocketBase sidecar for Locker.
//
// It is a thin wrapper around pocketbase.NewWithConfig: bind loopback only on
// an ephemeral port, gate every request with a random auth token, and run the
// JS schema migrations bundled into the binary. No business logic lives here.
//
// Dart spawns the .so, reads PORT+TOKEN from stdout, then talks to the REST API
// over loopback. The --dir flag MUST point at a writable app-private directory
// (nativeLibraryDir is read-only on Android, so the Dart launcher always sets it).
package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/jsvm"
	"github.com/pocketbase/pocketbase/tools/hook"
	"github.com/spf13/cobra"

	"github.com/locker/locker-pb/migrations"
)

const tokenHeader = "X-Locker-Token"

func main() {
	app := pocketbase.NewWithConfig(pocketbase.Config{HideStartBanner: true})

	var httpAddr string
	var authToken string
	app.RootCmd.Flags().StringVar(
		&httpAddr, "http", "127.0.0.1:0",
		"loopback listen address (ephemeral port when :0)",
	)
	app.RootCmd.Flags().StringVar(
		&authToken, "auth-token", "",
		"auth token gating all requests (random if empty)",
	)
	if authToken == "" {
		authToken = randomToken()
	}

	// JS migrations are bundled via go:embed; write them to the data dir so the
	// jsvm loader (which reads a real directory at register time) finds them.
	migrationsDir := filepath.Join(app.DataDir(), "migrations")
	if err := extractMigrations(migrationsDir); err != nil {
		log.Fatalf("extract migrations: %v", err)
	}

	jsvm.MustRegister(app, jsvm.Config{MigrationsDir: migrationsDir})

	// token gate + race-free ephemeral listener. Binding an OnServe hook lets us
	// hand apis.Serve our own already-bound listener so we can read the real port.
	app.OnServe().Bind(&hook.Handler[*core.ServeEvent]{
		Func: func(e *core.ServeEvent) error {
			e.Router.BindFunc(func(re *core.RequestEvent) error {
				if re.Request.Header.Get(tokenHeader) != authToken {
					return apis.NewUnauthorizedError("invalid token", nil)
				}
				return re.Next()
			})

			ln, err := net.Listen("tcp", httpAddr)
			if err != nil {
				return err
			}
			e.Listener = ln
			port := ln.Addr().(*net.TCPAddr).Port
			fmt.Printf("LOCKER_PB_PORT=%d\n", port)
			fmt.Printf("LOCKER_PB_TOKEN=%s\n", authToken)
			fmt.Printf("LOCKER_PB_READY=1\n")
			return e.Next()
		},
	})

	// Execute (not Start) so PB's default `serve`/`superuser` commands are never
	// registered — the binary cannot accidentally bind 0.0.0.0:8090.
	app.RootCmd.RunE = func(*cobra.Command, []string) error {
		return apis.Serve(app, apis.ServeConfig{
			HttpAddr:        httpAddr,
			ShowStartBanner: false,
		})
	}

	if err := app.Execute(); err != nil {
		log.Fatal(err)
	}
}

// extractMigrations writes every bundled *.js migration into destDir, overwriting
// so a binary upgrade ships its current schema. Idempotent and tiny.
func extractMigrations(destDir string) error {
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return err
	}
	entries, err := migrations.FS.ReadDir(".")
	if err != nil {
		return err
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".js") {
			continue
		}
		data, err := migrations.FS.ReadFile(e.Name())
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(destDir, e.Name()), data, 0o644); err != nil {
			return err
		}
	}
	return nil
}

func randomToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("generate auth token: %v", err)
	}
	return hex.EncodeToString(b) // 64 hex chars, 256-bit
}
