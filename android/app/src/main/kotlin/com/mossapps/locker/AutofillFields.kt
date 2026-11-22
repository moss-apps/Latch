package com.mossapps.locker

import android.text.InputType
import android.view.View
import java.net.URI
import java.util.Locale

internal enum class FieldType { USERNAME, PASSWORD }

internal enum class AutofillWebsiteFailure(val code: String) {
    ANDROID_VERSION("AF01"),
    MISSING_DOMAIN("AF02"),
    MISSING_SCHEME("AF03"),
    NOT_HTTPS("AF04"),
    INVALID_DOMAIN("AF05"),
}

internal sealed interface AutofillWebsite {
    object Native : AutofillWebsite
    data class Verified(val host: String) : AutofillWebsite
    data class Unverified(val reason: AutofillWebsiteFailure) : AutofillWebsite
}

internal data class AutofillCandidate<Id>(
    val id: Id,
    val type: FieldType,
    val scope: Int,
    val focused: Boolean,
    val website: AutofillWebsite = AutofillWebsite.Native,
)

internal data class AutofillTargets<Id>(
    val username: Id?,
    val password: Id?,
    val website: AutofillWebsite,
)

internal fun verifyAutofillWebsite(
    supportsWebScheme: Boolean,
    fieldDomain: String?,
    fieldScheme: String?,
): AutofillWebsite {
    // Only the field's own metadata is evidence of its origin.
    val failure = when {
        !supportsWebScheme -> AutofillWebsiteFailure.ANDROID_VERSION
        fieldDomain.isNullOrBlank() -> AutofillWebsiteFailure.MISSING_DOMAIN
        fieldScheme.isNullOrBlank() -> AutofillWebsiteFailure.MISSING_SCHEME
        !fieldScheme.equals("https", ignoreCase = true) -> AutofillWebsiteFailure.NOT_HTTPS
        else -> {
            val host = httpsAutofillHost("https://$fieldDomain")
            if (host != null) return AutofillWebsite.Verified(host)
            AutofillWebsiteFailure.INVALID_DOMAIN
        }
    }
    return AutofillWebsite.Unverified(failure)
}

internal fun <Id> selectAutofillTargets(
    candidates: List<AutofillCandidate<Id>>,
): AutofillTargets<Id>? {
    val focused = candidates.singleOrNull { it.focused } ?: return null
    if (focused.website is AutofillWebsite.Unverified) {
        return AutofillTargets(
            username = focused.id.takeIf { focused.type == FieldType.USERNAME },
            password = focused.id.takeIf { focused.type == FieldType.PASSWORD },
            website = focused.website,
        )
    }

    val related = candidates.filter {
        it.scope == focused.scope && it.website == focused.website
    }
    val companion = if (related.count { it.type == focused.type } == 1) {
        related.singleOrNull { it.type != focused.type }
    } else {
        null
    }

    return if (focused.type == FieldType.USERNAME) {
        AutofillTargets(focused.id, companion?.id, focused.website)
    } else {
        AutofillTargets(companion?.id, focused.id, focused.website)
    }
}

internal fun classifyAutofillField(
    androidHints: List<String>,
    inputType: Int,
    htmlTag: String? = null,
    htmlAttributes: Map<String, String> = emptyMap(),
): FieldType? {
    val htmlType = htmlAttributes["type"]?.trim()?.lowercase(Locale.ROOT).orEmpty()
    if (htmlTag != null && (htmlTag != "input" || htmlType !in HTML_CREDENTIAL_TYPES)) return null

    val hints = androidHints.map { it.trim().lowercase(Locale.ROOT) } +
        htmlAttributes["autocomplete"].orEmpty().lowercase(Locale.ROOT).split(Regex("\\s+"))
    if (hints.any { it in EXCLUDED_HINTS }) return null
    if (htmlType == "password" || "current-password" in hints || View.AUTOFILL_HINT_PASSWORD in hints) {
        return FieldType.PASSWORD
    }
    if (htmlType == "email" || hints.any { it in USERNAME_HINTS }) return FieldType.USERNAME

    if (htmlTag != null) {
        for (attribute in listOf("name", "id")) {
            val name = htmlAttributes[attribute]?.lowercase(Locale.ROOT)?.filter { it.isLetterOrDigit() }
            if (name in HTML_USERNAME_NAMES) return FieldType.USERNAME
        }
        return null
    }

    val variation = inputType and InputType.TYPE_MASK_VARIATION
    return when (inputType and InputType.TYPE_MASK_CLASS) {
        InputType.TYPE_CLASS_TEXT -> when (variation) {
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD -> FieldType.PASSWORD
            InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> FieldType.USERNAME
            else -> null
        }
        InputType.TYPE_CLASS_NUMBER -> {
            if (variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD) FieldType.PASSWORD else null
        }
        else -> null
    }
}

internal fun httpsAutofillHost(url: String): String? {
    val uri = runCatching { URI(url.trim()) }.getOrNull() ?: return null
    if (!uri.scheme.equals("https", ignoreCase = true) || uri.rawUserInfo != null) return null
    return uri.host?.trimEnd('.')?.lowercase(Locale.ROOT)?.takeIf { it.isNotEmpty() }
}

private val HTML_CREDENTIAL_TYPES = setOf("", "text", "email", "password")
private val EXCLUDED_HINTS = setOf("new-password", "new-username", "newpassword", "newusername", "one-time-code")
private val USERNAME_HINTS = setOf(View.AUTOFILL_HINT_USERNAME, "email", "emailaddress")
private val HTML_USERNAME_NAMES = setOf(
    "username", "user", "userid", "email", "emailaddress", "useremail",
    "login", "loginid", "loginemail", "loginusername",
)
