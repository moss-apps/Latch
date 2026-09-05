// Package backup stores the encrypted vault snapshot in a local
// latch-backup/ directory:
//
//	latch-backup/
//	  manifest.enc      encrypted RemoteManifest v2 (GCM envelope)
//	  keybundle.json    password-wrapped master key (as pushed)
//	  ab/cd/<sha>.enc  content-addressed blobs (sharded like sync S3)
//
// The phone pushes blobs + manifest into this layout over the pairing
// receiver (see internal/receiver); this package owns the on-disk format,
// unlock, verification, orphan reaping, and plaintext export.
package backup

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"latchd/internal/cryptoutil"
)

// ManifestTime also accepts the zone-less local strings Dart's
// toIso8601String() emits for non-UTC DateTimes (read as UTC — PocketBase
// hands the phone UTC wall times). Old manifests on disk keep parsing.
type ManifestTime struct{ time.Time }

func (t *ManifestTime) UnmarshalJSON(b []byte) error {
	s := strings.Trim(string(b), `"`)
	if s == "" || s == "null" {
		*t = ManifestTime{}
		return nil
	}
	for _, layout := range []string{
		time.RFC3339Nano, time.RFC3339,
		"2006-01-02T15:04:05.999999999", "2006-01-02T15:04:05",
	} {
		if v, err := time.Parse(layout, s); err == nil {
			t.Time = v.UTC()
			return nil
		}
	}
	return fmt.Errorf("bad timestamp %q", s)
}

// ManifestEntry is the RemoteManifest v2 entry (full restore metadata).
type ManifestEntry struct {
	ID                  string        `json:"id"`
	ContentHash         *string       `json:"contentHash"`
	Deleted             bool          `json:"deleted"`
	OriginalName        *string       `json:"originalName"`
	Type                *string       `json:"type"`
	MimeType            *string       `json:"mimeType"`
	FileSize            *int64        `json:"fileSize"`
	IsEncrypted         bool          `json:"isEncrypted"`
	EncryptionIv        *string       `json:"encryptionIv"`
	EncryptionAlgorithm *string       `json:"encryptionAlgorithm"`
	KeyDerivationSalt   *string       `json:"keyDerivationSalt"`
	KdfIterations       *int          `json:"kdfIterations"`
	IsFavorite          bool          `json:"isFavorite"`
	DateAdded           *ManifestTime `json:"dateAdded"`
	DateModified        *ManifestTime `json:"dateModified"`
}

// Manifest is the decrypted RemoteManifest v2 envelope payload.
type Manifest struct {
	Version int             `json:"version"`
	Entries []ManifestEntry `json:"entries"`
}

// Target is a local latch-backup/ directory.
type Target struct {
	Dir string
}

// BlobPath returns the sharded path for a content hash (mirrors the sync
// blobNameFor helper: first two hash bytes shard the directory).
func (t Target) BlobPath(shaHex string) string {
	padded := shaHex
	for len(padded) < 4 {
		padded = "0" + padded
	}
	return filepath.Join(t.Dir, padded[:2], padded[2:4], shaHex+".enc")
}

func (t Target) manifestPath() string { return filepath.Join(t.Dir, "manifest.enc") }

// KeybundlePath is the stored keybundle.json path.
func (t Target) KeybundlePath() string { return filepath.Join(t.Dir, "keybundle.json") }

func (t Target) keybundlePath() string { return t.KeybundlePath() }

// Hashes lists the blob digests already stored (walks the shard dirs).
func (t Target) Hashes() ([]string, error) {
	var out []string
	for _, shard1 := range listDirs(t.Dir) {
		for _, shard2 := range listDirs(shard1) {
			entries, err := os.ReadDir(shard2)
			if err != nil {
				continue
			}
			for _, e := range entries {
				name := e.Name()
				if len(name) == 68 && name[64:] == ".enc" {
					out = append(out, name[:64])
				}
			}
		}
	}
	return out, nil
}

// StoredManifest reads the local encrypted manifest, or nil if absent.
func (t Target) StoredManifest() ([]byte, error) {
	raw, err := os.ReadFile(t.manifestPath())
	if os.IsNotExist(err) {
		return nil, nil
	}
	return raw, err
}

// StoredKeybundle reads the local keybundle.json, or nil if absent.
func (t Target) StoredKeybundle() ([]byte, error) {
	raw, err := os.ReadFile(t.keybundlePath())
	if os.IsNotExist(err) {
		return nil, nil
	}
	return raw, err
}

// DecodeManifest decrypts + parses a manifest envelope with masterKey.
func DecodeManifest(envelope, masterKey []byte) (Manifest, error) {
	var m Manifest
	pt, err := cryptoutil.DecryptManifest(envelope, masterKey)
	if err != nil {
		return m, err
	}
	if err := json.Unmarshal(pt, &m); err != nil {
		return m, fmt.Errorf("bad manifest JSON: %w", err)
	}
	// JSON null leaves a zero ManifestTime behind; nil it back out.
	for i := range m.Entries {
		e := &m.Entries[i]
		if e.DateAdded != nil && e.DateAdded.Time.IsZero() {
			e.DateAdded = nil
		}
		if e.DateModified != nil && e.DateModified.Time.IsZero() {
			e.DateModified = nil
		}
	}
	return m, nil
}

