package hu.nahu02.event_snap_2

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.net.Uri
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStreamReader
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

/**
 * Turns shared content URIs into local files the Flutter side can read:
 * images are copied into `cacheDir/shared_images/`, downscaled to at most
 * [MAX_EDGE_PX] on the long edge, rotated per EXIF and re-encoded as JPEG.
 *
 * Blocking I/O: call from a background thread only.
 */
internal class SharedImageProcessor(context: Context) {
    companion object {
        const val DIRECTORY_NAME = "shared_images"
        const val MAX_IMAGES = 4
        const val MAX_EDGE_PX = 2048
        const val JPEG_QUALITY = 85
        const val OUTPUT_MIME_TYPE = "image/jpeg"
        const val MAX_AGE_MS = 24L * 60 * 60 * 1000

        /** Inputs larger than this are skipped (protects the cache and the heap). */
        private const val MAX_SOURCE_BYTES = 64L * 1024 * 1024

        /** Upper bound of characters read from a shared text document. */
        private const val MAX_TEXT_CHARS = 100_000

        /** Unreadable images do not count towards [MAX_IMAGES]; this bounds the attempts. */
        private const val MAX_ATTEMPTS = MAX_IMAGES * 3

        private const val TAG = "EventSnapShare"

        /**
         * Largest power-of-two sample size that keeps the decoded long edge at or
         * above 3/4 of the target, so the final scaling step stays a mild
         * downscale (good quality) while decode memory stays bounded.
         */
        internal fun sampleSizeFor(longEdge: Int, maxEdge: Int = MAX_EDGE_PX): Int {
            val minSampledEdge = maxEdge * 3 / 4
            var sampleSize = 1
            while (longEdge / (sampleSize * 2) >= minSampledEdge) sampleSize *= 2
            return sampleSize
        }
    }

    private val appContext = context.applicationContext
    private val resolver: ContentResolver = appContext.contentResolver
    private val directory = File(appContext.cacheDir, DIRECTORY_NAME)

    /** Deletes cached shared images older than [MAX_AGE_MS]. */
    fun deleteStaleFiles(now: Long = System.currentTimeMillis()) {
        val files = directory.listFiles() ?: return
        var deleted = 0
        for (file in files) {
            if (now - file.lastModified() > MAX_AGE_MS && file.delete()) deleted++
        }
        if (deleted > 0) Log.d(TAG, "Deleted $deleted stale shared image(s)")
    }

    /** Processes up to [MAX_IMAGES] images; unreadable ones are skipped. */
    fun processImages(uris: List<Uri>): List<File> {
        val results = mutableListOf<File>()
        for ((attempt, uri) in uris.withIndex()) {
            if (results.size >= MAX_IMAGES || attempt >= MAX_ATTEMPTS) break
            processImage(uri)?.let(results::add)
        }
        if (uris.size > results.size) {
            Log.i(TAG, "Using ${results.size} of ${uris.size} shared image(s)")
        }
        return results
    }

    /** Returns the processed JPEG, or null if the URI can't be read or decoded. */
    fun processImage(uri: Uri): File? {
        if (!isAllowedSource(uri)) {
            Log.w(TAG, "Ignoring shared URI with a disallowed source: ${uri.scheme}://${uri.authority}")
            return null
        }
        if (!directory.isDirectory && !directory.mkdirs()) {
            Log.w(TAG, "Cannot create ${directory.path}")
            return null
        }
        val id = UUID.randomUUID().toString()
        val source = File(directory, "$id.tmp")
        val output = File(directory, "$id.jpg")
        try {
            if (!copyToFile(uri, source)) return null
            val bitmap = decodeNormalized(source) ?: return null
            try {
                val written = FileOutputStream(output).use { stream ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
                }
                if (!written) {
                    output.delete()
                    return null
                }
            } finally {
                bitmap.recycle()
            }
            return output
        } catch (e: Exception) {
            Log.w(TAG, "Skipping unreadable shared image", e)
        } catch (e: OutOfMemoryError) {
            Log.w(TAG, "Skipping shared image: out of memory", e)
        } finally {
            source.delete()
        }
        output.delete()
        return null
    }

    /** Reads a shared text document (e.g. a .txt or .ics file), capped in size. */
    fun readText(uri: Uri): String? {
        if (!isAllowedSource(uri)) {
            Log.w(TAG, "Ignoring shared document with a disallowed source: ${uri.scheme}://${uri.authority}")
            return null
        }
        return try {
            resolver.openInputStream(uri)?.use { input ->
                InputStreamReader(input, Charsets.UTF_8).use { reader ->
                    val buffer = CharArray(8 * 1024)
                    val text = StringBuilder()
                    while (text.length < MAX_TEXT_CHARS) {
                        val read = reader.read(buffer, 0, min(buffer.size, MAX_TEXT_CHARS - text.length))
                        if (read < 0) break
                        text.append(buffer, 0, read)
                    }
                    text.toString().trim().takeIf { it.isNotEmpty() }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot read shared document", e)
            null
        }
    }

    /**
     * Only `content://` URIs of other apps. `file://` URIs and URIs of this app's
     * own providers could make the app read its private files on behalf of the
     * sender (confused deputy).
     */
    private fun isAllowedSource(uri: Uri): Boolean {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return false
        val authority = uri.authority ?: return false
        val ownPackage = appContext.packageName
        return authority != ownPackage && !authority.startsWith("$ownPackage.")
    }

    private fun copyToFile(uri: Uri, target: File): Boolean {
        val input = resolver.openInputStream(uri) ?: return false
        input.use {
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > MAX_SOURCE_BYTES) throw IOException("Shared image exceeds $MAX_SOURCE_BYTES bytes")
                    output.write(buffer, 0, read)
                }
                return total > 0
            }
        }
    }

    /** Decodes [file] downscaled to ≤ [MAX_EDGE_PX], upright per EXIF, without transparency. */
    private fun decodeNormalized(file: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(max(bounds.outWidth, bounds.outHeight))
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(file.path, options) ?: return null

        val scale = min(1f, MAX_EDGE_PX.toFloat() / max(decoded.width, decoded.height))
        val matrix = Matrix().apply {
            setScale(scale, scale)
            applyExifOrientation(this, readOrientation(file))
        }
        val transformed =
            if (matrix.isIdentity) {
                decoded
            } else {
                Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
            }
        if (transformed !== decoded) decoded.recycle()
        return if (transformed.hasAlpha()) flattenOnWhite(transformed) else transformed
    }

    private fun readOrientation(file: File): Int =
        try {
            ExifInterface(file).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (e: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }

    // Same mapping as Glide's TransformationUtils.initializeMatrixForRotation.
    private fun applyExifOrientation(matrix: Matrix, orientation: Int) {
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.postRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(-90f)
        }
    }

    /** JPEG has no alpha channel: transparent pixels would turn black. */
    private fun flattenOnWhite(bitmap: Bitmap): Bitmap {
        val opaque = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        Canvas(opaque).apply {
            drawColor(Color.WHITE)
            drawBitmap(bitmap, 0f, 0f, null)
        }
        bitmap.recycle()
        return opaque
    }
}
