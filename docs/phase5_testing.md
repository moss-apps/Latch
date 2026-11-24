# Device checks

These are the checks that need a real phone. The automated suite covers expiry
with an injected clock, restoring encrypted bytes, failure/restart replay,
backup exclusion, sync decisions, gallery filtering/import-sheet callbacks, and
bottom navigation at 240/320/600 logical pixels with 1×/2×/3.2× text scaling.
That does not replace Android pickers, the camera, Autofill, TalkBack, or a real
server.

## Before you start

- Do the approval/isolation preflight in
  [Stable release checks](stable_release_checklist.md) first. No automatic
  installs, overwrites, uninstall/reinstall, or clear-data on a live vault.
- Use a disposable/test vault and a fixture backup you've verified separately.
  Don't wipe real data, and don't change the device clock to test retention.
- Stable sign-off uses the exact approved release artifact and records its hash.
  Debug checks are useful, but they don't count as sign-off. Test upgrades from
  the previous version only on the disposable target, and confirm settings,
  data, and keys survive.
- Have a photo, video, song, PDF, another document, an encrypted file with a
  thumbnail, a hidden-only file, a note, and a password entry ready. Tag and
  favorite a few, and put some in an album/folder. Use dummy logins only.
- For resume checks, you may need to turn off Close app in background
  temporarily. Test its normal enabled behavior separately, then put your
  settings back.

## Recently Deleted

1. Open Recently Deleted from both the drawer and Settings → Storage. It should
   say 30 days unless you've changed it. Check that the storage/backup/sync
   explanation is visible and scrolls.
2. Delete a mix of encrypted and hidden-only items from the gallery, explorer,
   album, favorites, smart collection, note list, and password list. They should
   leave active results, and deleted dummy logins should stop showing up in
   Autofill.
3. Check that retained-byte storage goes up. Restart, lock, unlock, reopen
   Recently Deleted, and restore. Open, play, or decrypt the restored items and
   check names, tags, favorites, dates, album/folder membership, and note or
   password content. Restoring shouldn't create duplicate ids.
4. Delete an item, remove its now-unused folder/album, then restore it. It should
   come back without recreating the removed definition or crashing an editor.
5. Choose 7 days, delete something, then switch to 90 days. The item's displayed
   deadline should stay put. The automated clock tests cover actual expiry — don't
   wait for it or fake it by changing a production device's clock.
6. Choose Delete immediately. Cancel the extra confirmation and check that
   nothing changed. Try again and accept, then delete a disposable item: nothing
   should be recoverable. Existing trash keeps its old deadline.
7. Try Cancel and Confirm for Delete permanently and Empty Recently Deleted,
   with Secure Delete both off and on. Removed items shouldn't come back after
   unlock/restart. This checks app behavior, not forensic flash erasure.
8. In a decoy session, repeat delete/restore with a dummy file. Main-vault
   recovery items shouldn't show up there (or vice versa). Decoy changes
   shouldn't enter WebDAV sync.
9. During a large operation, minimize the progress UI and try a competing
   recovery action. It should refuse safely instead of running both. Lock during
   a batch on disposable data, then unlock and use Retry cleanup. Every item
   should be active or have a pending/restorable receipt — never silently lost.

## Website Autofill diagnostics

On the approved test device or profile, make Latch Android's Autofill provider
and turn on Biometric Unlock in Latch. In the browser, enable external Autofill
if it asks. Tap the password field on a public test form such as
[The Internet](https://the-internet.herokuapp.com/login); don't submit it.

- If **Choose a password in Latch** opens a warning, write down the `AF` code,
  the Android version, and the browser version. `AF01` means Android doesn't
  expose the field's scheme. `AF02` or `AF03` means the field doesn't report a
  domain or scheme. `AF04` means the reported scheme isn't HTTPS. `AF05` means
  the reported domain couldn't be parsed. These happen before Latch opens the
  vault, and the saved URL can't fix them.
- If no suggestion appears or it closes right away, run
  `adb logcat -v brief -s LatchAutofill:D` with the debug build on the test
  target. Reproduce once, then stop with Ctrl+C. Share only lines from that
  attempt, or say that none appeared. The tag records fixed outcomes and counts,
  not URLs, form values, or credentials. Don't share an unfiltered log.

## Backups and WebDAV

1. Delete one dummy file/login and leave another active. Create a new ZIP and a
   desktop backup. Only active items should be included, and an older backup
   shouldn't change. Restore a deleted item and repeat to include it again.
2. On a compatible test WebDAV target, sync a file, delete it locally, then sync
   again. Its manifest entry should become deleted while the remote blob bytes
   stay. Permanent local deletion must not erase that remote blob.
3. Restore before expiry and sync again. The item should become live on the
   target, or ask for conflict review if the target changed.
4. Change a file's remote metadata from a second key-compatible client, then
   delete it locally and sync. Expect review, not an automatic winner. Remote or
   keep-both resolution should tell you to restore/purge the retained local item
   first. Restore it, retry, and resolve the conflict normally.
5. Use [the WebDAV hardware check](local_server_testing.md) for capability,
   interrupted-transfer, large-file, and key-continuity checks. A WebDAV server
   alone can't unlock a fresh install — don't assume it can.

## Navigation and gallery regression

1. Use the narrowest practical app window, Android's largest font/display
   settings, light and dark themes, and gesture/button navigation. All five
   categories — including Docs — and Import should stay reachable. Overflowing
   tabs scroll sideways; Import stays pinned. Labels shouldn't shrink or
   truncate, and the last file row should clear the floating bar/system inset.
2. Customize category order/visibility and put Import on the left or right.
   Restart, swipe between pages, enter/exit selection, and check that your
   choices persist and the selected tab is obvious. All categories should stay
   accessible in selection mode even though Import is hidden.
3. With TalkBack, go through every tab and Import. Each label should be read
   once, buttons should have semantics, and the selected state should be
   announced. With a hardware keyboard, Tab/Shift+Tab should reveal focused
   overflow tabs, and Enter/Space should activate them.
4. Check drawer scrolling/counts/routes, search, structured filters, sorting,
   select-all, and sliding selection. Files hidden by a filter shouldn't be
   selectable. Check the encrypted and hidden-only thumbnail settings.
5. Try every import action: Images, Videos, All Media, Take Photo, Record Video,
   Record Audio, Songs, Documents (including Office conversion), Any Files, and
   Import Folder. Cancel at each picker/confirmation once. Check per-file
   encryption choices, progress/minimize, duplicate handling, retained-original
   reporting, and that folder import leaves the sources alone. Close should only
   dismiss the import sheet, not the gallery.
6. Recheck viewing/export, unhide, notes/password editor routing, share intake,
   album/tag/favorite actions, settings, decoy setup, and Lock now. Unhide may
   leave a recoverable vault copy depending on retention.

Write down the device/Android version, font/display settings, what you did, what
you expected, what happened, and redacted diagnostics for failures. Never
include real passwords, keys, personal filenames, or server credentials.
