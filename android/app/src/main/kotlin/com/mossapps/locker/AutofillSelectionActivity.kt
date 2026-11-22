package com.mossapps.locker

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@RequiresApi(Build.VERSION_CODES.O)
class AutofillSelectionActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.mossapps.locker/autofill"
    private var usernameId: AutofillId? = null
    private var passwordId: AutofillId? = null
    private var webHost: String? = null
    private var websiteFailure: String? = null
    private var validRequest = false

    override fun getDartEntrypointFunctionName(): String = "autofillMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        usernameId = readFieldId(EXTRA_USERNAME_ID)
        passwordId = readFieldId(EXTRA_PASSWORD_ID)
        webHost = intent.getStringExtra(EXTRA_WEB_HOST)
        val targetStatus = intent.getStringExtra(EXTRA_TARGET_STATUS)
        websiteFailure = AutofillWebsiteFailure.entries.firstOrNull { it.code == targetStatus }?.code
        val validTarget = when (targetStatus) {
            TARGET_NATIVE -> webHost == null
            TARGET_VERIFIED_WEBSITE -> !webHost.isNullOrEmpty()
            else -> websiteFailure != null && webHost == null
        }
        validRequest = intent.hasExtra(AutofillManager.EXTRA_ASSIST_STRUCTURE) &&
            (usernameId != null || passwordId != null) && validTarget
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        if (!validRequest) {
            logAutofillDiagnostic("picker_invalid_request")
            finish()
        } else {
            logAutofillDiagnostic("picker_opened")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFillTarget" -> {
                    if (!validRequest) {
                        result.error("invalid_request", null, null)
                    } else {
                        result.success(mapOf(
                            "webHost" to webHost,
                            "websiteFailure" to websiteFailure,
                        ))
                    }
                }
                "fillCredentials" -> {
                    val username = call.argument<String>("username") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    val url = call.argument<String>("url") ?: ""
                    fillCredentials(username, password, url, result)
                }
                "cancel" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun fillCredentials(username: String, password: String, url: String, result: MethodChannel.Result) {
        if (!validRequest || websiteFailure != null) {
            result.error("website_unavailable", null, null)
            return
        }
        if (webHost != null && httpsAutofillHost(url) != webHost) {
            logAutofillDiagnostic("entry_website_mismatch")
            result.error("website_mismatch", null, null)
            return
        }

        val usernameTarget = usernameId?.takeIf { username.isNotEmpty() }
        val passwordTarget = passwordId?.takeIf { password.isNotEmpty() }
        if (usernameTarget == null && passwordTarget == null) {
            logAutofillDiagnostic("entry_no_values")
            result.error("no_values", null, null)
            return
        }

        val dataset = Dataset.Builder(autofillPresentation())
        usernameTarget?.let { dataset.setValue(it, AutofillValue.forText(username)) }
        passwordTarget?.let { dataset.setValue(it, AutofillValue.forText(password)) }
        val data = Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, dataset.build())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            data.putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, true)
        }
        setResult(RESULT_OK, data)
        logAutofillDiagnostic("dataset_returned")
        result.success(null)
        finish()
    }

    @Suppress("DEPRECATION")
    private fun readFieldId(key: String): AutofillId? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, AutofillId::class.java)
        } else {
            intent.getParcelableExtra(key)
        }

    internal companion object {
        const val EXTRA_USERNAME_ID = "com.mossapps.locker.autofill.USERNAME_ID"
        const val EXTRA_PASSWORD_ID = "com.mossapps.locker.autofill.PASSWORD_ID"
        const val EXTRA_WEB_HOST = "com.mossapps.locker.autofill.WEB_HOST"
        const val EXTRA_TARGET_STATUS = "com.mossapps.locker.autofill.TARGET_STATUS"
        const val TARGET_NATIVE = "native"
        const val TARGET_VERIFIED_WEBSITE = "verified_website"
    }
}

internal fun Context.autofillPresentation() = RemoteViews(packageName, R.layout.autofill_suggestion)
