package backup

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/pbkdf2"

	"latchd/internal/cryptoutil"
)

// --- fixture builders (mirror the Dart side, independent code path) ---

func testSeal(t *testing.T, key, nonce, pt []byte) []byte {
	t.Helper()
	ct, err := cryptoutil.GcmSeal(key, nonce, pt)
	if err != nil {
		t.Fatal(err)
	}
	return ct
}

func testFileBlob(t *testing.T, master, salt, iv []byte, iters int, pt []byte) []byte {
	t.Helper()
	fileKey := pbkdf2.Key(master, salt, iters, 32, sha256.New)
	ct := testSeal(t, fileKey, iv, pt)
	out := make([]byte, 8+len(ct))
	copy(out, "LKRG")
	binary.LittleEndian.PutUint32(out[4:8], uint32(len(pt)))
	copy(out[8:], ct)
	return out
}

// fixture creates a backup dir with a 2-file manifest + blobs + keybundle.
// Returns the target, credential, and content hashes.
func fixture(t *testing.T) (Target, string, []string) {
	t.Helper()
	dir := t.TempDir()
	tgt := Target{Dir: dir}
	cred := "correct-horse"

	master := make([]byte, 32)
	if _, err := rand.Read(master); err != nil {
		t.Fatal(err)
	}
	wrapSalt := make([]byte, 32)
	wrapIV := make([]byte, 16)
	if _, err := rand.Read(wrapSalt); err != nil {
		t.Fatal(err)
	}
	if _, err := rand.Read(wrapIV); err != nil {
		t.Fatal(err)
	}
	kwk := argon2.IDKey([]byte(cred), wrapSalt, 3, 16384, 1, 32)
	wrapped := testSeal(t, kwk, wrapIV, master)
	kb, _ := json.Marshal(map[string]any{
		"wrappedKey": base64.StdEncoding.EncodeToString(wrapped),
		"wrapSalt":   base64.StdEncoding.EncodeToString(wrapSalt),
		"wrapIv":     base64.StdEncoding.EncodeToString(wrapIV),
		"argon2":     map[string]any{"t": 3, "m": 16384, "p": 1},
	})
	if err := os.WriteFile(filepath.Join(dir, "keybundle.json"), kb, 0o600); err != nil {
		t.Fatal(err)
	}

	str := func(s string) *string { return &s }
	n1, n2 := int64(11), int64(4)
	fav := true
	added := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	modified := time.Date(2026, 8, 2, 11, 30, 0, 0, time.UTC)
	salt1, iv1 := make([]byte, 32), make([]byte, 16)
	salt2, iv2 := make([]byte, 32), make([]byte, 16)
	rand.Read(salt1)
	rand.Read(iv1)
	rand.Read(salt2)
	rand.Read(iv2)
	blob1 := testFileBlob(t, master, salt1, iv1, 100000, []byte("hello world"))
	blob2 := testFileBlob(t, master, salt2, iv2, 100000, []byte("data"))
	blob3 := []byte("plain data") // unencrypted entry: pushed as-is
	h1 := cryptoutil.Sha256Hex(blob1)
	h2 := cryptoutil.Sha256Hex(blob2)
	h3 := cryptoutil.Sha256Hex(blob3)
	n3 := int64(len(blob3))
	iters := 100000
	m := Manifest{Version: 2, Entries: []ManifestEntry{
		{ID: "a", ContentHash: &h1, OriginalName: str("hello.txt"),
			Type: str("image"), FileSize: &n1, IsEncrypted: true,
			EncryptionIv:      str(base64.StdEncoding.EncodeToString(iv1)),
			KeyDerivationSalt: str(base64.StdEncoding.EncodeToString(salt1)),
			KdfIterations:     &iters, IsFavorite: fav,
			DateAdded:    &ManifestTime{Time: added},
			DateModified: &ManifestTime{Time: modified}},
		{ID: "b", ContentHash: &h2, OriginalName: str("d.bin"),
			Type: str("video"), FileSize: &n2, IsEncrypted: true,
			EncryptionIv:      str(base64.StdEncoding.EncodeToString(iv2)),
			KeyDerivationSalt: str(base64.StdEncoding.EncodeToString(salt2)),
			KdfIterations:     &iters},
		{ID: "c", ContentHash: &h3, OriginalName: str("plain.txt"),
			Type: str("document"), FileSize: &n3, IsEncrypted: false},
	}}
	manifestIV := make([]byte, 16)
	rand.Read(manifestIV)
	manifestJSON, _ := json.Marshal(m)
	envelope := append(manifestIV, testSeal(t, master, manifestIV, manifestJSON)...)
	if err := os.WriteFile(filepath.Join(dir, "manifest.enc"), envelope, 0o600); err != nil {
		t.Fatal(err)
	}
	for _, hb := range []struct {
		h string
		b []byte
	}{{h1, blob1}, {h2, blob2}, {h3, blob3}} {
		p := tgt.BlobPath(hb.h)
		if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, hb.b, 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return tgt, cred, []string{h1, h2, h3}
}

func loadFixture(t *testing.T, tgt Target, cred string) Manifest {
	t.Helper()
	envelope, err := tgt.StoredManifest()
	if err != nil || envelope == nil {
		t.Fatal("no manifest")
	}
	kb, err := tgt.StoredKeybundle()
	if err != nil || kb == nil {
		t.Fatal("no keybundle")
	}
	_, m, err := UnlockManifest(envelope, kb, cred)
	if err != nil {
		t.Fatalf("unlock: %v", err)
	}
	return m
}

func TestUnlockRoundtrip(t *testing.T) {
	tgt, cred, _ := fixture(t)
	m := loadFixture(t, tgt, cred)
	if len(m.Entries) != 3 || m.Version != 2 {
		t.Fatalf("bad manifest: %+v", m)
	}
	if *m.Entries[0].OriginalName != "hello.txt" || !m.Entries[0].IsFavorite {
		t.Fatalf("bad entry metadata: %+v", m.Entries[0])
	}
	added := time.Date(2026, 8, 1, 10, 0, 0, 0, time.UTC)
	modified := time.Date(2026, 8, 2, 11, 30, 0, 0, time.UTC)
	if m.Entries[0].DateAdded == nil || !m.Entries[0].DateAdded.Equal(added) ||
		m.Entries[0].DateModified == nil || !m.Entries[0].DateModified.Equal(modified) {
		t.Fatalf("bad entry dates: %+v", m.Entries[0])
	}
}

// Dart's toIso8601String() drops the zone for local DateTimes; those
// manifests must still parse (read as UTC) and null must stay nil.
func TestZonelessDateStamps(t *testing.T) {
	manifestJSON := []byte(`{"version":2,"entries":[{"id":"z","deleted":false,` +
		`"dateAdded":"2026-09-05T20:47:50.837349","dateModified":null}]}`)
	master := make([]byte, 32)
	rand.Read(master)
	iv := make([]byte, 16)
	rand.Read(iv)
	envelope := append(iv, testSeal(t, master, iv, manifestJSON)...)
	m, err := DecodeManifest(envelope, master)
	if err != nil {
		t.Fatalf("zone-less manifest rejected: %v", err)
	}
	want := time.Date(2026, 9, 5, 20, 47, 50, 837349000, time.UTC)
	if m.Entries[0].DateAdded == nil || !m.Entries[0].DateAdded.Equal(want) {
		t.Fatalf("bad dateAdded: %+v", m.Entries[0].DateAdded)
	}
	if m.Entries[0].DateModified != nil {
		t.Fatalf("null dateModified should stay nil: %+v", m.Entries[0].DateModified)
	}
}

func TestWrongPasswordIndistinguishable(t *testing.T) {
	tgt, _, _ := fixture(t)
	envelope, _ := tgt.StoredManifest()
	kb, _ := tgt.StoredKeybundle()
	_, _, err := UnlockManifest(envelope, kb, "wrong-password")
	if err == nil {
		t.Fatal("expected error for wrong password")
	}
	// Must not leak whether the password or the data was at fault.
	for _, leak := range []string{"password", "argon", "tag", "auth"} {
		if containsFold(err.Error(), leak) {
			t.Fatalf("error leaks detail %q: %v", leak, err)
		}
	}
}

func TestVerifyPass(t *testing.T) {
	tgt, cred, hashes := fixture(t)
	m := loadFixture(t, tgt, cred)
	if err := VerifyManifest(tgt, m); err != nil {
		t.Fatalf("verify: %v", err)
	}
	if got := LiveHashes(m); len(got) != 3 || got[0] != hashes[0] {
		t.Fatalf("live hashes: %v", got)
	}
}

func TestVerifyFlippedByteFails(t *testing.T) {
	tgt, cred, hashes := fixture(t)
	m := loadFixture(t, tgt, cred)
	p := tgt.BlobPath(hashes[0])
	raw, _ := os.ReadFile(p)
	raw[10] ^= 0xFF
	if err := os.WriteFile(p, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	err := VerifyManifest(tgt, m)
	var ve *VerifyError
	if !errors.As(err, &ve) {
		t.Fatalf("expected *VerifyError, got %v", err)
	}
	if len(ve.Corrupt) != 1 || ve.Corrupt[0] != hashes[0][:12] {
		t.Fatalf("wrong corrupt set: %+v", ve)
	}
}

func TestVerifyMissingFails(t *testing.T) {
	tgt, cred, hashes := fixture(t)
	m := loadFixture(t, tgt, cred)
	if err := os.Remove(tgt.BlobPath(hashes[1])); err != nil {
		t.Fatal(err)
	}
	err := VerifyManifest(tgt, m)
	var ve *VerifyError
	if !errors.As(err, &ve) || len(ve.Missing) != 1 {
		t.Fatalf("expected one missing, got %v", err)
	}
}

func TestExportRoundtrip(t *testing.T) {
	tgt, cred, _ := fixture(t)
	out := t.TempDir() + "/plain"
	exported, skipped, err := ExportDir(tgt, cred, out, nil)
	if err != nil {
		t.Fatalf("export: %v", err)
	}
	if exported != 3 || skipped != 0 {
		t.Fatalf("exported=%d skipped=%d", exported, skipped)
	}
	raw, err := os.ReadFile(filepath.Join(out, "hello.txt"))
	if err != nil || string(raw) != "hello world" {
		t.Fatalf("bad export: %q %v", raw, err)
	}
	plain, err := os.ReadFile(filepath.Join(out, "plain.txt"))
	if err != nil || string(plain) != "plain data" {
		t.Fatalf("bad unencrypted export: %q %v", plain, err)
	}
}

func containsFold(s, sub string) bool {
	return len(s) >= len(sub) && searchFold(s, sub)
}

func searchFold(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		match := true
		for j := 0; j < len(sub); j++ {
			a, b := s[i+j], sub[j]
			if a >= 'A' && a <= 'Z' {
				a += 'a' - 'A'
			}
			if b >= 'A' && b <= 'Z' {
				b += 'a' - 'A'
			}
			if a != b {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
