# Latch Product Improvement Roadmap

This roadmap turns the product review into phased, actionable work. Phases are ordered to reduce data-loss and security risks before expanding the feature set. Status reflects a source and documentation review performed on 2026-10-02; it does not imply that runtime verification was performed.

## Status legend

- **Done** — implementation is present and its acceptance criteria have been verified.
- **In progress** — implementation has started but acceptance criteria are not all met.
- **Not started** — proposed work with no implementation identified in the review.
- **Existing** — capability already exists; follow-up work in this roadmap is an improvement to it.

> Status is intentionally conservative. Work should only move to **Done** after implementation and relevant tests are reviewed. Existing capabilities are marked separately from proposed improvements.

## At a glance

| Phase | Focus | Status | Priority |
|---|---|---|---|
| 0 | Reliability and data integrity | **Done** | Critical |
| 1 | Protection defaults and import clarity | **Done** | High |
| 2 | Session locking | **Done** | High |
| 3 | Large-vault sync and conflict recovery | **Done** | High |
| 4 | Import convenience and discovery | **Not started** | Medium |
| 5 | Recovery and product polish | **Not started** | Medium |

## Phase 0 — Reliability and data integrity

**Status: Done**

Fix the paths where failures can leave the vault's index, disk, or remote state inconsistent. Land these changes before new data-management features.

Implemented 2026-10-02: failure-safe bulk deletion returns per-file removed/failed results and retains failed entries; WebDAV reads treat only a confirmed 404 as absent and propagate transport/auth/server errors; import results report retained originals instead of claiming deletion. Regression tests cover all failure cases (`flutter test`: 164 passing; `flutter analyze` clean).

| Item | Work | Acceptance criteria |
|---|---|---|
| 0.1 | Make bulk deletion failure-safe in `lib/services/file_service.dart`. | Failed file or thumbnail deletion does not remove the corresponding vault entry. Successful deletions remain removed. The caller can identify failures and retry them. |
| 0.2 | Make WebDAV reads distinguish missing resources from transport, authentication, and server failures in `lib/services/remote/webdav_store.dart`. | Only a confirmed not-found result is treated as an absent manifest/blob. Other errors propagate to sync. A failed manifest read cannot be interpreted as a first sync or lead to manifest replacement. |
| 0.3 | Add regression tests for the failure cases above. | Tests cover failed bulk deletion and the WebDAV not-found, unauthorized, and unreachable cases. Sync aborts without committing when the existing manifest could not be read. |
| 0.4 | Review import outcomes when original-media deletion fails. | The user sees whether import succeeded, whether originals were deleted, and what action remains; no success message implies originals were removed when they remain. |

**Likely areas:** `lib/services/file_service.dart`, `lib/services/remote/webdav_store.dart`, `lib/services/sync_service.dart`, `lib/services/file_import_service.dart`, and their existing tests.

## Phase 1 — Protection defaults and import clarity

**Status: Done**

Make it easy to understand what is encrypted and ensure per-file choices behave predictably.

Implemented 2026-10-02: The encryption default stays **off** for new installations (product decision: hiding remains the default promise and encryption is an explicit opt-in), and existing saved choices are preserved. Per-file import choices now take precedence over the global "Encrypt New Files" setting through `FileService.resolveEncryption` (per-file → call-level → global → unencrypted); both logical-OR sites were removed, and the import sheet lets users override individual files even while the global toggle is on. Duplicate handling now verifies content: filename and size shortlist candidates, then a sha256 comparison of the source against the stored plaintext payload decides whether a duplicate is safely present. `VaultedFile.contentHash` records that hash for new and lazily hashed entries, and originals are only removed when content is verified present. `ImportResult` and `OfficeImportResult` expose imported, skipped-duplicate, failed, and retained-original counts, which batch import toasts now display. Checks: `flutter analyze` clean; `flutter test` 170 passing.

