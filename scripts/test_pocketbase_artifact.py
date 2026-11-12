"""Packaging regression tests; no devices, servers, tool installs, or live data."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import pocketbase_artifact as artifact


class PocketBaseArtifactTest(unittest.TestCase):
    def setUp(self):
        tmp_root = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
        self.tmp = tempfile.TemporaryDirectory(prefix="latch-packaging-test-", dir=tmp_root)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.module = self.root / "pocketbase"
        self.module.mkdir()
        (self.module / "go.mod").write_text(
            "module example.test/pb\n\ngo 1.27\n\nrequire (\n"
            " github.com/pocketbase/pocketbase v0.40.4\n"
            " modernc.org/sqlite v1.57.0\n)\n")
        (self.module / "go.sum").write_text("locked module checksums\n")
        (self.module / "main.go").write_text("package main\n")
        self.binary = self.root / "libpocketbase.so"
        self.write_marker()
        self.settings = {"GOOS": "android", "GOARCH": "arm64", "CGO_ENABLED": "0"}
        self.deps = {"github.com/pocketbase/pocketbase": "v0.40.4",
                     "modernc.org/sqlite": "v1.57.0"}
        mock = patch.object(artifact, "read_build_info", side_effect=self.build_info)
        mock.start()
        self.addCleanup(mock.stop)

    def write_marker(self):
        self.binary.write_bytes(b"ELF-test\0LATCH_PB_SOURCE_SHA256:"
                                + artifact.source_digest(self.root).encode() + b":END\0")

    def build_info(self, _path):
        return "test: go1.27.0\n", self.settings, self.deps

    def verify(self, path=None):
        return artifact.verify_binary(path or self.binary, root=self.root)

    def test_current_binary_passes(self):
        self.assertEqual(self.verify(), "v0.40.4")

    def test_stale_native_source_is_rejected(self):
        (self.module / "main.go").write_text("package main // changed\n")
        with self.assertRaisesRegex(ValueError, "stale native source"):
            self.verify()

    def test_new_embedded_migration_is_rejected(self):
        (self.module / "new_migration.js").write_text("migrate(() => {});\n")
        with self.assertRaisesRegex(ValueError, "stale native source"):
            self.verify()

    def test_module_lock_change_is_rejected(self):
        (self.module / "go.sum").write_text("changed checksums\n")
        with self.assertRaisesRegex(ValueError, "stale native source"):
            self.verify()

    def test_runtime_data_does_not_affect_source_digest(self):
        data = self.module / "pb_data"
        data.mkdir()
        (data / "scratch.js").write_text("not a bundled migration\n")
        self.verify()

    def test_old_dependency_is_rejected(self):
        self.deps["github.com/pocketbase/pocketbase"] = "v0.39.10"
        with self.assertRaisesRegex(ValueError, "differs from pocketbase/go.mod"):
            self.verify()

    def test_wrong_platform_or_cgo_is_rejected(self):
        for key, wrong in {"GOOS": "linux", "GOARCH": "amd64", "CGO_ENABLED": "1"}.items():
            with self.subTest(key=key):
                old = self.settings[key]
                self.settings[key] = wrong
                with self.assertRaisesRegex(ValueError, "expected " + key):
                    self.verify()
                self.settings[key] = old

    def test_missing_marker_is_rejected(self):
        self.binary.write_bytes(b"ELF-test-no-provenance")
        with self.assertRaisesRegex(ValueError, "missing/stale native source"):
            self.verify()

    def test_old_or_missing_toolchain_metadata_is_rejected(self):
        for metadata in ("test: go1.26.5\n", ""):
            with self.subTest(metadata=metadata):
                with patch.object(artifact, "read_build_info", return_value=
                                  (metadata, self.settings, self.deps)):
                    with self.assertRaisesRegex(ValueError, "toolchain metadata"):
                        self.verify()

    def test_bundle_and_apk_payloads_are_verified_without_execution(self):
        for prefix in ("lib/", "base/lib/"):
            with self.subTest(prefix=prefix):
                bundle = self.root / "app.zip"
                with zipfile.ZipFile(bundle, "w") as archive:
                    archive.writestr(prefix + "arm64-v8a/libpocketbase.so",
                                     self.binary.read_bytes())
                artifact.verify(bundle, root=self.root)

    def test_bundle_missing_sidecar_is_rejected(self):
        bundle = self.root / "missing.aab"
        with zipfile.ZipFile(bundle, "w") as archive:
            archive.writestr("base/manifest/AndroidManifest.xml", "fixture")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            artifact.verify(bundle, root=self.root)

    def test_ambiguous_bundle_payload_is_rejected(self):
        bundle = self.root / "ambiguous.zip"
        with zipfile.ZipFile(bundle, "w") as archive:
            for prefix in ("lib/", "base/lib/"):
                archive.writestr(prefix + "arm64-v8a/libpocketbase.so",
                                 self.binary.read_bytes())
        with self.assertRaisesRegex(ValueError, "exactly one"):
            artifact.verify(bundle, root=self.root)

    def test_build_failure_preserves_previous_binary(self):
        before = self.binary.read_bytes()
        with patch.object(artifact.subprocess, "run", side_effect=
                          subprocess.CalledProcessError(1, ["go", "build"])):
            with self.assertRaises(subprocess.CalledProcessError):
                artifact.build(self.binary, root=self.root)
        self.assertEqual(self.binary.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
