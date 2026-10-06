package com.mossapps.locker

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.Display
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.mossapps.locker/autokill"
    private val AUTO_KILL_PREFS = "locker_auto_kill"
    private val AUTO_KILL_DELAY_KEY = "delay_seconds"
    private val MEDIA_SCANNER_CHANNEL = "com.example.vault/media_scanner"
    private val SCREENSHOT_PROTECTION_CHANNEL = "com.mossapps.locker/screenshot_protection"
    private val FLICK_CHANNEL = "com.mossapps.locker/flick"
    private val FLICK_PACKAGE = "com.mossapps.flick"
    private val RECORDER_CHANNEL = "com.mossapps.locker/audio_recorder"
    private val AMPLITUDE_CHANNEL = "com.mossapps.locker/audio_amplitude"
    private val INSTALL_SOURCE_CHANNEL = "com.mossapps.locker/install_source"
    private val PB_CHANNEL = "com.mossapps.locker/pb"
    private val SHARE_CHANNEL = "com.mossapps.locker/share_intake"

    private data class ShareItem(
        val id: String,
        val uri: String,
        val name: String?,
        val mimeType: String?,
        val size: Long?,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id,
            "uri" to uri,
            "name" to name,
            "mimeType" to mimeType,
            "size" to size,
        )
    }

    private val pendingShareItems = mutableListOf<ShareItem>()
    private var shareChannel: MethodChannel? = null
    private val autoKillPreferences by lazy {
        getSharedPreferences(AUTO_KILL_PREFS, MODE_PRIVATE)
    }
    private val autoKillHandler = Handler(Looper.getMainLooper())
    private val autoKillRunnable = Runnable {
        if (isAutoKillEnabled && !isFinishing && !isDestroyed) {
            finishAndRemoveTask()
        }
    }
    private var isAutoKillEnabled = true
    private var isStopped = false
    private var autoKillDelayMillis = 0L
    private var mediaRecorder: MediaRecorder? = null
    private var currentRecordingPath: String? = null
    private var isRecording = false
    private var amplitudeSink: EventChannel.EventSink? = null
    private val amplitudeHandler = Handler(Looper.getMainLooper())
    private val amplitudeRunnable = object : Runnable {
        override fun run() {
            if (isRecording && mediaRecorder != null) {
                try {
                    val amp = mediaRecorder!!.maxAmplitude.toDouble() / 32768.0
                    amplitudeSink?.success(amp)
                } catch (_: Exception) {}
                amplitudeHandler.postDelayed(this, 100)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        autoKillDelayMillis = loadAutoKillDelayMillis()
        if (savedInstanceState == null) {
            handleShareIntent(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Enable high frame rate
        enableHighFrameRate()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAutoKillEnabled" -> {
                    val enabled = call.arguments as? Boolean
                    if (enabled == null) {
                        result.error("INVALID_ARGUMENT", "Boolean flag is required", null)
                    } else {
                        setAutoKillEnabled(enabled)
                        result.success(null)
                    }
                }
                "setAutoKillDelaySeconds" -> {
                    val seconds =
                        (call.argument<Number>("seconds") ?: call.arguments as? Number)?.toInt()
                    if (seconds == null || seconds < 0) {
                        result.error("INVALID_ARGUMENT", "Non-negative delay is required", null)
                    } else {
                        setAutoKillDelaySeconds(seconds)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_PROTECTION_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setScreenshotProtectionEnabled") {
                val enabled = call.arguments as? Boolean
                if (enabled == null) {
                    result.error("INVALID_ARGUMENT", "Boolean flag is required", null)
                } else {
                    setScreenshotProtectionEnabled(enabled)
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
        
        // Media scanner channel for scanning files without creating duplicates
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SCANNER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        scanMediaFile(path, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FLICK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isFlickInstalled" -> result.success(isPackageInstalled(FLICK_PACKAGE))
                "openAudioInFlick" -> {
                    val path = call.argument<String>("filePath")
                    val mimeType = call.argument<String>("mimeType")

                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    } else {
                        openAudioInFlick(path, mimeType, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AMPLITUDE_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    amplitudeSink = events
                }
                override fun onCancel(arguments: Any?) {
                    amplitudeSink = null
                    amplitudeHandler.removeCallbacks(amplitudeRunnable)
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startRecording" -> {
                    val path = call.argument<String>("path")
                    val format = call.argument<String>("format") ?: "aac"
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    } else {
                        startRecording(path, format, result)
                    }
                }
                "stopRecording" -> stopRecording(result)
                "pauseRecording" -> pauseRecording(result)
                "resumeRecording" -> resumeRecording(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_SOURCE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInstallerPackageName") {
                result.success(getInstallerPackageName())
            } else {
                result.notImplemented()
            }
        }

        // Exposes applicationInfo.nativeLibraryDir so Dart can locate and spawn
        // the bundled PocketBase .so. P0 spike wiring — see pb_spike_screen.dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PB_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getNativeLibraryDir") {
                result.success(applicationInfo.nativeLibraryDir)
            } else {
                result.notImplemented()
            }
        }

        val shareChannelInstance =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
        shareChannel = shareChannelInstance
        shareChannelInstance.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingShare" -> result.success(sharePayload())
                "consumeShare" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    pendingShareItems.removeAll { ids.contains(it.id) }
                    result.success(true)
                }
                "clearShare" -> {
                    pendingShareItems.clear()
                    result.success(true)
                }
                "stageShare" -> stageShare(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun sharePayload(): Map<String, Any?> =
        mapOf("items" to pendingShareItems.map { it.toMap() })

    private fun notifySharePending() {
        val channel = shareChannel ?: return
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod("onShareReceived", sharePayload())
        }
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val uris = extractStreamUris(intent)
        if (uris.isEmpty()) return

        for (uri in uris) {
            val existing = pendingShareItems.any { it.uri == uri.toString() }
            if (existing) continue
            val metadata = queryShareMetadata(uri)
            pendingShareItems.add(
                ShareItem(
                    id = UUID.randomUUID().toString(),
                    uri = uri.toString(),
                    name = metadata.first,
                    mimeType = intent.type?.takeIf { it.isNotBlank() && it != "*/*" }
                        ?: contentResolver.getType(uri),
                    size = metadata.second,
                )
            )
        }
        notifySharePending()
    }

    private fun extractStreamUris(intent: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            if (uri != null) uris.add(uri)
        } else if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            }
            if (list != null) uris.addAll(list)
        }
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        return uris.distinctBy { it.toString() }
    }

    private fun queryShareMetadata(uri: Uri): Pair<String?, Long?> {
        var name: String? = null
        var size: Long? = null
        try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                        name = cursor.getString(nameIndex)
                    }
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        size = cursor.getLong(sizeIndex)
                    }
                }
            }
        } catch (_: Exception) {}
        if (name.isNullOrBlank()) {
            name = uri.lastPathSegment?.substringAfterLast('/')
        }
        return name to size
    }

    private fun stageShare(call: MethodCall, result: MethodChannel.Result) {
        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
        val destinationDir = call.argument<String>("destinationDir")
        if (destinationDir.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Destination directory is required", null)
            return
        }

        Thread {
            val staged = mutableListOf<Map<String, Any?>>()
            val directory = File(destinationDir)
            try {
                directory.mkdirs()
            } catch (_: Exception) {}
            for (item in items) {
                val id = item["id"] as? String
                val uriString = item["uri"] as? String
                try {
                    if (id.isNullOrBlank() || uriString.isNullOrBlank()) {
                        throw IllegalArgumentException("Missing id or uri")
                    }
                    val uri = Uri.parse(uriString)
                    val fallbackName = item["name"] as? String
                    val displayName = queryShareMetadata(uri).first ?: fallbackName ?: "shared_file"
                    val safeName = displayName
                        .replace(Regex("[^A-Za-z0-9._-]"), "_")
                        .take(120)
                        .ifBlank { "shared_file" }
                    val outFile = File(directory, "${id}_$safeName")
                    contentResolver.openInputStream(uri).use { input ->
                        if (input == null) {
                            throw IllegalStateException("Could not open shared file")
                        }
                        FileOutputStream(outFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    staged.add(
                        mapOf(
                            "id" to id,
                            "path" to outFile.absolutePath,
                            "name" to displayName,
                            "mimeType" to (contentResolver.getType(uri)
                                ?: item["mimeType"]),
                            "size" to outFile.length(),
                        )
                    )
                } catch (e: Exception) {
                    staged.add(
                        mapOf(
                            "id" to id,
                            "error" to (e.message ?: "Failed to stage shared file"),
                        )
                    )
                }
            }
            Handler(Looper.getMainLooper()).post {
                result.success(mapOf("staged" to staged))
            }
        }.start()
    }

    private fun startRecording(path: String, format: String, result: MethodChannel.Result) {
        try {
            stopAndReleaseRecorder()

            val file = File(path)
            file.parentFile?.mkdirs()

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(applicationContext)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            if (format == "wav") {
                recorder.setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
                recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB)
            } else {
                recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            }
            recorder.setAudioSamplingRate(44100)
            recorder.setAudioChannels(1)
            recorder.setAudioEncodingBitRate(128000)
            recorder.setOutputFile(path)
            recorder.prepare()
            recorder.start()

            mediaRecorder = recorder
            currentRecordingPath = path
            isRecording = true

            amplitudeHandler.removeCallbacks(amplitudeRunnable)
            amplitudeHandler.postDelayed(amplitudeRunnable, 100)

            result.success(path)
        } catch (e: Exception) {
            stopAndReleaseRecorder()
            result.error("RECORD_ERROR", "Failed to start recording: ${e.message}", null)
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        try {
            val path = currentRecordingPath
            amplitudeHandler.removeCallbacks(amplitudeRunnable)
            isRecording = false

            if (mediaRecorder != null) {
                mediaRecorder!!.stop()
                mediaRecorder!!.release()
                mediaRecorder = null
            }
            currentRecordingPath = null
            result.success(path)
        } catch (e: Exception) {
            stopAndReleaseRecorder()
            result.error("RECORD_ERROR", "Failed to stop recording: ${e.message}", null)
        }
    }

    private fun pauseRecording(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && mediaRecorder != null) {
                mediaRecorder!!.pause()
                amplitudeHandler.removeCallbacks(amplitudeRunnable)
                result.success(null)
            } else {
                result.error("NOT_SUPPORTED", "Pause not supported on this Android version", null)
            }
        } catch (e: Exception) {
            result.error("RECORD_ERROR", "Failed to pause: ${e.message}", null)
        }
    }

    private fun resumeRecording(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && mediaRecorder != null) {
                mediaRecorder!!.resume()
                amplitudeHandler.removeCallbacks(amplitudeRunnable)
                amplitudeHandler.postDelayed(amplitudeRunnable, 100)
                result.success(null)
            } else {
                result.error("NOT_SUPPORTED", "Resume not supported on this Android version", null)
            }
        } catch (e: Exception) {
            result.error("RECORD_ERROR", "Failed to resume: ${e.message}", null)
        }
    }

    private fun stopAndReleaseRecorder() {
        isRecording = false
        amplitudeHandler.removeCallbacks(amplitudeRunnable)
        try { mediaRecorder?.stop() } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        currentRecordingPath = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun getInstallerPackageName(): String? {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        } catch (_: Exception) {
            null
        }
    }

    private fun openAudioInFlick(
        filePath: String,
        mimeType: String?,
        result: MethodChannel.Result,
    ) {
        try {
            if (!isPackageInstalled(FLICK_PACKAGE)) {
                result.error("FLICK_NOT_INSTALLED", "Flick is not installed", null)
                return
            }

            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                return
            }

            val resolvedMimeType = mimeType?.takeIf { it.isNotBlank() } ?: "audio/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                setPackage(FLICK_PACKAGE)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val authority = "${applicationContext.packageName}.fileProvider.com.crazecoder.openfile"
                val uri = FileProvider.getUriForFile(applicationContext, authority, file)

                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                intent.clipData = ClipData.newUri(contentResolver, file.name, uri)
                intent.setDataAndType(uri, resolvedMimeType)
                grantUriPermission(FLICK_PACKAGE, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                intent.setDataAndType(Uri.fromFile(file), resolvedMimeType)
            }

            if (intent.resolveActivity(packageManager) == null) {
                result.error("FLICK_UNAVAILABLE", "Flick cannot open this audio file", null)
                return
            }

            startActivity(intent)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("FLICK_UNAVAILABLE", "Flick cannot handle this file", e.message)
        } catch (e: Exception) {
            result.error("FLICK_OPEN_FAILED", "Failed to open Flick", e.message)
        }
    }

    private fun scanMediaFile(filePath: String, result: MethodChannel.Result) {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                return
            }
            
            // Use MediaScannerConnection to scan the file
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(filePath),
                null
            ) { path, uri ->
                if (uri != null) {
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
        } catch (e: Exception) {
            result.error("SCAN_ERROR", "Failed to scan file: ${e.message}", null)
        }
    }

    private fun setScreenshotProtectionEnabled(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun setAutoKillEnabled(enabled: Boolean) {
        isAutoKillEnabled = enabled
        if (!enabled) {
            cancelAutoKill()
        } else if (isStopped && !isChangingConfigurations) {
            scheduleAutoKill()
        }
    }

    private fun setAutoKillDelaySeconds(seconds: Int) {
        autoKillDelayMillis = seconds * 1000L
        autoKillPreferences.edit().putInt(AUTO_KILL_DELAY_KEY, seconds).apply()
    }

    private fun loadAutoKillDelayMillis(): Long {
        val seconds = autoKillPreferences.getInt(AUTO_KILL_DELAY_KEY, 0)
        return seconds * 1000L
    }

    private fun cancelAutoKill() {
        autoKillHandler.removeCallbacks(autoKillRunnable)
    }

    private fun scheduleAutoKill() {
        cancelAutoKill()
        if (autoKillDelayMillis <= 0L) {
            finishAndRemoveTask()
        } else {
            autoKillHandler.postDelayed(autoKillRunnable, autoKillDelayMillis)
        }
    }
    
    private fun enableHighFrameRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes.preferredDisplayModeId = getPreferredDisplayMode().modeId
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            var bestMode: Display.Mode? = null
            for (mode in modes) {
                if (bestMode == null || mode.refreshRate > bestMode.refreshRate) {
                    bestMode = mode
                }
            }
            bestMode?.let {
                val params = window.attributes
                params.preferredDisplayModeId = it.modeId
                window.attributes = params
            }
        }
    }
    
    private fun getPreferredDisplayMode(): Display.Mode {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val display = display
            if (display != null) {
                val modes = display.supportedModes
                var bestMode: Display.Mode = modes[0]
                for (mode in modes) {
                    if (mode.refreshRate > bestMode.refreshRate) {
                        bestMode = mode
                    }
                }
                return bestMode
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = windowManager.defaultDisplay
            val modes = display.supportedModes
            var bestMode: Display.Mode = modes[0]
            for (mode in modes) {
                if (mode.refreshRate > bestMode.refreshRate) {
                    bestMode = mode
                }
            }
            return bestMode
        }
        @Suppress("DEPRECATION")
        return windowManager.defaultDisplay.supportedModes[0]
    }
    
    override fun onStart() {
        super.onStart()
        isStopped = false
        cancelAutoKill()
    }

    override fun onStop() {
        super.onStop()
        isStopped = true
        if (isAutoKillEnabled && !isChangingConfigurations) {
            scheduleAutoKill()
        }
    }

    override fun onDestroy() {
        cancelAutoKill()
        stopAndReleaseRecorder()
        super.onDestroy()
    }
}