| Item | Work | Acceptance criteria |
|---|---|---|
| 1.1 | Decide and implement the encryption default for new installations. | The chosen default is documented and reflected consistently in setup, settings, and import flows. Existing users' saved choices are preserved. |
| 1.2 | Define precedence between the global “Encrypt New Files” setting and per-file import choices. | A user's explicit per-file choice is honored, or the UI clearly explains why encryption is mandatory. Tests cover both global and per-file settings. |
| 1.3 | Explain “hidden” versus “encrypted” at import and in security settings. | Users can tell whether stored file bytes are encrypted, whether thumbnails expose previews, and whether source originals remain on the device. |
| 1.4 | Improve duplicate verification before skipping or deleting source media. | Filename and size can shortlist candidates, but content comparison verifies duplicates where needed. A source original is never removed unless its content is safely present in the vault. |
| 1.5 | Report import results per outcome. | Imported, skipped-as-duplicate, failed, and original-retained counts are visible after a batch import. |

**Decision record:** Keep `VaultSettings.encryptionEnabled` defaulting to `false` for new installations and preserve stored settings for existing users, so no migration was required. Previously the import path combined the per-file choice with the global setting using logical OR (`lib/services/file_service.dart`), so a per-file opt-out could not override a globally enabled setting; that behavior is replaced by explicit precedence. Duplicate pre-filtering previously trusted filename and size (`lib/services/file_import_service.dart`); it now confirms candidate content before skipping or deleting source originals.

## Phase 2 — In-session locking

**Status: Done**

Implemented 2026-10-06: `SessionService` owns the locked/unlocked state, inactivity and background deadlines, and scoped system-interaction exemptions. “Lock now” is available in the vault drawer and Security settings. Locking replaces the entire protected navigator and provider scope with authentication, disposing open viewers, editors, and dialogs; back navigation cannot restore them. App content is covered while inactive or backgrounded, including during permitted system interactions.

Relock settings default to **5 minutes of inactivity** and **immediate background locking**, with explicit “Never” options. Touch, scrolling, hardware keys, and soft-keyboard editing count as activity. Returning to the foreground checks wall-clock deadlines even if the OS suspended Dart timers. Pickers, permissions, biometric prompts, and explicitly opened external files suspend automatic relocking until the interaction returns; nested interactions remain exempt until all finish. Inactivity restarts on return, and manual locking revokes any outstanding exemption. Android's existing auto-kill default and saved delay are preserved; the new “Close app in background” switch lets users turn it off to use relocking without process termination.

Lock cleanup zeroes cached master, decoy, and per-file key buffers, clears pending credentials, thumbnails, image caches, and note/password caches, detaches the PocketBase session, stops key-holding crypto/sync/conversion workers and video compression, and removes owned decrypted scratch files. Generation checks reject late key derivation, previews, and metadata results, and prevent PocketBase from sealing new records with evicted keys. Authentication waits for cleanup; a cleanup failure keeps the vault locked and offers a retry. Persisted vault files and stored key material are preserved, with a lock → reauthenticate → decrypt round-trip verified.

| Item | Work | Acceptance criteria | Status |
|---|---|---|---|
| 2.1 | Add a central locked/unlocked session state and a “Lock now” action. | Locking blocks protected routes and returns the user to authentication without restarting the app. | **Done** |
| 2.2 | Add configurable relock triggers. | Users can choose an inactivity timeout and background behavior. Lock timing is predictable when switching to a picker, biometric prompt, or external app. | **Done** |
| 2.3 | Clear sensitive in-memory state on lock. | Cached keys and sensitive decrypted temporary content are evicted or invalidated; lock does not delete vault data. | **Done** |
| 2.4 | Cover lifecycle and navigation edge cases. | Returning from permitted system interactions does not unexpectedly lock mid-operation or leave protected content visible. Back navigation cannot bypass the lock. | **Done** |
| 2.5 | Add security and lifecycle tests. | Tests cover manual lock, timeout, background/foreground, route gating, and an allowed external/system interaction. | **Done** |

