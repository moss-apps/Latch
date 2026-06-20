package com.mossapps.locker

import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.O)
class AutofillService : AutofillService() {

    override fun onFillRequest(request: FillRequest, cancellationSignal: CancellationSignal, callback: FillCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val fields = parseFields(structure)
        if (fields.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        AutofillCallbackHolder.set(callback, fields)

        val intent = Intent(this, AutofillSelectionActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
    }

    override fun onSaveRequest(request: SaveRequest, callback: android.service.autofill.SaveCallback) {
        callback.onSuccess()
    }

    private fun parseFields(structure: AssistStructure): List<AutofillField> {
        val fields = mutableListOf<AutofillField>()
        val seenIds = mutableSetOf<AutofillId>()

        for (i in 0 until structure.windowNodeCount) {
            traverseNode(structure.getWindowNodeAt(i).rootViewNode, fields, seenIds)
        }
        return fields
    }

    private fun traverseNode(node: AssistStructure.ViewNode, fields: MutableList<AutofillField>, seenIds: MutableSet<AutofillId>) {
        val id = node.autofillId
        if (id != null && id !in seenIds) {
            val type = classifyField(node)
            if (type != null) {
                fields.add(AutofillField(id, type))
                seenIds.add(id)
            }
        }

        for (i in 0 until node.childCount) {
            traverseNode(node.getChildAt(i), fields, seenIds)
        }
    }

    private fun classifyField(node: AssistStructure.ViewNode): FieldType? {
        val hints = node.autofillHints
        if (hints != null) {
            for (hint in hints) {
                when (hint) {
                    View.AUTOFILL_HINT_USERNAME, View.AUTOFILL_HINT_EMAIL_ADDRESS -> return FieldType.USERNAME
                    View.AUTOFILL_HINT_PASSWORD -> return FieldType.PASSWORD
                }
            }
        }

        val inputType = node.inputType
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        when (variation) {
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_NUMBER_VARIATION_PASSWORD -> return FieldType.PASSWORD
            InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS -> return FieldType.USERNAME
        }

        return null
    }
}
