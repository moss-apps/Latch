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
	cd $(PB_MODULE) && CGO_ENABLED=0 go build -o ../../locker-pb $(PB_PKG)

## Vendor the canonical JS editor types so the `/// <reference>` in each
## migration resolves. Regenerable, gitignored — run after a PB version bump.
pb-types:
	@mkdir -p $(PB_MODULE)/pb_data
	@cp "$$(go env GOMODCACHE)/github.com/pocketbase/pocketbase@$(PB_VERSION)/plugins/jsvm/internal/types/generated/types.d.ts" \
		$(PB_MODULE)/pb_data/types.d.ts
	@echo "-> $(PB_MODULE)/pb_data/types.d.ts ($(PB_VERSION))"

clean:
	rm -rf $(JNI_DIR)/arm64-v8a/libpocketbase.so locker-pb
