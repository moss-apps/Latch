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
| 2 | Session locking | **Not started** | High — recommended next feature |
| 3 | Large-vault sync and conflict recovery | **Not started** | High |
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

**Status: Not started**

**Recommended next feature.** The existing security model includes PIN/password/biometric authentication and Android auto-kill behavior, but there is no in-session lock, “Lock now” action, or inactivity relock flow. The existing refactor roadmap also identifies session locking as the prerequisite for safely evicting cached keys.

| Item | Work | Acceptance criteria |
|---|---|---|
| 2.1 | Add a central locked/unlocked session state and a “Lock now” action. | Locking blocks protected routes and returns the user to authentication without restarting the app. |
| 2.2 | Add configurable relock triggers. | Users can choose an inactivity timeout and background behavior. Lock timing is predictable when switching to a picker, biometric prompt, or external app. |
| 2.3 | Clear sensitive in-memory state on lock. | Cached keys and sensitive decrypted temporary content are evicted or invalidated; lock does not delete vault data. |
| 2.4 | Cover lifecycle and navigation edge cases. | Returning from permitted system interactions does not unexpectedly lock mid-operation or leave protected content visible. Back navigation cannot bypass the lock. |
| 2.5 | Add security and lifecycle tests. | Tests cover manual lock, timeout, background/foreground, route gating, and an allowed external/system interaction. |

**Likely areas:** app initialization/lifecycle handling, authentication routing, `lib/services/auto_kill_service.dart`, encryption key/cache ownership, and sensitive viewer/editor routes. Coordinate this work with `docs/refactor_roadmap.md` before implementing key eviction.

## Phase 3 — Large-vault sync and conflict recovery

**Status: Not started**

| Item | Work | Acceptance criteria |
|---|---|---|
| 3.1 | Stream WebDAV blob transfers and hashes instead of loading whole files into memory. | Large files sync without allocating a full extra in-memory copy; interrupted transfers fail safely and can be retried. |
| 3.2 | Surface byte-level progress and cancellation. | The user sees current file, transferred bytes, total bytes, and a cancellation action. Cancellation leaves the manifest in a consistent state. |
| 3.3 | Improve conflict recovery. | Conflicts are inspectable and recoverable; the user's local or remote copy is not silently lost under last-write-wins behavior. |
| 3.4 | Add tests for interruption and conflict outcomes. | Tests prove retry safety, manifest commit ordering, and preservation of both versions or an explicit user-selected resolution. |

**Review findings:** `SyncService` currently reads and uploads complete blobs as byte arrays, and `syncNow` invokes the engine in an isolate without forwarding per-file progress. Conflicts are summarized after last-write-wins reconciliation; the current behavior does not provide a choose/keep-both flow.

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
