package com.mossapps.locker

import android.app.assist.AssistStructure
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService as FrameworkAutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveRequest
import android.util.Log
import android.view.View
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi
import java.util.Locale
import java.util.UUID

@RequiresApi(Build.VERSION_CODES.O)
class AutofillService : FrameworkAutofillService() {

    override fun onFillRequest(request: FillRequest, cancellationSignal: CancellationSignal, callback: FillCallback) {
        logAutofillDiagnostic("request api=${Build.VERSION.SDK_INT}")
        val context = request.fillContexts.lastOrNull()
        if (context == null) {
            logAutofillDiagnostic("no_context")
            callback.onSuccess(null)
            return
        }

        val focusedId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) context.focusedId else null
        val fields = parseFields(context.structure, focusedId)
        val targets = selectAutofillTargets(fields.candidates)
        if (cancellationSignal.isCanceled) {
            logAutofillDiagnostic("request_canceled")
            return
        }
        if (targets == null) {
            val focusedStates = fields.focusedStates.ifEmpty { setOf("not_found") }
            val recognizedCount = fields.candidates.count { it.focused }
            logAutofillDiagnostic("no_target focused=${focusedStates.joinToString()} matches=$recognizedCount")
            callback.onSuccess(null)
            return
        }

        val webHost = (targets.website as? AutofillWebsite.Verified)?.host
        val targetStatus = when (val website = targets.website) {
            AutofillWebsite.Native -> AutofillSelectionActivity.TARGET_NATIVE
            is AutofillWebsite.Verified -> AutofillSelectionActivity.TARGET_VERIFIED_WEBSITE
            is AutofillWebsite.Unverified -> website.reason.code
        }
        val intent = Intent(this, AutofillSelectionActivity::class.java).apply {
            // Each suggestion carries only the field IDs from its own request.
            action = "com.mossapps.locker.autofill.AUTHENTICATE.${UUID.randomUUID()}"
            putExtra(AutofillSelectionActivity.EXTRA_USERNAME_ID, targets.username)
            putExtra(AutofillSelectionActivity.EXTRA_PASSWORD_ID, targets.password)
            putExtra(AutofillSelectionActivity.EXTRA_WEB_HOST, webHost)
            putExtra(AutofillSelectionActivity.EXTRA_TARGET_STATUS, targetStatus)
        }
        // The framework fills in its authentication extras when the user taps the suggestion.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val authentication = PendingIntent.getActivity(this, 0, intent, flags)
        val dataset = Dataset.Builder(autofillPresentation())
            .setAuthentication(authentication.intentSender)
        targets.username?.let { dataset.setValue(it, null) }
        targets.password?.let { dataset.setValue(it, null) }

        val response = FillResponse.Builder().addDataset(dataset.build()).build()
        logAutofillDiagnostic("suggestion target=$targetStatus")
        callback.onSuccess(response)
    }

    override fun onSaveRequest(request: SaveRequest, callback: android.service.autofill.SaveCallback) {
        callback.onSuccess()
    }

    private data class ParsedFields(
        val candidates: List<AutofillCandidate<AutofillId>>,
        val focusedStates: Set<String>,
    )

    private fun parseFields(
        structure: AssistStructure,
        focusedId: AutofillId?,
    ): ParsedFields {
        val fields = mutableListOf<AutofillCandidate<AutofillId>>()
        val focusedStates = mutableSetOf<String>()
        var nextScope = 0

        fun visit(node: AssistStructure.ViewNode, scope: Int, parentIsWeb: Boolean) {
            val html = node.htmlInfo
            val tag = html?.tag?.lowercase(Locale.ROOT)
            val webDomain = node.webDomain
            val isWeb = parentIsWeb || tag != null || webDomain != null || node.className == "android.webkit.WebView"
            val fieldScope = if (tag == "form" || (isWeb && !parentIsWeb)) nextScope++ else scope
            val id = node.autofillId
            val focused = focusedId?.let { it == id } ?: node.isFocused
            val state = when {
                id == null -> "no_id"
                node.autofillType != View.AUTOFILL_TYPE_TEXT -> "not_text"
                node.visibility != View.VISIBLE -> "not_visible"
                !node.isEnabled -> "disabled"
                node.width <= 0 || node.height <= 0 -> "empty_bounds"
                else -> {
                    val type = classifyAutofillField(
                        androidHints = node.autofillHints?.toList().orEmpty(),
                        inputType = node.inputType,
                        htmlTag = tag,
                        htmlAttributes = html?.attributes.orEmpty().associate {
                            it.first.lowercase(Locale.ROOT) to it.second
                        },
                    )
                    if (type == null) {
                        "not_sign_in"
                    } else {
                        val website = if (isWeb) {
                            verifyAutofillWebsite(
                                supportsWebScheme = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P,
                                fieldDomain = webDomain,
                                fieldScheme = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) node.webScheme else null,
                            )
                        } else {
                            AutofillWebsite.Native
                        }
                        fields.add(AutofillCandidate(id, type, fieldScope, focused, website))
                        "recognized"
                    }
                }
            }
            if (focused) focusedStates.add(state)

            for (i in 0 until node.childCount) {
                visit(node.getChildAt(i), fieldScope, isWeb)
            }
        }
        for (i in 0 until structure.windowNodeCount) {
            visit(structure.getWindowNodeAt(i).rootViewNode, nextScope++, false)
        }
        return ParsedFields(fields, focusedStates)
    }
}

// Only pass fixed outcomes and counts. Never log field metadata, URLs, or vault values.
internal fun Context.logAutofillDiagnostic(message: String) {
    if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
        Log.d("LatchAutofill", message)
    }
}
