package hu.nahu02.event_snap_2

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Parcelable

/**
 * What a share (`ACTION_SEND` / `ACTION_SEND_MULTIPLE`) or view (`ACTION_VIEW` of
 * a `text/calendar` file) intent carries, before any I/O happens.
 */
internal data class SharedIntentData(
    /** Text from `EXTRA_TEXT` (with a useful `EXTRA_SUBJECT` prepended), or null. */
    val text: String?,
    /** Image URIs in the order the sender listed them (not yet capped). */
    val imageUris: List<Uri>,
    /** A text document to read when no inline text was shared (e.g. a shared .txt or an opened .ics). */
    val textDocumentUri: Uri?,
) {
    val isEmpty: Boolean get() = text == null && imageUris.isEmpty() && textDocumentUri == null
}

/** Extracts [SharedIntentData] from incoming intents. Pure: no I/O. */
internal object SharedIntentParser {
    private val FILE_NAME_SUBJECT =
        Regex("""^[^\s/\\]+\.(jpe?g|png|gif|webp|heic|heif|bmp|txt|ics)$""", RegexOption.IGNORE_CASE)

    /** Returns null when the intent carries nothing the app should handle. */
    fun parse(intent: Intent): SharedIntentData? {
        // Relaunching a task from Recents re-delivers the original share intent.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        val type = intent.type?.lowercase()
        val data = when (intent.action) {
            Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE -> parseSend(intent, type)
            Intent.ACTION_VIEW -> parseView(intent, type)
            else -> null
        }
        return data?.takeUnless { it.isEmpty }
    }

    private fun parseSend(intent: Intent, type: String?): SharedIntentData {
        val text = composeText(subject = subjectOf(intent), body = bodyOf(intent))
        val streams = streamUris(intent)
        return if (type != null && type.startsWith("text/")) {
            SharedIntentData(
                text = text,
                imageUris = emptyList(),
                textDocumentUri = if (text == null) streams.firstOrNull() else null,
            )
        } else {
            // image/* (the manifest only routes text/plain and image/* here).
            SharedIntentData(text = text, imageUris = streams, textDocumentUri = null)
        }
    }

    /**
     * The only VIEW filter is `text/calendar`; the type may still be unset when
     * the sender let the system resolve it from the content provider.
     */
    private fun parseView(intent: Intent, type: String?): SharedIntentData? {
        val uri = intent.data ?: return null
        val isCalendar =
            type == null ||
                type == "text/calendar" ||
                uri.lastPathSegment?.endsWith(".ics", ignoreCase = true) == true
        if (!isCalendar) return null
        return SharedIntentData(text = null, imageUris = emptyList(), textDocumentUri = uri)
    }

    private fun subjectOf(intent: Intent): String? =
        runCatching { intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString() }.getOrNull()

    private fun bodyOf(intent: Intent): String? {
        val single = runCatching { intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() }.getOrNull()
        if (!single.isNullOrBlank()) return single
        // SEND_MULTIPLE senders may attach one text per item.
        val multiple = runCatching { intent.getCharSequenceArrayListExtra(Intent.EXTRA_TEXT) }.getOrNull()
            ?.mapNotNull { it?.toString()?.trim()?.takeIf(String::isNotEmpty) }
            ?.distinct()
        if (!multiple.isNullOrEmpty()) return multiple.joinToString("\n")
        // Some senders only fill ClipData.
        val clip = intent.clipData ?: return null
        return (0 until clip.itemCount)
            .mapNotNull { clip.getItemAt(it).text?.toString()?.trim()?.takeIf(String::isNotEmpty) }
            .distinct()
            .takeIf { it.isNotEmpty() }
            ?.joinToString("\n")
    }

    /**
     * Prepends the subject when it adds information: e-mail subjects and web page
     * titles (Chrome shares the title as subject and the URL as text) are useful
     * context; file names ("IMG_1234.jpg") are not.
     */
    internal fun composeText(subject: String?, body: String?): String? {
        val s = subject?.trim()?.takeIf { it.isNotEmpty() && !FILE_NAME_SUBJECT.matches(it) }
        val b = body?.trim()?.takeIf { it.isNotEmpty() }
        return when {
            s == null -> b
            b == null -> s
            b.contains(s, ignoreCase = true) -> b
            else -> "$s\n\n$b"
        }
    }

    /** `EXTRA_STREAM` (list or single, whatever the action says) and, as a fallback, `ClipData` URIs. */
    private fun streamUris(intent: Intent): List<Uri> {
        val uris = LinkedHashSet<Uri>()
        parcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.filterNotNullTo(uris)
        if (uris.isEmpty()) parcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let(uris::add)
        if (uris.isEmpty()) {
            intent.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let(uris::add)
            }
        }
        return uris.toList()
    }

    // The typed getters exist since API 33 but are only reliable from API 34
    // (https://issuetracker.google.com/issues/240585930).
    private fun <T : Parcelable> parcelableExtra(intent: Intent, key: String, clazz: Class<T>): T? =
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                intent.getParcelableExtra(key, clazz)
            } else {
                @Suppress("DEPRECATION")
                val value: Parcelable? = intent.getParcelableExtra(key)
                if (clazz.isInstance(value)) clazz.cast(value) else null
            }
        }.getOrNull()

    private fun <T : Parcelable> parcelableArrayListExtra(intent: Intent, key: String, clazz: Class<T>): List<T?>? =
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                intent.getParcelableArrayListExtra(key, clazz)
            } else {
                @Suppress("DEPRECATION")
                val values: ArrayList<Parcelable?>? = intent.getParcelableArrayListExtra(key)
                values?.map { value -> if (clazz.isInstance(value)) clazz.cast(value) else null }
            }
        }.getOrNull()
}
