package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// Execute the current test binary, not an installed sidecar. Each server uses
// an isolated t.TempDir, an ephemeral loopback port, and a bounded lifetime.
func TestSidecarProcess(t *testing.T) {
	if os.Getenv("LATCH_PB_TEST_PROCESS") != "1" {
		return
	}
	for i, arg := range os.Args {
		if arg == "--" {
			os.Args = append([]string{"locker-pb"}, os.Args[i+1:]...)
			main()
			os.Exit(0)
		}
	}
	t.Fatal("missing helper arguments")
}

func helperCommand(ctx context.Context, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, os.Args[0], append(
		[]string{"-test.run=^TestSidecarProcess$", "--"}, args...)...)
	cmd.Env = append(os.Environ(), "LATCH_PB_TEST_PROCESS=1")
	return cmd
}

func TestBuildInfoDoesNotCreateData(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := helperCommand(ctx, "--build-info")
	cmd.Dir = t.TempDir()
	output, err := cmd.CombinedOutput()
	if err != nil || strings.TrimSpace(string(output)) != buildSource {
		t.Fatalf("build info: %q, %v", output, err)
	}
	entries, err := os.ReadDir(cmd.Dir)
	if err != nil || len(entries) != 0 {
		t.Fatalf("build-info created files: %v, %v", entries, err)
	}
}

func startTestSidecar(t *testing.T, dir string) (string, string, func()) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	cmd := helperCommand(ctx, "--dir="+dir, "--http=127.0.0.1:0")
	cmd.Dir = filepath.Dir(dir)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		cancel()
		t.Fatal(err)
	}
	var once sync.Once
	stop := func() { once.Do(func() { cancel(); _ = cmd.Wait() }) }
	t.Cleanup(stop)
	type handshake struct{ port, token string }
	ready := make(chan handshake, 1)
	go func() {
		defer close(ready)
		var h handshake
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.HasPrefix(line, "LOCKER_PB_PORT=") {
				h.port = strings.TrimPrefix(line, "LOCKER_PB_PORT=")
			}
			if strings.HasPrefix(line, "LOCKER_PB_TOKEN=") {
				h.token = strings.TrimPrefix(line, "LOCKER_PB_TOKEN=")
			}
			if line == "LOCKER_PB_READY=1" {
				ready <- h
				_, _ = io.Copy(io.Discard, stdout)
				return
			}
		}
	}()
	select {
	case h, ok := <-ready:
		port, err := strconv.Atoi(h.port)
		if ok && err == nil && port > 0 && len(h.token) == 64 {
			return "http://127.0.0.1:" + h.port, h.token, stop
		}
	case <-ctx.Done():
	}
	stop()
	t.Fatalf("no valid sidecar handshake: %s", stderr.String())
	return "", "", stop
}

func TestNativeBootstrapTokenMigrationsAndPersistence(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "isolated-pb-data")
	base, token, stop := startTestSidecar(t, dir)
	client := &http.Client{Timeout: 5 * time.Second}
	request := func(method, path, credential, body string, status int) map[string]any {
		t.Helper()
		req, err := http.NewRequest(method, base+path, strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		if credential != "" {
			req.Header.Set(tokenHeader, credential)
		}
		req.Header.Set("Content-Type", "application/json")
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		data, err := io.ReadAll(res.Body)
		if err != nil || res.StatusCode != status {
			t.Fatalf("%s %s: got %d, want %d: %s (%v)", method, path,
				res.StatusCode, status, data, err)
		}
		var decoded map[string]any
		if len(data) != 0 {
			if err := json.Unmarshal(data, &decoded); err != nil {
				t.Fatal(err)
			}
		}
		return decoded
	}
	request("GET", "/api/health", "", "", 401)
	request("GET", "/api/health", "wrong-token", "", 401)
	request("GET", "/api/health", token, "", 200)
	for _, collection := range []string{"vault_files", "albums", "tags", "folders"} {
		request("GET", "/api/collections/"+collection+"/records", token, "", 200)
	}
	const records = "/api/collections/vault_files/records"
	created := request("POST", records, token,
		`{"blob_ref":"test-fixture","modified_at":1,"cipher_meta":{"test":true},"deleted":false}`, 200)
	id, ok := created["id"].(string)
	if !ok || id == "" {
		t.Fatal("record creation returned no ID")
	}
	path := records + "/" + id
	request("PATCH", path, token, `{"blob_ref":"updated-fixture","modified_at":2}`, 200)
	stop()
	oldToken := token
	base, token, _ = startTestSidecar(t, dir)
	if token == oldToken {
		t.Fatal("token did not rotate after restart")
	}
	request("GET", "/api/health", oldToken, "", 401)
	restored := request("GET", path, token, "", 200)
	if restored["blob_ref"] != "updated-fixture" {
		t.Fatalf("record not persisted: %v", restored)
	}
	request("DELETE", path, token, "", 204)
	request("GET", path, token, "", 404)
}
