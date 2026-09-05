// Verify re-checks a local latch-backup/ directory: every live manifest entry
// must have a blob whose sha256 matches its content hash. It does not need
// the credential — naming hashes authenticate content.
package backup

import (
	"fmt"
	"os"

	"latchd/internal/cryptoutil"
)

// VerifyDir checks blob presence + content hashes against the stored
// manifest. Needs the decrypted manifest, so callers unlock first.
func VerifyManifest(t Target, m Manifest) error {
	var missing, corrupt []string
	for _, h := range LiveHashes(m) {
		raw, err := os.ReadFile(t.BlobPath(h))
		if err != nil {
			missing = append(missing, short(h))
			continue
		}
		if cryptoutil.Sha256Hex(raw) != h {
			corrupt = append(corrupt, short(h))
		}
	}
	if len(missing) > 0 || len(corrupt) > 0 {
		return &VerifyError{Missing: missing, Corrupt: corrupt}
	}
	return nil
}

// VerifyError names the blobs that failed verification (truncated hashes).
type VerifyError struct {
	Missing []string
	Corrupt []string
}

func (e *VerifyError) Error() string {
	return fmt.Sprintf("backup verification failed: %d missing, %d corrupt",
		len(e.Missing), len(e.Corrupt))
}

// VerifyDir is a credential-less self-consistency check: every stored blob
// file must hash to its own name. Full entry-level verification (manifest
// coverage) happens in VerifyManifest after unlock.
func VerifyDir(t Target) error {
	var corrupt []string
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
				raw, err := os.ReadFile(t.BlobPath(name[:64]))
				if err != nil || cryptoutil.Sha256Hex(raw) != name[:64] {
					corrupt = append(corrupt, short(name[:64]))
				}
			}
		}
	}
	if len(corrupt) > 0 {
		return &VerifyError{Corrupt: corrupt}
	}
	return nil
}
