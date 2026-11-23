package hu.nahu02.event_snap_2

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * `hu.nahu02.event_snap_2/snap` method channel (Dart side:
 * `lib/services/platform/snap_service.dart`):
 * - `getStatus` → `{supported, enabled}`
 * - `openAccessibilitySettings` → bool
 * - `cropImage {path, left, top, right, bottom}` (fractions 0..1) → `{path, mimeType}`
 */
internal class SnapChannelHandler(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "EventSnapCrop").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    fun release() {
        detach()
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(
                mapOf("supported" to SnapCapture.isSupported(), "enabled" to isServiceEnabled()),
            )
            "openAccessibilitySettings" -> result.success(openAccessibilitySettings())
            "cropImage" -> {
                val path = call.argument<String>("path")
                val left = call.argument<Double>("left")
                val top = call.argument<Double>("top")
                val right = call.argument<Double>("right")
                val bottom = call.argument<Double>("bottom")
                if (path == null || left == null || top == null || right == null || bottom == null) {
                    result.error("INVALID_ARGUMENT", "path and left/top/right/bottom are required", null)
                    return
                }
                executor.execute {
                    try {
                        val file = crop(File(path), left, top, right, bottom)
                        mainHandler.post {
                            result.success(mapOf("path" to file.absolutePath, "mimeType" to SnapContract.MIME_TYPE))
                        }
                    } catch (t: Throwable) {
                        Log.w(TAG, "Crop failed", t)
                        mainHandler.post { result.error("CROP_FAILED", t.message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Whether the user switched the EventSnap accessibility service on. */
    private fun isServiceEnabled(): Boolean {
        if (SnapAccessibilityService.instance != null) return true
        val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            ?: return false
        return manager
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any {
                val service = it.resolveInfo?.serviceInfo
                service?.packageName == context.packageName &&
                    service.name == SnapAccessibilityService::class.java.name
            }
    }

    private fun openAccessibilitySettings(): Boolean =
        try {
            context.startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (e: Exception) {
            Log.w(TAG, "Cannot open accessibility settings", e)
            false
        }

    /** Crops [source] (a file in the snaps folder) and writes a downscaled JPEG next to it. */
    private fun crop(source: File, left: Double, top: Double, right: Double, bottom: Double): File {
        val dir = SnapContract.directory(context).canonicalFile
        val canonical = source.canonicalFile
        require(canonical.parentFile == dir && canonical.isFile) { "Not a snap file" }

        val decoder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            BitmapRegionDecoder.newInstance(canonical.absolutePath)
        } else {
            @Suppress("DEPRECATION")
            BitmapRegionDecoder.newInstance(canonical.absolutePath, false)
        } ?: throw IllegalStateException("Cannot decode image")
        try {
            val w = decoder.width
            val h = decoder.height
            val region = Rect(
                (left.coerceIn(0.0, 1.0) * w).toInt(),
                (top.coerceIn(0.0, 1.0) * h).toInt(),
                (right.coerceIn(0.0, 1.0) * w).toInt().coerceAtMost(w),
                (bottom.coerceIn(0.0, 1.0) * h).toInt().coerceAtMost(h),
            )
            require(region.width() >= 1 && region.height() >= 1) { "Empty selection" }
            // Decode at a sample size that keeps the long edge near the 2048 px limit.
            val longEdge = maxOf(region.width(), region.height())
            var sample = 1
            while (longEdge / (sample * 2) >= SharedImageProcessor.MAX_EDGE_PX) sample *= 2
            val options = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
            }
            val decoded = decoder.decodeRegion(region, options) ?: throw IllegalStateException("Cannot decode region")
            var scaled: Bitmap = decoded
            try {
                val edge = maxOf(decoded.width, decoded.height)
                if (edge > SharedImageProcessor.MAX_EDGE_PX) {
                    val factor = SharedImageProcessor.MAX_EDGE_PX.toFloat() / edge
                    scaled = Bitmap.createScaledBitmap(
                        decoded,
                        (decoded.width * factor).toInt().coerceAtLeast(1),
                        (decoded.height * factor).toInt().coerceAtLeast(1),
                        true,
                    )
                }
                val out = SnapContract.newFile(context, "crop")
                try {
                    FileOutputStream(out).use {
                        if (!scaled.compress(Bitmap.CompressFormat.JPEG, 90, it)) {
                            throw IllegalStateException("JPEG compression failed")
                        }
                    }
                } catch (t: Throwable) {
                    out.delete()
                    throw t
                }
                return out
            } finally {
                if (scaled !== decoded) scaled.recycle()
                decoded.recycle()
            }
        } finally {
            decoder.recycle()
        }
    }

    companion object {
        const val CHANNEL = "hu.nahu02.event_snap_2/snap"
        private const val TAG = "EventSnapSnap"
    }
}
