package com.mossapps.locker

import android.app.assist.AssistStructure
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@RequiresApi(Build.VERSION_CODES.O)
class AutofillSelectionActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.mossapps.locker/autofill"

    override fun getDartEntrypointFunctionName(): String = "autofillMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "fillCredentials" -> {
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val title = call.argument<String>("title") ?: "Latch"
                    fillCredentials(username, password, title, result)
                }
                "cancel" -> {
                    AutofillCallbackHolder.cancel()
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun fillCredentials(username: String, password: String, title: String, result: MethodChannel.Result) {
        val callback = AutofillCallbackHolder.callback
        val fields = AutofillCallbackHolder.fields

        if (callback == null || fields == null) {
            result.error("no_callback", "No fill request pending", null)
            finish()
            return
        }

        try {
            val presentation = RemoteViews(packageName, R.layout.autofill_suggestion)
            presentation.setTextViewText(R.id.autofill_title, title)

            val builder = Dataset.Builder()
            var matched = false

            for (field in fields) {
                when (field.type) {
                    FieldType.USERNAME -> {
                        if (username.isNotEmpty()) {
                            builder.setValue(field.autofillId, AutofillValue.forText(username), presentation)
                            matched = true
                        }
                    }
                    FieldType.PASSWORD -> {
                        if (password.isNotEmpty()) {
                            builder.setValue(field.autofillId, AutofillValue.forText(password), presentation)
                            matched = true
                        }
                    }
                }
            }

            if (!matched) {
                AutofillCallbackHolder.cancel()
                result.success(null)
                finish()
                return
            }

            val response = FillResponse.Builder().addDataset(builder.build()).build()
            callback.onSuccess(response)
            AutofillCallbackHolder.clear()
            result.success(null)
            finish()
        } catch (e: Exception) {
            Log.e("AutofillSelection", "fill failed", e)
            AutofillCallbackHolder.cancel()
            result.error("fill_error", e.message, null)
            finish()
        }
    }

    override fun onDestroy() {
        AutofillCallbackHolder.cancel()
        super.onDestroy()
    }
}
