package cryptoutil

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"testing"

	"golang.org/x/crypto/pbkdf2"
)

// dartV2Blob mirrors the on-disk GCM v2 container written by the phone
// (lib/services/crypto_isolate_pool.dart): magic "LKR2", version 0x02,
// little-endian plaintext size, GCM ciphertext+tag.
func dartV2Blob(t *testing.T, fileKey, iv, pt []byte) []byte {
	t.Helper()
	ct, err := GcmSeal(fileKey, iv, pt)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]byte, 9+len(ct))
	copy(out, "LKR2")
	out[4] = 0x02
	binary.LittleEndian.PutUint32(out[5:9], uint32(len(pt)))
	copy(out[9:], ct)
	return out
}

func TestDecryptFileBlobGcmV2(t *testing.T) {
	master := bytes.Repeat([]byte{0x42}, 32)
	salt := bytes.Repeat([]byte{0x24}, 32)
	iv := bytes.Repeat([]byte{0x11}, 16)
	pt := []byte("desktop backup interop")

	ivB64 := base64.StdEncoding.EncodeToString(iv)
	saltB64 := base64.StdEncoding.EncodeToString(salt)

	for _, iters := range []int{100000, 600000} {
		fileKey := pbkdf2.Key(master, salt, iters, 32, sha256.New)
		blob := dartV2Blob(t, fileKey, iv, pt)

		got, err := DecryptFileBlob(blob, master, ivB64, saltB64, iters, "aes256Gcm")
		if err != nil {
			t.Fatalf("iters=%d: %v", iters, err)
		}
		if !bytes.Equal(got, pt) {
			t.Fatalf("iters=%d: plaintext mismatch", iters)
		}
	}
}

func TestDecryptFileBlobRejectsUnknownVersion(t *testing.T) {
	master := bytes.Repeat([]byte{0x42}, 32)
	salt := bytes.Repeat([]byte{0x24}, 32)
	iv := bytes.Repeat([]byte{0x11}, 16)
	fileKey := pbkdf2.Key(master, salt, 100000, 32, sha256.New)
	blob := dartV2Blob(t, fileKey, iv, []byte("data"))
	blob[4] = 0x03

	_, err := DecryptFileBlob(blob, master,
		base64.StdEncoding.EncodeToString(iv),
		base64.StdEncoding.EncodeToString(salt),
		100000, "aes256Gcm")
	if err == nil {
		t.Fatal("expected unknown version to be rejected")
	}
}
