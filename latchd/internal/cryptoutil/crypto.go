// Package cryptoutil mirrors Locker's Dart crypto (lib/crypto/) in Go so the
// latchd desktop companion can verify, browse, and export phone backups.
//
// Wire formats (must stay in sync with the Dart side):
//   manifest envelope: [16-byte IV][AES-256-GCM ciphertext+16B tag]
//   keybundle.json: {wrappedKey, wrapSalt, wrapIv (base64),
//     argon2:{t,m,p}} — KWK = Argon2id(credential, wrapSalt, t, m KiB, p)
//   file blobs: GCM v2 magic "LKR2"+ver(1)+LE size(4), GCM v1 "LKRG"+LE size,
//     CTR legacy "LKRS"+LE size (AES-CTR, full-16B big-endian counter),
//     per-file key = PBKDF2-HMAC-SHA256(masterKey, salt, iterations, 32B).
package cryptoutil

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"fmt"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/pbkdf2"
)

// Argon2Params carries the t/m/p triple from keybundle.json (m in KiB).
type Argon2Params struct {
	T uint32
	M uint32
	P uint8
}

// Keybundle is the password-wrapped master key served at GET /keybundle.
type Keybundle struct {
	WrappedKey []byte
	WrapSalt   []byte
	WrapIV     []byte
	Argon2     Argon2Params
}

// UnwrapKeybundle re-derives the KWK from credential and unwraps the master
// key. A wrong password fails GCM auth; the error is deliberately generic so
// callers cannot distinguish it from corruption.
func UnwrapKeybundle(bundle Keybundle, credential string) ([]byte, error) {
	kwk := argon2.IDKey([]byte(credential), bundle.WrapSalt, bundle.Argon2.T, bundle.Argon2.M, bundle.Argon2.P, 32)
	master, err := gcmOpen(kwk, bundle.WrapIV, bundle.WrappedKey)
	if err != nil {
		return nil, fmt.Errorf("cannot unlock backup")
	}
	if len(master) != 32 {
		return nil, fmt.Errorf("cannot unlock backup")
	}
	return master, nil
}

// DecryptManifest opens the [16-byte IV][GCM ciphertext] envelope.
func DecryptManifest(blob, masterKey []byte) ([]byte, error) {
	if len(blob) < 17 {
		return nil, fmt.Errorf("manifest blob too short")
	}
	pt, err := gcmOpen(masterKey, blob[:16], blob[16:])
	if err != nil {
		return nil, fmt.Errorf("cannot unlock backup")
	}
	return pt, nil
}

// DeriveFileKeyRaw derives a 32-byte file key from raw master key + salt.
func DeriveFileKeyRaw(masterKey, salt []byte, iterations int) []byte {
	return pbkdf2.Key(masterKey, salt, iterations, 32, sha256.New)
}

// Sha256Hex names blobs in latch-backup/ and verifies content on read.
func Sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// DecryptFileBlob decrypts one vault file blob with its manifest metadata.
// ivB64 is the base64 nonce/IV from entry.encryptionIv; saltB64/iterations
// feed the per-file key. CBC ("LKR_"/legacy) is decrypt-only on the phone
// and unsupported here — the caller should surface that per file.
func DecryptFileBlob(blob []byte, masterKey []byte, ivB64, saltB64 string, iterations int, algorithm string) ([]byte, error) {
	salt, err := base64.StdEncoding.DecodeString(saltB64)
	if err != nil {
		return nil, fmt.Errorf("bad file salt: %w", err)
	}
	iv, err := base64.StdEncoding.DecodeString(ivB64)
	if err != nil {
		return nil, fmt.Errorf("bad file iv: %w", err)
	}
	fileKey := DeriveFileKeyRaw(masterKey, salt, iterations)
	if len(blob) < 8 {
		return nil, fmt.Errorf("blob too short")
	}
	magic := string(blob[:4])
	size := binary.LittleEndian.Uint32(blob[4:8])
	switch magic {
	case "LKR2":
		// v2: magic(4) + version(1) + LE size(4); body at [9:].
		if len(blob) < 9 {
			return nil, fmt.Errorf("v2 blob too short")
		}
		if blob[4] != 1 {
			return nil, fmt.Errorf("unsupported blob version %d", blob[4])
		}
		size = binary.LittleEndian.Uint32(blob[5:9])
		pt, err := gcmOpen(fileKey, iv, blob[9:])
		if err != nil {
			return nil, fmt.Errorf("cannot decrypt file")
		}
		return checkSize(pt, size)
	case "LKRG":
		pt, err := gcmOpen(fileKey, iv, blob[8:])
		if err != nil {
			return nil, fmt.Errorf("cannot decrypt file")
		}
		return checkSize(pt, size)
	case "LKRS":
		if len(iv) != 16 {
			return nil, fmt.Errorf("CTR blob needs a 16-byte iv")
		}
		block, err := aes.NewCipher(fileKey)
		if err != nil {
			return nil, err
		}
		pt := make([]byte, len(blob)-8)
		cipher.NewCTR(block, iv).XORKeyStream(pt, blob[8:])
		return checkSize(pt, size)
	default:
		return nil, fmt.Errorf("unsupported blob format")
	}
}

// gcmOpen opens AES-256-GCM with an arbitrary-size nonce (Locker uses
// 16-byte IVs, so the cipher is sized to the nonce at hand).
func gcmOpen(key, nonce, ct []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCMWithNonceSize(block, len(nonce))
	if err != nil {
		return nil, err
	}
	return gcm.Open(nil, nonce, ct, nil)
}

// GcmSeal is the test/CLI counterpart of gcmOpen (same nonce flexibility).
func GcmSeal(key, nonce, pt []byte) ([]byte, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCMWithNonceSize(block, len(nonce))
	if err != nil {
		return nil, err
	}
	return gcm.Seal(nil, nonce, pt, nil), nil
}

func checkSize(pt []byte, size uint32) ([]byte, error) {
	if uint32(len(pt)) != size {
		return nil, fmt.Errorf("size mismatch: header says %d, got %d", size, len(pt))
	}
	return pt, nil
}
