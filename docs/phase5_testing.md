# Phase 5 device checks

Physical-device testing is user-run. Automated tests cover expiry with an
injected clock, encrypted-byte restoration, failure/restart replay, backup
exclusion, sync decisions, gallery filtering/import-sheet callbacks, and bottom
navigation at 240/320/600 logical pixels with 1×/2×/3.2× text scaling. They do not
replace Android picker, camera, Autofill, TalkBack, or real-server checks.

## Preparation

- Use a disposable/test vault and keep an external backup. Do not wipe real
  data or change the device clock to test retention.
- Install the debug APK (`build/app/outputs/flutter-apk/app-debug.apk`) by your
  usual method. Confirm existing settings/data are preserved when upgrading.
- Prepare a photo, video, song, PDF, another document, an encrypted file with a
  thumbnail, a hidden-only file, a note, and a password entry. Tag/favorite some
  items and place them in an album/folder. Use dummy login data only.
- For resume checks, temporarily disable Close app in background if necessary;
  test its normal enabled behavior separately. Restore your preferred settings
  afterward.

## Local recovery

1. Open Recently Deleted from both the drawer and Settings → Storage. Expect
   30-day retention unless already configured. Verify the storage/backup/sync
   explanation is visible and scrollable.
2. Delete mixed encrypted/hidden-only items from the gallery, explorer, album,
   favorites, smart collection, note list, and password list. They must leave
   active results; dummy deleted logins must no longer be offered by Autofill.
3. Confirm retained-byte storage increases. Restart/lock/unlock, reopen Recently
   Deleted, and restore. Open/play/decrypt the restored items and check names,
   tags, favorites, dates, surviving album/folder membership, and note/password
   editor content. Restore should not create duplicate ids.
4. Delete an item, remove its now-unused folder/album, then restore. It should
   return without recreating the removed definition or crashing an editor.
5. Choose 7 days, delete an item, then choose 90 days. Its displayed deadline
   must stay unchanged. Automated clock tests cover actual expiry; do not wait
   for or simulate expiry by changing a production device's clock.
6. Choose Delete immediately. Cancel its extra confirmation and verify no
   setting changes. Accept on a second attempt, then delete a disposable item:
   no recoverable item should remain. Existing trash keeps its old deadline.
7. Test Cancel and Confirm for Delete permanently and Empty Recently Deleted,
   with Secure Delete both off and on. Removed items must not return after
   unlock/restart. This checks application behavior, not forensic flash erasure.
8. In a decoy session, repeat delete/restore with a dummy file. Main-vault
   recovery items must not appear there (or vice versa). Decoy changes must not
   enter WebDAV sync.
9. During a large operation, minimize its progress UI and try a competing
   recovery action. It must refuse safely, not run concurrently. Lock during a
   batch on disposable data; unlock and use Retry cleanup. Each item must be
   active or represented by a pending/restorable receipt, never silently lost.

## Backups and WebDAV

1. Delete one dummy file/login and leave another active. Create a new ZIP and a
   desktop backup. Verify only active items are included; a previously created
   backup is unaffected. Restore a deleted item and repeat to include it again.
2. On a compatible test WebDAV target, sync a file, delete it locally, then sync
   again. Its manifest entry should become deleted while remote blob bytes
   remain. Permanent local deletion must not erase that remote blob.
3. Restore before expiry and sync again. The item should become live on the
   target (or request conflict review if the target changed).
4. Change a file's remote metadata on a second key-compatible client, then
   delete locally and sync. Expect review, not an automatic winner. Remote or
   keep-both resolution must instruct you to restore/purge the retained local
   item first. Restore it, retry, and resolve the live conflict normally.
5. Use [the Phase 3 server guide](local_server_testing.md) for capability,
   interrupted-transfer, large-file, and key-continuity checks. Do not assume a
   WebDAV server alone can unlock a fresh install.

## Navigation and gallery regression

1. Use the narrowest practical app window and Android's largest font/display
   settings, light and dark themes, and gesture/button navigation. All five
   categories—including Docs—and Import must remain reachable. Overflowing
   tabs scroll horizontally; Import stays pinned. Labels should not shrink or
   truncate, and the last file row must clear the floating bar/system inset.
2. Customize category order/visibility and Import on the left/right. Restart,
   swipe between pages, enter/exit selection, and verify persisted choices and
   selected-tab indication. All categories must remain accessible in selection
   mode even though Import is hidden.
3. With TalkBack, traverse every tab and Import. Expect each label once, button
   semantics, and the selected state. With a hardware keyboard, Tab/Shift+Tab
   should reveal focused overflow tabs; Enter/Space activates them.
4. Check drawer scrolling/counts/routes, search, structured filters, sorting,
   select-all, and sliding selection. Hidden-by-filter files must not be
   selected. Verify encrypted and hidden-only thumbnail settings.
5. Exercise every import action: Images, Videos, All Media, Take Photo, Record
   Video, Record Audio, Songs, Documents (including Office conversion), Any
   Files, and Import Folder. Cancel at each picker/confirmation once. Verify
   per-file encryption choices, progress/minimize, duplicate handling, retained
   originals reporting, and folder import preserving sources. Close only
   dismisses the import sheet, not the gallery.
6. Recheck viewing/export, unhide, notes/password editor routing, share intake,
   album/tag/favorite actions, settings, decoy setup, and Lock now. Unhide may
   leave a recoverable vault copy according to retention.

Record device/Android version, font/display settings, action, expected/actual
result, and redacted diagnostics for failures. Never include real passwords,
keys, personal filenames, or server credentials in a report.
