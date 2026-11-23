package hu.nahu02.event_snap_2

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** Names shared by the Snap entry points (see also `SnapFileStore.directoryName` in Dart). */
internal object SnapContract {
    const val ACTION_SNAP = "hu.nahu02.event_snap_2.action.SNAP"

    /** MainActivity intent carrying the result of a capture. */
    const val ACTION_SNAP_RESULT = "hu.nahu02.event_snap_2.action.SNAP_RESULT"
    const val EXTRA_CROP = "crop"
    const val EXTRA_PATH = "snap_path"
    const val EXTRA_ERROR = "snap_error"

    const val ERROR_SERVICE_DISABLED = "serviceDisabled"
    const val ERROR_UNSUPPORTED = "unsupported"
    const val ERROR_SECURE = "secure"
    const val ERROR_FAILED = "failed"

    const val DIRECTORY_NAME = "snaps"
    const val MIME_TYPE = "image/jpeg"

    fun directory(context: Context): File = File(context.cacheDir, DIRECTORY_NAME).apply { mkdirs() }

    /** Fresh file in the app-private snaps folder (never MediaStore / shared storage). */
    fun newFile(context: Context, prefix: String): File =
        File(directory(context), "${prefix}_${System.currentTimeMillis()}.jpg")
}

/**
 * Takes a screenshot through [SnapAccessibilityService] and stores it as a JPEG in
 * `cacheDir/snaps/`. Nothing is written to the gallery.
 *
 * Callbacks run on a background thread.
 */
internal object SnapCapture {
    private const val TAG = "EventSnapSnap"

    /** Android allows about one screenshot per second per service. */
    private const val MIN_INTERVAL_MS = 1100L
    private const val JPEG_QUALITY = 92

    /** `AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT` (API 30). */
    private const val ERROR_INTERVAL_TIME_SHORT = 3

    /** `AccessibilityService.ERROR_TAKE_SCREENSHOT_SECURE_WINDOW` (API 34). */
    private const val ERROR_SECURE_WINDOW = 6

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "EventSnapCapture").apply { isDaemon = true }
    }
    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    private var lastAttemptAt = 0L

    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    /**
     * Captures the screen. [maxEdge] > 0 downscales the saved JPEG so its long
     * edge is at most that many pixels. [onDone] gets the file, or an
     * `SnapContract.ERROR_*` code.
     */
    fun capture(context: Context, maxEdge: Int, onDone: (File?, String?) -> Unit) {
        val appContext = context.applicationContext
        if (!isSupported()) return onDone(null, SnapContract.ERROR_UNSUPPORTED)
        val service = SnapAccessibilityService.instance
            ?: return onDone(null, SnapContract.ERROR_SERVICE_DISABLED)
        executor.execute {
            try {
                val wait = lastAttemptAt + MIN_INTERVAL_MS - System.currentTimeMillis()
                if (wait > 0) Thread.sleep(wait)
                takeScreenshot(appContext, service, maxEdge, retry = true, onDone = onDone)
            } catch (t: Throwable) {
                Log.w(TAG, "Capture failed", t)
                onDone(null, SnapContract.ERROR_FAILED)
            }
        }
    }

    private fun takeScreenshot(
        context: Context,
        service: AccessibilityService,
        maxEdge: Int,
        retry: Boolean,
        onDone: (File?, String?) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return onDone(null, SnapContract.ERROR_UNSUPPORTED)
        lastAttemptAt = System.currentTimeMillis()
        service.takeScreenshot(
            Display.DEFAULT_DISPLAY,
            executor,
            object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                    try {
                        onDone(save(context, result, maxEdge), null)
                    } catch (e: BlankCaptureException) {
                        onDone(null, SnapContract.ERROR_SECURE)
                    } catch (t: Throwable) {
                        Log.w(TAG, "Could not save screenshot", t)
                        onDone(null, SnapContract.ERROR_FAILED)
                    }
                }

                override fun onFailure(errorCode: Int) {
                    Log.w(TAG, "takeScreenshot failed: $errorCode")
                    when {
                        errorCode == ERROR_INTERVAL_TIME_SHORT && retry ->
                            handler.postDelayed(
                                { executor.execute { takeScreenshot(context, service, maxEdge, false, onDone) } },
                                MIN_INTERVAL_MS,
                            )
                        errorCode == ERROR_SECURE_WINDOW -> onDone(null, SnapContract.ERROR_SECURE)
                        else -> onDone(null, SnapContract.ERROR_FAILED)
                    }
                }
            },
        )
    }

    private class BlankCaptureException : Exception()

    /** HardwareBuffer → Bitmap → JPEG in the snaps folder. */
    private fun save(context: Context, result: AccessibilityService.ScreenshotResult, maxEdge: Int): File {
        val buffer = result.hardwareBuffer
        var hardware: Bitmap? = null
        var software: Bitmap? = null
        var scaled: Bitmap? = null
        try {
            hardware = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                ?: throw IllegalStateException("wrapHardwareBuffer returned null")
            software = hardware.copy(Bitmap.Config.ARGB_8888, false)
                ?: throw IllegalStateException("Bitmap copy failed")
            if (isBlank(software)) throw BlankCaptureException()
            val longEdge = maxOf(software.width, software.height)
            scaled = if (maxEdge > 0 && longEdge > maxEdge) {
                val factor = maxEdge.toFloat() / longEdge
                Bitmap.createScaledBitmap(
                    software,
                    (software.width * factor).toInt().coerceAtLeast(1),
                    (software.height * factor).toInt().coerceAtLeast(1),
                    true,
                )
            } else {
                software
            }
            val file = SnapContract.newFile(context, "snap")
            try {
                FileOutputStream(file).use { out ->
                    if (!scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)) {
                        throw IllegalStateException("JPEG compression failed")
                    }
                }
            } catch (t: Throwable) {
                file.delete()
                throw t
            }
            return file
        } finally {
            buffer.close()
            if (scaled != null && scaled !== software) scaled.recycle()
            software?.recycle()
            hardware?.recycle()
        }
    }

    /** Secure windows (FLAG_SECURE) are delivered as black pixels on some Android versions. */
    private fun isBlank(bitmap: Bitmap): Boolean {
        val steps = 24
        for (yi in 0 until steps) {
            for (xi in 0 until steps) {
                val x = (bitmap.width - 1) * xi / (steps - 1)
                val y = (bitmap.height - 1) * yi / (steps - 1)
                val pixel = bitmap.getPixel(x, y)
                if (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel) > 12) return false
            }
        }
        return true
    }
}
