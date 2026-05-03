# Flick Integration Guide

## Goal

Flick should behave like a first-class playback companion for Locker:

- Locker hands Flick a hidden song with a normal Android audio `VIEW` intent.
- Flick plays that URI directly without copying it into public storage.
- Flick exposes an explicit `Back to Locker` action.
- Returning from Flick should foreground the existing Locker task when it is already running.

This keeps the two apps feeling like one ecosystem instead of two unrelated apps.

## Locker Contract

Locker now exposes these Android integration points:

- Locker package: `com.mossapps.locker`
- Flick package: `com.mossapps.flick`
- Return URI: `locker://return`
- Main activity launch mode: `singleTask`
- Return intent filter: `ACTION_VIEW` on `locker://return`

What that means for Flick:

- If Locker is already open in the background, opening `locker://return` will bring that existing task forward.
- If Locker is not running, Android will cold-start it.
- Locker does not need a custom action for v1. Standard Android `VIEW` for audio is enough.

## What Flick Should Implement

### 1. Accept standard Android audio `VIEW` intents

Flick should expose an exported playback activity that can handle audio sent from Locker.

Recommended manifest shape:

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

Notes:

- Supporting `content://` is the important part.
- Keep MIME support broad: `audio/*`.
- You can add narrower types later if you want analytics or specialized handling.
- Do not require custom permissions from Locker.

## 2. Read the incoming URI directly

Locker will hand Flick a temporary readable audio URI. Flick should stream from it instead of copying it into gallery-visible storage.

If Flick uses Media3 / ExoPlayer, the flow should look like this:

```kotlin
val audioUri = intent?.data ?: return

val mediaItem = MediaItem.fromUri(audioUri)
player.setMediaItem(mediaItem)
player.prepare()
player.playWhenReady = true
```

If Flick does any preflight validation, do it through `ContentResolver`:

```kotlin
contentResolver.openAssetFileDescriptor(audioUri, "r")?.use {
    // URI is readable
}
```

Important behavior:

- Do not move the file into shared storage.
- Do not rescan it into the media library.
- Do not assume the URI is permanent.
- Release the URI and player resources when playback is done.

## 3. Preserve Locker's privacy model

Flick should treat Locker-supplied media as temporary private content.

Recommended rules on the Flick side:

- No background indexing of Locker media.
- No automatic caching to public folders.
- No automatic cloud sync for the handed-off file.
- No thumbnail export into gallery-visible locations.
- If caching is needed for playback stability, keep it inside Flick's private app storage and clean it up aggressively.

## 4. Add a dedicated `Back to Locker` action

Do not rely only on Android back-stack behavior. It may feel okay in some cases, but explicit return is more reliable and intentional.

Flick should expose a visible action in the player UI such as:

- `Back to Locker`
- `Return to Locker`
- `Done in Flick`

Recommended implementation:

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

Why this is the right shape:

- `package = "com.mossapps.locker"` makes the return deterministic.
- `locker://return` matches Locker's manifest contract.
- `CLEAR_TOP` and `SINGLE_TOP` help Android reuse the running Locker activity instead of creating unnecessary duplicates.

If you want to be defensive, wrap the launch in a `try/catch` and fall back to a normal `finish()` if Locker is unavailable.

## 5. Package-targeted handoff

Locker now knows Flick's package name and can target it directly:

- Flick package: `com.mossapps.flick`
- Locker can detect whether Flick is installed
- Locker can show a dedicated `Play with Flick` action
- Locker can skip the generic app chooser when the user explicitly wants Flick

That makes the handoff deterministic and keeps the two-app flow feeling tighter.

Because of that, Flick's package identifier should now be treated as part of the integration contract.

## Recommended UX Flow

1. User taps a song in Locker.
2. Locker can either play it internally or hand it to Flick.
3. Flick opens directly on a playback screen.
4. Flick makes it obvious the track came from Locker.
5. User taps `Back to Locker`.
6. Flick launches `locker://return`.
7. Locker comes back to the foreground in its existing state.

Good small UX touches in Flick:

- Show a small `Opened from Locker` label.
- Keep the return action visible without burying it in a menu.
- If playback fails, offer `Back to Locker` in the error state too.

## Test Checklist

Run these checks before calling the integration done:

1. Launch an MP3 from Locker into Flick.
2. Verify Flick can read the URI without copying it to public storage.
3. Verify playback works for at least `mp3`, `m4a`, and `ogg`.
4. Tap `Back to Locker` and confirm the existing Locker task returns.
5. Confirm Locker is not duplicated in recents.
6. Confirm the handed-off song does not appear in gallery/music scanners because of Flick.
7. Confirm closing Flick does not leave stale temp playback state behind.

## Locker-side implementation status

Locker is configured to support this integration now:

- `locker://return` is registered in Locker's manifest
- Locker uses `singleTask` so the existing task can be foregrounded again
- Locker can query `com.mossapps.flick`
- Locker can offer a dedicated `Play with Flick` action for songs when Flick is installed

The remaining work is fully on Flick's side: accept the URI, play it, and provide the explicit return affordance.
