package com.mossapps.locker

import android.app.assist.AssistStructure
import android.service.autofill.FillCallback
import android.view.autofill.AutofillId

enum class FieldType { USERNAME, PASSWORD }

data class AutofillField(val autofillId: AutofillId, val type: FieldType)

object AutofillCallbackHolder {
    var callback: FillCallback? = null
        private set
    var fields: List<AutofillField>? = null
        private set

    fun set(callback: FillCallback, fields: List<AutofillField>) {
        this.callback = callback
        this.fields = fields
    }

    fun cancel() {
        try { callback?.onSuccess(null) } catch (_: Exception) {}
        clear()
    }

    fun clear() {
        callback = null
        fields = null
    }
}
