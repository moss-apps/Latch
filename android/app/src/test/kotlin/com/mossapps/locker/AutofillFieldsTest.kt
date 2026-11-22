package com.mossapps.locker

import android.text.InputType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AutofillFieldsTest {
    @Test
    fun recognizesBrowserInputsWithoutAndroidHints() {
        assertEquals(FieldType.PASSWORD, htmlInput("type" to "password"))
        assertEquals(FieldType.USERNAME, htmlInput("type" to "email"))
        assertEquals(FieldType.USERNAME, htmlInput("type" to "text", "id" to "login-email"))
        assertEquals(FieldType.PASSWORD, htmlInput("type" to "text", "autocomplete" to "section-login current-password"))
    }

    @Test
    fun ignoresOtherHtmlInputs() {
        assertNull(htmlInput("type" to "hidden", "autocomplete" to "current-password"))
        assertNull(htmlInput("type" to "password", "autocomplete" to "new-password"))
        assertNull(htmlInput("type" to "text", "autocomplete" to "one-time-code", "name" to "login"))
        assertNull(htmlInput("type" to "text", "name" to "search"))
    }

    @Test
    fun recognizesNativeHintsAndInputTypes() {
        assertEquals(FieldType.USERNAME, classifyAutofillField(listOf("emailAddress"), 0))
        assertEquals(
            FieldType.PASSWORD,
            classifyAutofillField(emptyList(), InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD),
        )
        assertEquals(
            FieldType.PASSWORD,
            classifyAutofillField(emptyList(), InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD),
        )
        assertNull(classifyAutofillField(emptyList(), InputType.TYPE_CLASS_TEXT))
    }

    @Test
    fun pairsOnlyUnambiguousFieldsInTheFocusedFormAndHost() {
        val password = webField("pass", FieldType.PASSWORD, focused = true)
        val username = webField("user", FieldType.USERNAME)
        assertEquals(
            AutofillTargets("user", "pass", VERIFIED),
            selectAutofillTargets(listOf(
                password,
                username,
                username.copy(id = "otherForm", scope = 2),
                username.copy(id = "otherHost", website = AutofillWebsite.Verified("other.example")),
                username.copy(id = "noHost", website = NO_DOMAIN),
                username.copy(id = "native", website = AutofillWebsite.Native),
            )),
        )
        assertEquals(
            AutofillTargets(null, "pass", VERIFIED),
            selectAutofillTargets(listOf(password, username, username.copy(id = "ambiguous"))),
        )
    }

    @Test
    fun targetsWithoutAWebsiteHostCanExplainWhyFillIsUnavailable() {
        val password = webField("pass", FieldType.PASSWORD)
        assertNull(selectAutofillTargets(listOf(password)))
        assertEquals(
            AutofillTargets(null, "pass", NO_DOMAIN),
            selectAutofillTargets(listOf(
                password.copy(focused = true, website = NO_DOMAIN),
                webField("user", FieldType.USERNAME),
            )),
        )
        assertEquals(
            AutofillTargets(null, "pass", AutofillWebsite.Native),
            selectAutofillTargets(listOf(AutofillCandidate("pass", FieldType.PASSWORD, 1, true))),
        )
    }

    @Test
    fun distinguishesWebsiteVerificationFailuresWithoutTreatingThemAsNative() {
        assertEquals(
            AutofillWebsite.Unverified(AutofillWebsiteFailure.ANDROID_VERSION),
            verifyAutofillWebsite(false, HOST, null),
        )
        assertEquals(NO_DOMAIN, verifyAutofillWebsite(true, null, "https"))
        assertEquals(
            AutofillWebsite.Unverified(AutofillWebsiteFailure.MISSING_SCHEME),
            verifyAutofillWebsite(true, HOST, null),
        )
        assertEquals(
            AutofillWebsite.Unverified(AutofillWebsiteFailure.NOT_HTTPS),
            verifyAutofillWebsite(true, HOST, "http"),
        )
        assertEquals(
            AutofillWebsite.Unverified(AutofillWebsiteFailure.INVALID_DOMAIN),
            verifyAutofillWebsite(true, "user@portal.example", "https"),
        )
        assertEquals(VERIFIED, verifyAutofillWebsite(true, "PORTAL.EXAMPLE.", "HTTPS"))
    }

    @Test
    fun parsesTheStoredUrlByHttpsHost() {
        assertEquals(HOST, httpsAutofillHost(" https://PORTAL.example/login?source=app "))
        assertEquals("portal.example.other.test", httpsAutofillHost("https://portal.example.other.test/login"))
        assertNull(httpsAutofillHost("https://portal.example@other.test/login"))
        assertNull(httpsAutofillHost("http://portal.example/login"))
        assertNull(httpsAutofillHost("portal.example/login"))
    }

    private fun htmlInput(vararg attributes: Pair<String, String>) =
        classifyAutofillField(emptyList(), 0, "input", mapOf(*attributes))

    private fun webField(id: String, type: FieldType, focused: Boolean = false) =
        AutofillCandidate(id, type, scope = 1, focused, website = VERIFIED)

    private companion object {
        const val HOST = "portal.example"
        val VERIFIED = AutofillWebsite.Verified(HOST)
        val NO_DOMAIN = AutofillWebsite.Unverified(AutofillWebsiteFailure.MISSING_DOMAIN)
    }
}
