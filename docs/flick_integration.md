# Flick integration

Flick plays audio that Latch hands off to it. Latch sends a hidden song with a
standard Android audio `VIEW` intent, Flick streams it without copying it to
public storage, and Flick shows a `Back to Latch` action that returns you to the
running Latch task.

## The contract

| Item | Value |
|---|---|
| Latch package | `com.mossapps.locker` |
| Flick package | `com.mossapps.flick` |
| Return URI | `locker://return` |
| Latch launch mode | `singleTask` |
| Return intent filter | `ACTION_VIEW` on `locker://return` |

- Opening `locker://return` brings a running Latch task forward, or cold-starts
  Latch if it isn't running.
- Latch targets Flick's package directly and skips the generic app chooser.
- Flick doesn't need a custom action or permission for v1. A normal `VIEW` intent
  for audio is enough.

## What Flick needs to do

| # | Requirement | Details |
|---|---|---|
| 1 | Accept audio `VIEW` intents | Export a playback activity that handles `content://` URIs with MIME `audio/*`. Don't require custom permissions. |
| 2 | Stream the URI directly | Don't copy it to shared storage, scan it into the media library, or assume the URI sticks around. Release the URI and player when playback ends. |
| 3 | Respect Latch's privacy model | No background indexing, public caching, cloud sync, or gallery-visible thumbnails of Latch media. Cache only for playback in Flick's private storage, and clean it up aggressively. |
| 4 | Show a `Back to Latch` action | Put it in the player UI and in error states. Don't rely on the back stack alone. |

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

Check readability first with `ContentResolver`:

```kotlin
contentResolver.openAssetFileDescriptor(audioUri, "r")?.use {
    // URI is readable
}
```

### Returning to Latch

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

Setting `package` makes the return deterministic, and `CLEAR_TOP` + `SINGLE_TOP`
reuse the running Latch activity. Wrap it in `try/catch` and fall back to
`finish()` if Latch isn't available.

## Test checklist

1. Launch an MP3 from Latch into Flick.
2. Flick reads the URI without copying it to public storage.
3. Playback works for `mp3`, `m4a`, and `ogg`.
4. `Back to Latch` returns to the existing Latch task, and Latch doesn't show up
   twice in recents.
5. The song doesn't appear in gallery or music scanners.
6. Closing Flick leaves no stale temp playback state.

For UX, show an `Opened from Latch` label, keep the return action visible
instead of burying it in a menu, and offer it in the error state too.
