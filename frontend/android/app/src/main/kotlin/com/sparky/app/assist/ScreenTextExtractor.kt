package com.sparky.app.assist

import android.app.assist.AssistStructure
import android.os.Build
import android.text.InputType
import android.view.View

/**
 * Pulls the visible text out of an [AssistStructure] in reading order. The
 * raw nodes go to Dart, which trims, dedupes and caps them (unit-tested
 * there); this side only skips what must never leave the device (password
 * fields) and what is not on screen.
 */
object ScreenTextExtractor {
    private const val MAX_NODES = 3000
    private const val MAX_RAW_CHARS = 40_000
    private const val MAX_DEPTH = 64

    class Result(
        /** `{text, desc}` maps: desc is true for a content description. */
        val nodes: List<Map<String, Any>>,
        /** A web domain some node reported (WebView / browser), if any. */
        val webDomain: String?,
    )

    fun extract(structure: AssistStructure): Result {
        val out = ArrayList<Map<String, Any>>()
        var chars = 0
        var domain: String? = null

        fun add(text: CharSequence?, desc: Boolean) {
            val s = text?.toString()?.trim() ?: return
            if (s.isEmpty() || out.size >= MAX_NODES || chars >= MAX_RAW_CHARS) return
            chars += s.length
            out.add(mapOf(AssistProtocol.NODE_TEXT to s, AssistProtocol.NODE_DESC to desc))
        }

        fun walk(node: AssistStructure.ViewNode, depth: Int) {
            if (depth > MAX_DEPTH || out.size >= MAX_NODES || chars >= MAX_RAW_CHARS) return
            if (node.visibility != View.VISIBLE) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (domain == null) node.webDomain?.takeIf { it.isNotBlank() }?.let { domain = it }
                if (isPassword(node.inputType)) return
            }
            val text = node.text
            if (!text.isNullOrBlank()) {
                add(text, false)
            } else if (node.childCount == 0) {
                add(node.contentDescription, true)
            }
            for (i in 0 until node.childCount) walk(node.getChildAt(i), depth + 1)
        }

        for (w in 0 until structure.windowNodeCount) {
            walk(structure.getWindowNodeAt(w).rootViewNode, 0)
        }
        return Result(out, domain)
    }

    private fun isPassword(inputType: Int): Boolean {
        val cls = inputType and InputType.TYPE_MASK_CLASS
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        return when (cls) {
            InputType.TYPE_CLASS_TEXT -> variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            InputType.TYPE_CLASS_NUMBER -> variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
            else -> false
        }
    }
}
