## Embedded PocketBase sidecar build.
##
## `make pb` cross-compiles the locker-pb wrapper for android/arm64 with the
## pure-Go modernc sqlite backend (CGO disabled — no NDK), strips symbols, and
## places the binary into jniLibs so Android extracts it at install time.
## The lib*.so naming is what makes PackageManager copy it into nativeLibraryDir.

PB_MODULE  := pocketbase
PB_PKG     := ./cmd/locker-pb
LDFLAGS    := -s -w
JNI_DIR    := android/app/src/main/jniLibs
## arm64-v8a only for v1 (open decision 2). Add armeabi-v7a / x86_64 if needed.
ABIS       := arm64-v8a
## PocketBase version is pinned in pocketbase/go.mod; resolve it for pb-types.
PB_VERSION := $(shell cd $(PB_MODULE) && go list -m -f '{{.Version}}' github.com/pocketbase/pocketbase)

GOOS       := android
GOARCH     := arm64
CGO        := 0

.PHONY: pb pb-linux pb-types clean

pb:
	@set -e; for abi in $(ABIS); do \
		case $$abi in \
			arm64-v8a)   goarch=arm64 ;; \
			armeabi-v7a) goarch=arm ;; \
			x86_64)      goarch=amd64 ;; \
			*) echo "unknown abi: $$abi" >&2; exit 1 ;; \
		esac; \
		out=$(CURDIR)/$(JNI_DIR)/$$abi/libpocketbase.so; \
		mkdir -p $$(dirname $$out); \
		echo ">> building $$abi ($$goarch)"; \
		(cd $(PB_MODULE) && GOOS=$(GOOS) GOARCH=$$goarch CGO_ENABLED=$(CGO) \
			go build -ldflags="$(LDFLAGS)" -trimpath -o $$out $(PB_PKG)); \
		echo "   -> $(JNI_DIR)/$$abi/libpocketbase.so ($$(du -h $$out | cut -f1))"; \
	done

## Local native build for quick desktop verification of the wrapper/migrations.
pb-linux:
	cd $(PB_MODULE) && CGO_ENABLED=0 go build -o $(CURDIR)/locker-pb $(PB_PKG)

## Vendor the canonical JS editor types so the `/// <reference>` in each
## migration resolves. Regenerable, gitignored — run after a PB version bump.
pb-types:
	@mkdir -p $(PB_MODULE)/pb_data
	@cp "$$(go env GOMODCACHE)/github.com/pocketbase/pocketbase@$(PB_VERSION)/plugins/jsvm/internal/types/generated/types.d.ts" \
		$(PB_MODULE)/pb_data/types.d.ts
	@echo "-> $(PB_MODULE)/pb_data/types.d.ts ($(PB_VERSION))"

clean:
	rm -rf $(JNI_DIR)/arm64-v8a/libpocketbase.so locker-pb

## Desktop backup companion (P6.2, docs/desktop_backup.md).
## latchd pulls the encrypted vault from the phone into latch-backup/.
LATCHD_MODULE := latchd
LATCHD_BIN    := latchd/latchd
## Release version: the app-version tag at HEAD (0.x.y-beta.z, same as
## mobile), else "dev". Exact match so dirty checkouts never stamp.
LATCHD_VERSION ?= $(shell v=$$(git describe --tags --exact-match --match '0.*' 2>/dev/null); echo $${v:-dev})

.PHONY: latchd-test latchd-web latchd-release clean-latchd

latchd: $(shell find $(LATCHD_MODULE) -name '*.go' -o -path '*internal/webui/web/*' -type f)
	cd $(LATCHD_MODULE) && CGO_ENABLED=0 go build -trimpath -o $(CURDIR)/$(LATCHD_BIN) ./cmd/latchd
	@echo "-> $(LATCHD_BIN)"

latchd-test:
	cd $(LATCHD_MODULE) && go test ./...

## Rebuild the latchd web UI from web-src/ into internal/webui/web/.
## The dist is committed, so this needs Node and is only for UI work.
latchd-web:
	cd $(LATCHD_MODULE)/web-src && npm install && npm run build

## Cross-build release artifacts into dist/ — the same set the
## release-latchd.yml workflow attaches on latchd-v* tags. Run at a tag.
latchd-release:
	@set -e; mkdir -p dist; \
	for target in linux/amd64 linux/arm64 windows/amd64; do \
		os=$${target%/*}; arch=$${target#*/}; ext=; \
		if [ "$$os" = windows ]; then ext=.exe; fi; \
		echo ">> building $$os/$$arch"; \
		(cd $(LATCHD_MODULE) && CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch \
			go build -trimpath -ldflags "-s -w -X main.version=$(LATCHD_VERSION)" \
			-o $(CURDIR)/dist/latchd-$$os-$$arch$$ext ./cmd/latchd); \
	done; \
	cd dist && sha256sum latchd-* > SHA256SUMS; \
	echo "-> dist/ (latchd $(LATCHD_VERSION))"

clean-latchd:
	rm -f $(LATCHD_BIN)
