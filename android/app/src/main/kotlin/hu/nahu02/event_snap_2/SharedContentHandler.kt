package hu.nahu02.event_snap_2

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Delivers content shared into the app to Flutter over the
 * `hu.nahu02.event_snap_2/share` method channel.
 *
 * Protocol (Dart side: `lib/services/platform/android_shared_content_source.dart`):
 * - Dart → native `getInitialSharedContent`: payload of the intent that created
 *   the activity, or null. Answered once (later calls get null); if the content
 *   is still being processed the reply waits for it.
 * - Dart → native `ready`: the Dart handler is installed. Content that arrived
 *   via `onNewIntent` before that is queued and pushed right after.
 * - native → Dart `onSharedContent(payload)`: content delivered via `onNewIntent`.
 *
 * Payload: `{"text": String?, "images": [{"path": String, "mimeType": String}]}`.
 *
 * All methods must be called on the main thread; image processing runs on a
 * single background thread (so deliveries keep their order).
 */
internal class SharedContentHandler(
    private val processor: SharedImageProcessor,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "hu.nahu02.event_snap_2/share"
        const val METHOD_GET_INITIAL = "getInitialSharedContent"
        const val METHOD_READY = "ready"
        const val METHOD_ON_SHARED_CONTENT = "onSharedContent"

        private const val MAX_QUEUED = 8
        private const val TAG = "EventSnapShare"
    }

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "EventSnapShare").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null
    private var dartReady = false
    private var released = false

    private var initialProcessing = false
    private var initialConsumed = false
    private var initialPayload: Map<String, Any?>? = null
    private val initialWaiters = mutableListOf<MethodChannel.Result>()

    private val queue = ArrayDeque<Map<String, Any?>>()

    fun attach(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
        dartReady = false
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        dartReady = false
    }

    /** Stops background work; pending results are dropped (the engine is going away). */
    fun release() {
        released = true
        detach()
        initialWaiters.clear()
        queue.clear()
        executor.shutdown()
    }

    fun deleteStaleFilesAsync() {
        runInBackground { processor.deleteStaleFiles() }
    }

    /** The intent that created the activity; served by `getInitialSharedContent`. */
    fun handleInitialIntent(intent: Intent?) {
        val data = intent?.let(SharedIntentParser::parse) ?: return
        initialProcessing = true
        process(data) { payload ->
            initialProcessing = false
            initialPayload = payload
            val waiters = initialWaiters.toList()
            initialWaiters.clear()
            waiters.forEach { it.success(takeInitialPayload()) }
        }
    }

    /** An intent delivered while the activity is running; pushed to Dart. */
    fun handleNewIntent(intent: Intent?) {
        val data = intent?.let(SharedIntentParser::parse) ?: return
        process(data) { payload -> if (payload != null) deliver(payload) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_GET_INITIAL ->
                if (initialProcessing) initialWaiters.add(result) else result.success(takeInitialPayload())
            METHOD_READY -> {
                dartReady = true
                result.success(null)
                flushQueue()
            }
            else -> result.notImplemented()
        }
    }

    private fun takeInitialPayload(): Map<String, Any?>? {
        if (initialConsumed) return null
        initialConsumed = true
        return initialPayload.also { initialPayload = null }
    }

    private fun deliver(payload: Map<String, Any?>) {
        if (dartReady && channel != null) {
            push(payload)
        } else {
            if (queue.size >= MAX_QUEUED) queue.removeFirst()
            queue.addLast(payload)
        }
    }

    private fun flushQueue() {
        while (dartReady && channel != null && queue.isNotEmpty()) push(queue.removeFirst())
    }

    private fun push(payload: Map<String, Any?>) {
        val target = channel ?: return deliver(payload)
        target.invokeMethod(
            METHOD_ON_SHARED_CONTENT,
            payload,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.w(TAG, "Flutter failed to handle shared content: $errorCode $errorMessage")
                }

                override fun notImplemented() {
                    // No Dart handler (e.g. after a hot restart): keep it until the next `ready`.
                    if (released) return
                    dartReady = false
                    deliver(payload)
                }
            },
        )
    }

    /** Builds the payload off the main thread and hands it to [onDone] on the main thread. */
    private fun process(data: SharedIntentData, onDone: (Map<String, Any?>?) -> Unit) {
        val submitted = runInBackground {
            val payload =
                try {
                    buildPayload(data)
                } catch (t: Throwable) {
                    Log.w(TAG, "Failed to process shared content", t)
                    data.text?.let { mapOf("text" to it, "images" to emptyList<Any>()) }
                }
            mainHandler.post { if (!released) onDone(payload) }
        }
        if (!submitted && !released) onDone(data.text?.let { mapOf("text" to it, "images" to emptyList<Any>()) })
    }

    private fun buildPayload(data: SharedIntentData): Map<String, Any?>? {
        val text = data.text ?: data.textDocumentUri?.let(processor::readText)
        val images = processor.processImages(data.imageUris).map { file ->
            mapOf("path" to file.absolutePath, "mimeType" to SharedImageProcessor.OUTPUT_MIME_TYPE)
        }
        if (text == null && images.isEmpty()) return null
        return mapOf("text" to text, "images" to images)
    }

    private fun runInBackground(task: () -> Unit): Boolean =
        try {
            executor.execute(task)
            true
        } catch (e: RejectedExecutionException) {
            Log.w(TAG, "Background executor unavailable", e)
            false
        }
}
