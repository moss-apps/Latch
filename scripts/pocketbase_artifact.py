#!/usr/bin/env python3
"""Build/check PocketBase artifacts. Never installs or executes an app/sidecar."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MARKER = re.compile(rb"LATCH_PB_SOURCE_SHA256:([0-9a-f]{64}):END")
ABIS = {"arm64": "arm64-v8a", "arm": "armeabi-v7a", "amd64": "x86_64"}


def source_digest(root=ROOT):
    """Fingerprint native sources, embedded JS, and locked module inputs."""
    module = root / "pocketbase"
    inputs = [module / "go.mod", module / "go.sum"]
    inputs += [
        p for p in module.rglob("*")
        if p.is_file() and p.suffix in {".go", ".js"}
        and "pb_data" not in p.relative_to(module).parts
    ]
    digest = hashlib.sha256()
    for path in sorted(inputs):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def read_build_info(path):
    # `go version -m` reads the executable as data; it does not run it.
    output = subprocess.run(
        ["go", "version", "-m", str(path)], check=True,
        capture_output=True, text=True,
    ).stdout
    settings, deps = {}, {}
    for line in output.splitlines():
        fields = line.strip().split("\t")
        if fields[0] == "build" and len(fields) == 2:
            key, _, value = fields[1].partition("=")
            settings[key] = value
        elif fields[0] == "dep" and len(fields) >= 3:
            deps[fields[1]] = fields[2]
    return output, settings, deps


def verify_binary(path, arch="arm64", root=ROOT):
    output, settings, deps = read_build_info(path)
    for key, expected in {"GOOS": "android", "GOARCH": arch,
                          "CGO_ENABLED": "0"}.items():
        if settings.get(key) != expected:
            raise ValueError(f"{path}: expected {key}={expected}")
    mod = (root / "pocketbase/go.mod").read_text()
    for name in ("github.com/pocketbase/pocketbase", "modernc.org/sqlite"):
        expected = re.search(r"(?m)^\s*" + re.escape(name) + r"\s+(\S+)", mod)
        if expected is None or deps.get(name) != expected[1]:
            raise ValueError(f"{path}: {name} differs from pocketbase/go.mod")
    required = re.search(r"(?m)^go (\d+)\.(\d+)", mod)
    actual = re.search(r": go(\d+)\.(\d+)", next(iter(output.splitlines()), ""))
    if (required is None or actual is None or
            tuple(map(int, actual.groups())) < tuple(map(int, required.groups()))):
        raise ValueError(f"{path}: missing/unsupported Go toolchain metadata")
    markers = {m.decode() for m in MARKER.findall(path.read_bytes())}
    if markers != {source_digest(root)}:
        raise ValueError(f"{path}: missing/stale native source fingerprint; run make pb")
    return deps["github.com/pocketbase/pocketbase"]


def verify(path, arch="arm64", root=ROOT):
    if not zipfile.is_zipfile(path):
        version = verify_binary(path, arch, root)
    else:
        # Accept APK and AAB layouts. Refuse missing/duplicate native entries.
        abi = ABIS[arch]
        candidates = {f"lib/{abi}/libpocketbase.so",
                      f"base/lib/{abi}/libpocketbase.so"}
        with zipfile.ZipFile(path) as archive:
            matches = [n for n in archive.namelist() if n in candidates]
            if len(matches) != 1:
                raise ValueError(f"{path}: expected exactly one {abi} PocketBase entry")
            tmp_root = "/tmp/opencode" if Path("/tmp/opencode").is_dir() else None
            with tempfile.TemporaryDirectory(prefix="latch-pb-check-", dir=tmp_root) as tmp:
                binary = Path(tmp) / "libpocketbase.so"
                binary.write_bytes(archive.read(matches[0]))
                version = verify_binary(binary, arch, root)
    print(f"Verified {path}: {version}, android/{arch}, source {source_digest(root)}")


def build(path, arch="arm64", root=ROOT):
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    before = source_digest(root)
    # Compile to a sibling temporary file; a failed build leaves the old binary.
    with tempfile.TemporaryDirectory(prefix=".pb-build-", dir=path.parent) as tmp:
        output = Path(tmp) / "libpocketbase.so"
        env = {**os.environ, "GOOS": "android", "GOARCH": arch,
               "CGO_ENABLED": "0", "GOWORK": "off"}
        subprocess.run([
            "go", "build", "-mod=readonly", "-trimpath", "-buildvcs=false",
            "-ldflags=-s -w -X main.buildSource=LATCH_PB_SOURCE_SHA256:"
            + before + ":END", "-o", str(output), "./cmd/locker-pb",
        ], cwd=root / "pocketbase", env=env, check=True)
        if source_digest(root) != before:
            raise ValueError("PocketBase sources changed during build; retry")
        verify_binary(output, arch, root)
        output.replace(path)
    verify(path, arch, root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "verify"])
    parser.add_argument("path", type=Path, help="binary output, or existing binary/APK/AAB")
    parser.add_argument("--arch", choices=ABIS, default="arm64")
    args = parser.parse_args()
    try:
        (build if args.action == "build" else verify)(args.path, args.arch)
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        parser.exit(1, f"PocketBase artifact check failed: {exc}\n")


if __name__ == "__main__":
    main()
