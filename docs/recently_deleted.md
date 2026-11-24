# Recently Deleted

## The basics

Recently Deleted is **local-only**, and the main and decoy vaults keep separate
namespaces. The default retention is **30 days**. You can pick **7, 30, or 90
days**, or **Delete immediately**, from Recently Deleted → Retention. The
setting applies to future deletions. Switching to immediate deletion asks for
confirmation first.

Each deletion keeps its own expiry deadline. Changing the setting later won't
shorten or extend deadlines that already exist. Restore only works before that
deadline. Cleanup runs on unlock/resume and on an expiry timer while the
protected session is open. Android may suspend or kill the app, so expired bytes
can stick around until the next unlocked cleanup — but the UI won't offer them
for restore anymore. There's no promised background-erasure deadline.

## Deleting, restoring, and storage

- A normal Delete moves the stored payload and thumbnail into a private
  `.recently-deleted` directory without decrypting or re-encrypting anything.
  Notes and passwords keep their editor metadata too, including IV/salt.
- Deleted items disappear from active lists, search, smart collections, and
  password Autofill. Active-vault counts and storage totals exclude them.
  Recently Deleted reports retained payload/thumbnail bytes separately, and
  moving an item there doesn't reclaim storage by itself.
- Restore keeps the id, file bytes, encryption metadata, tags, favorite state,
  and original dates. It uses new unique paths instead of overwriting an old
  path that's now occupied. Album/folder memberships come back only if the local
  definition still exists; a deleted note folder is not recreated. The sync
  modification marker is advanced so the restore is recorded.
- **Delete permanently** and **Empty Recently Deleted** ask for confirmation.
  Expiry and immediate deletion use the same permanent-removal path. Payloads
  and thumbnails are both removed. Once permanent removal starts, the item is no
  longer offered for restore, even if only part of the removal succeeds.
- With Secure Delete on, removal tries to overwrite-then-unlink; with it off, it
  just unlinks. The overwrite is **best effort, not guaranteed flash erasure** —
  wear leveling, snapshots, external copies, and storage firmware are outside
  Latch's control. Moving an item into Recently Deleted doesn't overwrite
  anything. Import/source-original removal keeps its existing timing.
- Unhide exports a copy and removes the active vault entry using this same
  retention policy, so a recoverable vault copy may remain locally.
- Wiping a vault, uninstalling, or clearing app data is not a recoverable
  Delete. Keep backups outside app-private storage.

## Interrupted operations

A strict secure-storage receipt is saved **before** moving bytes or changing
indexes. It outranks the legacy/PocketBase index fallback, so a stale row can't
make a deleted item active again. Notes and password lists apply the same
receipt filter even if an editor index update failed.

Pending delete/restore/permanent-delete transitions replay at the next unlocked
maintenance pass. Use **Retry cleanup** if you want to retry right away. If the
initial receipt write fails, the active item and its bytes stay untouched. A
later failure can leave a hidden pending item instead of an active file — the
receipt and surviving bytes are still there to finish the job. A pending restore
completes before another action can overwrite its receipt. Failures get reported
instead of pretending permanent removal worked. Corrupt/unreadable receipt
storage fails closed rather than being replaced with an empty list. These
operations share the session file-operation gate with imports and sync, and lock
cleanup drains in-flight I/O before detaching session stores.

## Backups

**New local ZIP and desktop backups leave out Recently Deleted**, including its
password editor records. A stale selection won't re-add a trashed file. Backups
you already created aren't rewritten or erased by deletion/expiry. Restore an
item into the active vault before including it in a new backup.

This is a local recovery queue, not a backup: it shares the app's storage and key
lifetime. Backup attempts that overlap a mutation may fail and need a retry —
they aren't advertised as atomic whole-vault snapshots.

## WebDAV

1. Deleting locally records deletion intent right after the recovery receipt.
   The next manual sync publishes a manifest tombstone when it's safe under the
   baseline/conflict rules. Deletion doesn't trigger networking by itself. A
   durable receipt also supplies evidence if the separate deletion-record write
   was interrupted. Missing index entries alone never mean "deleted".
2. Trashed payloads aren't uploaded as active files. A same-id remote live
   version can't be pulled over a retained local item, even with an old saved
   conflict choice. If a delete conflicts with a remote edit, choose local to
   publish the deletion, or restore/permanently remove the local recovery item
   **before** choosing remote/keep-both and retrying sync. No version gets picked
   silently by clock order.
3. Restore removes the local deletion record, marks explicit restore intent, and
   makes the item eligible for the next sync. A concurrent remote change can
   still need review; restore doesn't force a network overwrite.
4. Expiry/permanent deletion removes **local** retained payloads and thumbnails.
   Remote blobs, previous remote versions, and existing backups aren't erased.
   WebDAV canonical-blob garbage collection is still out of scope.
5. Server-originated tombstones keep their existing behavior: local payloads
   removed from the active sync index aren't automatically added to this
   user-delete recovery queue. This isn't cross-device trash sync.

See [WebDAV sync](local_server_sync.md) for the publication guards and
master-key continuity, and [device checks](phase5_testing.md) for release
testing.
