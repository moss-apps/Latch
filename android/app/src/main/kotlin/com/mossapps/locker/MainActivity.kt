package com.mossapps.locker

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.mossapps.locker/autokill"
    private val AUTO_KILL_PREFS = "locker_auto_kill"
    private val AUTO_KILL_DELAY_KEY = "delay_seconds"
    private val MEDIA_SCANNER_CHANNEL = "com.example.vault/media_scanner"
    private val SCREENSHOT_PROTECTION_CHANNEL = "com.mossapps.locker/screenshot_protection"
    private val FLICK_CHANNEL = "com.mossapps.locker/flick"
    private val FLICK_PACKAGE = "com.mossapps.flick"
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
    private var autoKillDelayMillis = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        autoKillDelayMillis = loadAutoKillDelayMillis()
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
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
        cancelAutoKill()
    }

    override fun onStop() {
        super.onStop()
        if (isAutoKillEnabled && !isChangingConfigurations) {
            scheduleAutoKill()
        }
    }

    override fun onDestroy() {
        cancelAutoKill()
        super.onDestroy()
    }
}