**Checks:** `flutter test --no-pub`: 193 passing; `flutter analyze --no-pub`: clean; `flutter build apk --debug --no-pub`: successful. Regression coverage includes cleanup failure/retry, route/dialog disposal and back navigation, lifecycle deadlines, nested/system hand-offs, soft-keyboard activity, active worker cancellation, partial plaintext removal, key eviction and reauthentication, and late PocketBase reads/writes. Device-level picker/biometric smoke testing remains a release check; lifecycle behavior was verified with automated tests, not physical-device interaction.

**Key-eviction coordination:** `docs/refactor_roadmap.md` item 0.2 is now implemented. Session cleanup calls the non-destructive `EncryptionService.evictCachedKeys()`; `resetKeys()` remains reserved for destructive vault reset.

## Phase 3 — Large-vault sync and conflict recovery

**Status: Done**

Implemented 2026-10-06. The rewrite replaces whole-buffer transfers and last-write-wins reconciliation:

- **Streaming transfers.** Blobs are hashed and uploaded/downloaded as streams through staging files (`PUT` to a temporary name, verify, then `MOVE` into place); pulls write to a `.partial` file, verify sha256, then move into the vault. No full in-memory copy, and interrupted transfers leave the previous canonical blob untouched.
- **Durable, encrypted sync state.** A per-target baseline and a write-ahead journal live under `<vault>/.sync-state/<targetId>.state|.journal`, AES-GCM-encrypted with the master key; explicit deletions are recorded in secure storage at delete time. Crash, lock-kill, or a failed local index write cannot advance the baseline or drop either version.
- **Snapshots, not clocks.** Reconcile compares a content fingerprint of each entry against the local view, the remote manifest, and the last agreed baseline; timestamp skew cannot decide an outcome.
- **Review-first conflicts.** Diverged files become `needsReview` conflicts with local/remote/keep-both/later choices; keep-both writes a hash-verified separate copy with a distinct id. The manifest is never rewritten with a losing version.
- **Safe publication.** `manifest.enc` publication probes the server (DAV header, strong ETag, honored `Overwrite: F` / `If` preconditions) before trusting it and is rejected with a plain-language error when the server would silently ignore revision guards. No silent fallback.
- **Progress and cancellation.** The UI shows phase, file name, per-file and overall bytes (unknown totals stay indeterminate); cancel is cooperative mid-transfer, ignored only for the brief commit step, and lock cleanup still hard-kills the worker. A partial transfer leaves the manifest and both payloads intact and retries cleanly.
- **Payload retention, no GC.** Remote "deletes" are manifest tombstones; superseded and deleted payloads are retained on both sides for recovery. Reclaimed-space GC is deliberately out of scope.

| Item | Work | Acceptance criteria | Status |
|---|---|---|---|
| 3.1 | Stream WebDAV blob transfers and hashes instead of loading whole files into memory. | Large files sync without allocating a full extra in-memory copy; interrupted transfers fail safely and can be retried. | **Done** |
| 3.2 | Surface byte-level progress and cancellation. | The user sees current file, transferred bytes, total bytes, and a cancellation action. Cancellation leaves the manifest in a consistent state. | **Done** |
| 3.3 | Improve conflict recovery. | Conflicts are inspectable and recoverable; the user's local or remote copy is not silently lost under last-write-wins behavior. | **Done** |
| 3.4 | Add tests for interruption and conflict outcomes. | Tests prove retry safety, manifest commit ordering, and preservation of both versions or an explicit user-selected resolution. | **Done** |

