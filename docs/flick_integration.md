# Flick Integration

Flick plays audio handed off from Latch. Latch sends a hidden song via a
standard Android audio `VIEW` intent; Flick streams it without copying to
public storage and exposes a `Back to Latch` action that returns to the
running Latch task.

## Contract

| Item | Value |
|---|---|
| Latch package | `com.mossapps.locker` |
| Flick package | `com.mossapps.flick` |
| Return URI | `locker://return` |
| Latch launch mode | `singleTask` |
| Return intent filter | `ACTION_VIEW` on `locker://return` |

- Opening `locker://return` foregrounds a running Latch task, or cold-starts Latch.
- Latch targets Flick's package directly, skipping the generic app chooser.
- No custom action or permission is required from Flick for v1; standard `VIEW` for audio is enough.

## Flick requirements

| # | Requirement | Detail |
|---|---|---|
| 1 | Accept audio `VIEW` intents | Exported playback activity, `content://` scheme, MIME `audio/*`. Do not require custom permissions. |
| 2 | Stream the URI directly | Do not copy to shared storage, rescan into the media library, or assume the URI is permanent. Release URI + player on completion. |
| 3 | Preserve Latch's privacy model | No background indexing, public caching, cloud sync, or gallery-visible thumbnails of Latch media. Cache for playback only inside Flick's private storage; clean up aggressively. |
| 4 | Provide a `Back to Latch` action | Visible in the player UI (and error states). Do not rely on back-stack behavior alone. |

### Manifest

```xml
<activity
    android:name=".player.ExternalPlaybackActivity"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:scheme="content" />
        <data android:mimeType="audio/*" />
    </intent-filter>
</activity>
```

### Playback (Media3 / ExoPlayer)

```kotlin
val audioUri = intent?.data ?: return

val mediaItem = MediaItem.fromUri(audioUri)
player.setMediaItem(mediaItem)
player.prepare()
player.playWhenReady = true
```

URI readability preflight via `ContentResolver`:

```kotlin
contentResolver.openAssetFileDescriptor(audioUri, "r")?.use {
    // URI is readable
}
```

### Return to Latch

```kotlin
private fun returnToLocker(context: Context) {
    val intent = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("locker://return?source=flick")
    ).apply {
        `package` = "com.mossapps.locker"
        addCategory(Intent.CATEGORY_BROWSABLE)
        addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
    context.startActivity(intent)
}
```

`package` makes the return deterministic; `CLEAR_TOP` + `SINGLE_TOP` reuse the running Latch activity. Wrap in `try/catch` and fall back to `finish()` if Latch is unavailable.

## Test checklist

1. Launch an MP3 from Latch into Flick.
2. Flick reads the URI without copying it to public storage.
3. Playback works for `mp3`, `m4a`, and `ogg`.
4. `Back to Latch` returns the existing Latch task; Latch is not duplicated in recents.
5. The handed-off song does not appear in gallery/music scanners.
6. Closing Flick leaves no stale temp playback state.

UX touches: show an `Opened from Latch` label; keep the return action visible (not buried in a menu); offer it in the error state too.
