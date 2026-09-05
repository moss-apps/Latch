// Export decrypts a local backup into a plaintext directory tree for
// disaster recovery. Output names come from the manifest (originalName or
// id + type extension). The master key stays in memory; nothing secret is
// written except the recovered files themselves.
package backup

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"latchd/internal/cryptoutil"
)

// ExportDir decrypts every live entry of the local backup into outDir.
// credential unlocks the stored keybundle; onProgress reports per file.
func ExportDir(t Target, credential, outDir string, onProgress func(Progress)) (exported, skipped int, err error) {
	envelope, err := t.StoredManifest()
	if err != nil || envelope == nil {
		return 0, 0, fmt.Errorf("no local backup manifest")
	}
	keybundleRaw, err := t.StoredKeybundle()
	if err != nil || keybundleRaw == nil {
		return 0, 0, fmt.Errorf("no local backup keybundle")
	}
	master, manifest, err := UnlockManifest(envelope, keybundleRaw, credential)
	if err != nil {
		return 0, 0, err
	}
	return ExportWithMaster(t, master, manifest, outDir, onProgress)
}

// ExportWithMaster exports using an already-unlocked master key + manifest
// (the web UI's unlock-once flow) without re-deriving from a credential.
func ExportWithMaster(t Target, master []byte, manifest Manifest, outDir string, onProgress func(Progress)) (exported, skipped int, err error) {
	live := 0
	for _, e := range manifest.Entries {
		if e.Deleted || e.ContentHash == nil || *e.ContentHash == "" {
			continue
		}
		live++
	}
	for _, e := range manifest.Entries {
		if e.Deleted || e.ContentHash == nil || *e.ContentHash == "" {
			continue
		}
		name := exportName(e)
		dest := filepath.Join(outDir, name)
		if err := exportOne(t, master, e, dest); err != nil {
			if _, ok := err.(*UnsupportedFormatError); ok {
				skipped++
				continue
			}
			return exported, skipped, fmt.Errorf("%s: %w", name, err)
		}
		exported++
		if onProgress != nil {
			onProgress(Progress{Done: exported + skipped, Total: live})
		}
	}
	return exported, skipped, nil
}

// UnsupportedFormatError marks legacy CBC blobs latchd cannot decrypt.
type UnsupportedFormatError struct {
	Algorithm string
}

func (e *UnsupportedFormatError) Error() string {
	return fmt.Sprintf("unsupported on export (legacy %s blob)", e.Algorithm)
}

func exportOne(t Target, master []byte, e ManifestEntry, dest string) error {
	raw, err := os.ReadFile(t.BlobPath(*e.ContentHash))
	if err != nil {
		return err
	}
	if cryptoutil.Sha256Hex(raw) != *e.ContentHash {
		return fmt.Errorf("content check failed")
	}
	// Unencrypted vault files are pushed as-is; the blob is the plaintext.
	pt := raw
	if e.IsEncrypted {
		algo := strOr(e.EncryptionAlgorithm, "")
		iv := strOr(e.EncryptionIv, "")
		salt := strOr(e.KeyDerivationSalt, "")
		iters := 0
		if e.KdfIterations != nil {
			iters = *e.KdfIterations
		}
		var err error
		pt, err = cryptoutil.DecryptFileBlob(raw, master, iv, salt, iters, algo)
		if err != nil {
			if strings.Contains(err.Error(), "unsupported blob format") {
				return &UnsupportedFormatError{Algorithm: algoOrLegacy(algo)}
			}
			return err
		}
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o700); err != nil {
		return err
	}
	return os.WriteFile(dest, pt, 0o600)
}

func exportName(e ManifestEntry) string {
	if e.OriginalName != nil && *e.OriginalName != "" {
		return sanitize(*e.OriginalName)
	}
	ext := ""
	if e.Type != nil && *e.Type != "" {
		ext = "." + strings.ToLower(*e.Type)
	}
	return e.ID + ext
}

func sanitize(name string) string {
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	name = strings.TrimSpace(name)
	if name == "" || name == "." || name == ".." {
		return "unnamed"
	}
	return name
}

func strOr(s *string, fallback string) string {
	if s == nil {
		return fallback
	}
	return *s
}

func algoOrLegacy(algo string) string {
	if algo == "" {
		return "legacy"
	}
	return algo
}