// LiveHashes returns the content hashes a backup must hold: every non-deleted
// entry with a content hash.
func LiveHashes(m Manifest) []string {
	var out []string
	for _, e := range m.Entries {
		if !e.Deleted && e.ContentHash != nil && *e.ContentHash != "" {
			out = append(out, *e.ContentHash)
		}
	}
	return out
}

// Progress reports backup progress to the CLI / web UI.
type Progress struct {
	Done  int
	Total int
}

// keybundleJSON mirrors the phone's exportKeybundle map.
type keybundleJSON struct {
	WrappedKey string `json:"wrappedKey"`
	WrapSalt   string `json:"wrapSalt"`
	WrapIv     string `json:"wrapIv"`
	Argon2     struct {
		T uint32 `json:"t"`
		M uint32 `json:"m"`
		P uint32 `json:"p"`
	} `json:"argon2"`
}

// ErrUnlock marks a failed vault unlock: wrong credential or corrupted
// key material — deliberately indistinguishable at the message level.
var ErrUnlock = errors.New("vault unlock failed")

// UnlockManifest decrypts an envelope with an explicit credential + keybundle.
// A wrong credential fails closed with a generic error.
func UnlockManifest(envelope, keybundleRaw []byte, credential string) ([]byte, Manifest, error) {
	var kb keybundleJSON
	if err := json.Unmarshal(keybundleRaw, &kb); err != nil {
		return nil, Manifest{}, fmt.Errorf("bad keybundle: %w", err)
	}
	wrapped, err := base64.StdEncoding.DecodeString(kb.WrappedKey)
	if err != nil {
		return nil, Manifest{}, fmt.Errorf("bad keybundle: %w", err)
	}
	salt, err := base64.StdEncoding.DecodeString(kb.WrapSalt)
	if err != nil {
		return nil, Manifest{}, fmt.Errorf("bad keybundle: %w", err)
	}
	iv, err := base64.StdEncoding.DecodeString(kb.WrapIv)
	if err != nil {
		return nil, Manifest{}, fmt.Errorf("bad keybundle: %w", err)
	}
	master, err := cryptoutil.UnwrapKeybundle(cryptoutil.Keybundle{
		WrappedKey: wrapped,
		WrapSalt:   salt,
		WrapIV:     iv,
		Argon2: cryptoutil.Argon2Params{
			T: kb.Argon2.T,
			M: kb.Argon2.M,
			P: uint8(kb.Argon2.P),
		},
	}, credential)
	if err != nil {
		return nil, Manifest{}, ErrUnlock
	}
	m, err := DecodeManifest(envelope, master)
	if err != nil {
		return nil, Manifest{}, err
	}
	return master, m, nil
}

// ValidateKeybundle checks the shape of a pushed keybundle JSON before it
// is allowed near disk: the three base64 fields and the argon2 params must
// decode. It does not attempt an unwrap.
func ValidateKeybundle(raw []byte) error {
	var kb keybundleJSON
	if err := json.Unmarshal(raw, &kb); err != nil {
		return fmt.Errorf("keybundle is not valid JSON: %w", err)
	}
	if kb.WrappedKey == "" || kb.WrapSalt == "" || kb.WrapIv == "" || kb.Argon2.T == 0 || kb.Argon2.M == 0 {
		return fmt.Errorf("keybundle is missing required fields")
	}
	for _, s := range []string{kb.WrappedKey, kb.WrapSalt, kb.WrapIv} {
		if _, err := base64.StdEncoding.DecodeString(s); err != nil {
			return fmt.Errorf("keybundle field is not valid base64")
		}
	}
	return nil
}

// SwapManifest atomically replaces the stored manifest envelope.
func SwapManifest(t Target, envelope []byte) error {
	if err := os.MkdirAll(t.Dir, 0o700); err != nil {
		return err
	}
	tmp := t.manifestPath() + ".tmp"
	if err := os.WriteFile(tmp, envelope, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, t.manifestPath())
}

// ReapOrphans deletes blobs no live entry references.
func ReapOrphans(t Target, m Manifest) error { return reapOrphans(t, m) }

func short(h string) string {
	if len(h) > 12 {
		return h[:12]
	}
	return h
}

func reapOrphans(t Target, m Manifest) error {
	keep := map[string]bool{}
	for _, h := range LiveHashes(m) {
		keep[h] = true
	}
	for _, shard1 := range listDirs(t.Dir) {
		for _, shard2 := range listDirs(shard1) {
			entries, err := os.ReadDir(shard2)
			if err != nil {
				continue
			}
			for _, e := range entries {
				name := e.Name()
				if len(name) != 68 || name[64:] != ".enc" {
					continue
				}
				if !keep[name[:64]] {
					p := filepath.Join(shard2, name)
					if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
						return err
					}
				}
			}
		}
	}
	return nil
}

func listDirs(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			out = append(out, filepath.Join(dir, e.Name()))
		}
	}
	return out
}