**Checks:** `flutter test --no-pub`: 219 passing; `flutter analyze --no-pub`: clean; `flutter build apk --debug --no-pub`: successful. Regression coverage includes streamed staging/MOVE transfers over a loopback WebDAV fixture, publication-precondition rejection, mid-body cancellation, stale-ETag races, corrupt-pull rejection, encrypted-journal recovery after a failed index write, backup-mode remote preservation, every conflict direction and resolution, and worker-scoped cancellation. Physical-device verification (1–2 GB transfers, cancel/retry, mid-sync lock, conflict review, real-server capability probing) is user-run; see `docs/local_server_testing.md` → *Phase 3 hardware guide*.

**Remaining limits (documented, not silent):** album/folder definitions still do not sync (file-level ids are carried); payload GC is deferred in favor of retention; and WebDAV sync does not carry the vault master key, so reinstall/new-device recovery requires the Desktop backup/restore key bundle or the original credential (see `docs/local_server_sync.md` → *Key continuity and reinstall*).

## Phase 4 — Import convenience and discovery

**Status: Not started**

Deliver focused features that make existing vault content easier to add and find.

| Item | Work | Acceptance criteria |
|---|---|---|
| 4.1 | Add Android “Share to Latch” intake for one or multiple files. | Latch appears as a share target, accepts supported content types, and routes items through the existing import, encryption, duplicate, and progress flows. |
| 4.2 | Add saved smart collections. | Users can save useful filters such as Untagged, Unencrypted, Large videos, or Added this month. Results update when vault metadata changes. |
| 4.3 | Make date-range search boundaries intuitive. | Calendar-based start/end dates include the selected days consistently, with tests for boundary timestamps. |

**Review findings:** the Android manifest currently has no `SEND`/`SEND_MULTIPLE` intent filters. Search currently covers filenames, tags, type, dates, favorites, and albums; saved smart filters were not identified.

## Phase 5 — Recovery and product polish

**Status: Not started**

| Item | Work | Acceptance criteria |
|---|---|---|
| 5.1 | Consider a Recently Deleted area with configurable retention. | Deleted items can be restored before expiry; permanent deletion is explicit; storage use and sync behavior are documented. |
| 5.2 | Improve small-screen and large-text navigation behavior. | Bottom navigation remains readable and usable at narrow widths and larger system font scales, with semantics for assistive technology. |
| 5.3 | Refresh README product and setup documentation. | README describes notes, password storage/autofill, WebDAV sync, and current prerequisites accurately. |
| 5.4 | Split the gallery screen into focused components/services. | `gallery_vault_screen.dart` is reduced into maintainable pieces without changing user-visible behavior; existing flows remain covered by tests. |

Recently Deleted requires an explicit product decision on retention, secure-delete timing, backup, and WebDAV tombstone behavior before implementation.

## Existing capabilities

These are already present and should be reused rather than rebuilt:

- **Existing:** encrypted notes and password storage/autofill.
- **Existing:** WebDAV push/two-way sync and conflict detection.
- **Existing:** import progress, duplicate pre-filtering, and gallery-original deletion handling.
- **Existing:** Android screenshot protection and configurable auto-kill delay.
- **Existing:** tags, albums, folders, favorites, and advanced search filters.
- **Existing:** desktop backup/restore and encrypted vault support.

“Existing” means the capability was identified during source review; it does not mark every possible enhancement to that capability as complete.

## Suggested delivery order

1. Complete **Phase 0** and its regression tests.
2. Resolve the product decision in **Phase 1**, then implement and test its import/security behavior.
3. Ship **Phase 2 session locking** as the next major user-facing feature.
4. Prioritize **Phase 3 sync safety/progress** before broadening sync conflict behavior.
5. Select **Share to Latch** or **smart collections** for Phase 4 based on user demand.
6. Start **Recently Deleted** only after its deletion and sync semantics are agreed.

## Updating status

Update the phase summary and the relevant item rows in the same change as implementation. Use **In progress** only when code or tests have landed and work remains. Use **Done** only when acceptance criteria are met and appropriate checks have passed. Record deferred or rejected work with a short rationale instead of leaving it marked as active.
