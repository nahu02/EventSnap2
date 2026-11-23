package hu.nahu02.event_snap_2

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.io.File

/**
 * Target of both Snap shortcuts (launcher shortcuts and the ones created for
 * apps like SnapKey Map). Translucent, no animation, no recents entry: the
 * screen underneath stays visible while the screenshot is taken, then
 * [MainActivity] is opened with the result and this activity finishes.
 *
 * Exported because shortcut launchers start it from outside the app.
 */
class SnapTrampolineActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var handedOff = false
    private var crop = false

    private val timeout = Runnable { finishWith(null, SnapContract.ERROR_FAILED) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        disableTransitions()
        if (savedInstanceState != null) {
            // Recreated after process death: nothing left to do.
            finish()
            return
        }
        crop = intent?.getBooleanExtra(SnapContract.EXTRA_CROP, false) ?: false
        // Give the window of a launcher shortcut menu / key press a moment to
        // go away so the screenshot shows the app the user was looking at.
        handler.postDelayed({ capture() }, START_DELAY_MS)
        handler.postDelayed(timeout, TIMEOUT_MS)
    }

    private fun capture() {
        // "Snap & crop" keeps full resolution for the crop; a plain snap is
        // downscaled like every other image sent to the AI.
        val maxEdge = if (crop) 0 else SharedImageProcessor.MAX_EDGE_PX
        SnapCapture.capture(this, maxEdge) { file, error ->
            handler.post { finishWith(file, error) }
        }
    }

    private fun finishWith(file: File?, error: String?) {
        if (handedOff) {
            // The timeout already reported a failure: a late file is not wanted.
            file?.delete()
            return
        }
        handedOff = true
        handler.removeCallbacksAndMessages(null)
        val result = Intent(this, MainActivity::class.java).apply {
            action = SnapContract.ACTION_SNAP_RESULT
            putExtra(SnapContract.EXTRA_CROP, crop)
            if (file != null) putExtra(SnapContract.EXTRA_PATH, file.absolutePath)
            if (error != null) putExtra(SnapContract.EXTRA_ERROR, error)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(result)
        finish()
        disableTransitions()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun disableTransitions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            overridePendingTransition(0, 0)
        }
    }

    private companion object {
        const val START_DELAY_MS = 150L
        const val TIMEOUT_MS = 8000L
    }
}
