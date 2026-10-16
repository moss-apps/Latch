# Recently Deleted

## Product decision

Recently Deleted is **local-only**, for both the main and decoy vaults in
separate namespaces. The default retention is **30 days**. Choose **7, 30, or
90 days**, or **Delete immediately**, from Recently Deleted → Retention for
future deletions. Switching to immediate deletion requires confirmation.

Each deletion fixes its own expiry deadline. A later setting change does not
shorten or extend existing deadlines. Restore is permitted only before that
deadline. Cleanup runs on unlock/resume and on an expiry timer while the
protected session exists. Android may suspend/kill the app: expired bytes can
remain until the next unlocked cleanup, but are no longer restorable through
the UI. There is no promised background erasure deadline.

## Deleting, restoring, and storage

- Ordinary Delete moves the stored payload and thumbnail into a private
  `.recently-deleted` directory without decrypting or re-encrypting them.
  Notes and passwords also retain their editor metadata, including IV/salt.
- These items disappear from active lists, search, smart collections, and
  password Autofill. Active-vault counts/storage totals exclude them. Recently
  Deleted reports retained payload/thumbnail bytes separately; storage is not
  reclaimed just by moving an item there.
- Restore preserves the id, file bytes, encryption metadata, tags, favorite
  state, and original dates. It uses unique new paths rather than overwriting
  an occupied old path. Album/folder memberships are restored only where the
  corresponding local definition still exists. A removed note folder is not
  recreated. The sync modification marker is advanced to record restore intent.
- **Delete permanently** and **Empty Recently Deleted** require confirmation.
  Expiry and immediate deletion use the same permanent-removal path. Payloads
  and thumbnails are both removed. Once permanent removal starts, the item is
  not offered for restoration, even if only part of the removal succeeds.
- With Secure Delete enabled, removal attempts overwrite-then-unlink; with it
  disabled, it unlinks normally. Overwrite is **best effort, not guaranteed
  flash erasure** (wear leveling, snapshots, external copies, and device storage
  behavior remain outside Latch's control). Moving into Recently Deleted does
  not overwrite bytes. Import/source-original removal keeps its existing timing.
- Unhide exports a copy and removes the active vault entry using this same
  retention policy; a recoverable vault copy may therefore remain locally.
- Wiping a vault, uninstalling, or clearing app data is not a recoverable Delete.
  Keep backups outside app-private storage.

## Interrupted operations

A strict secure-storage receipt is saved **before** moving bytes or changing
indexes. It is authoritative across legacy/PocketBase index fallback, so stale
rows cannot make a deleted item active again. Notes/password lists apply the
same receipt filter even if updating an editor index failed.

Pending delete/restore/permanent-delete transitions are replayed at the next
unlocked maintenance pass. Use **Retry cleanup** for an immediate retry. A
failed initial receipt write leaves the active item and bytes untouched. A
later failure can leave a hidden pending item instead of an active file: the
receipt and surviving bytes remain available to complete the operation. A
pending restore completes before another action can overwrite its receipt.
Failures are reported rather than treated as successful permanent removal.
Corrupt/unreadable receipt storage fails closed; it is not replaced with an
empty list. Operations share the session file-operation gate with imports and
sync, and lock cleanup drains in-flight I/O before detaching session stores.

## Backup policy

**New local ZIP and desktop backups exclude Recently Deleted**, including its
password editor records. A stale selection does not re-include a trashed file.
Backups already created are not rewritten or erased by deletion/expiry.
Restore an item into the active vault before including it in a new backup.
This is a local recovery queue, not a backup: it shares the app's storage/key
lifetime. Backup attempts concurrent with mutation may fail and need retrying;
they are not advertised as atomic whole-vault snapshots.

## WebDAV policy

1. Deleting locally records explicit deletion intent immediately after the
   recovery receipt. The next manual sync publishes a manifest tombstone when
   safe under the baseline/conflict rules; deletion does not trigger networking.
   A durable receipt also supplies evidence if the separate deletion-record
   write was interrupted. Missing index entries alone never imply deletion.
2. Trashed payloads are not uploaded as active files. A same-id remote live
   version cannot be pulled over a retained local item, even with an old saved
   conflict choice. If a delete conflicts with a remote edit, choose local to
   publish deletion, or restore/permanently remove the local recovery item
   **before** choosing remote/keep-both and retrying sync. No version is silently
   picked by clock order.
3. Restore removes the local deletion record, marks explicit restore intent,
   and makes the live item eligible for the next sync. A concurrent remote
   change can still require review; restore does not force a network overwrite.
4. Expiry/permanent deletion removes **local** retained payloads/thumbnails.
   Remote blobs, previous remote versions, and existing backups are not erased.
   WebDAV canonical-blob garbage collection remains out of scope.
5. Server-originated tombstones retain their existing Phase 3 behavior: local
   payloads removed from the active sync index are not automatically enrolled
   in this user-delete recovery queue. This is not cross-device trash sync.

See [WebDAV sync](local_server_sync.md) for publication guards and the master-key
continuity requirement, and [device checks](phase5_testing.md) for release testing.
