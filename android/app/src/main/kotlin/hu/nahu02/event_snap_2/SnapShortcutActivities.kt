package hu.nahu02.event_snap_2

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat

/**
 * `ACTION_CREATE_SHORTCUT` entry points: apps that remap hardware keys (e.g.
 * SnapKey Map's "run a supported app shortcut") list activities with this
 * filter and let the user pick one. Each finishes at once with a shortcut that
 * starts [SnapTrampolineActivity].
 *
 * The result is built with [ShortcutManagerCompat.createShortcutResultIntent],
 * which carries both the modern shortcut id and the legacy
 * `EXTRA_SHORTCUT_INTENT` / `EXTRA_SHORTCUT_NAME` / `EXTRA_SHORTCUT_ICON_RESOURCE`
 * extras, so pickers following either contract can read it.
 */
abstract class SnapShortcutActivity(
    private val shortcutId: String,
    private val crop: Boolean,
    private val shortLabelRes: Int,
    private val longLabelRes: Int,
    private val iconRes: Int,
) : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val target = Intent(this, SnapTrampolineActivity::class.java).apply {
            action = SnapContract.ACTION_SNAP
            putExtra(SnapContract.EXTRA_CROP, crop)
        }
        val info = ShortcutInfoCompat.Builder(this, shortcutId)
            .setShortLabel(getString(shortLabelRes))
            .setLongLabel(getString(longLabelRes))
            .setIcon(IconCompat.createWithResource(this, iconRes))
            .setIntent(target)
            .build()
        setResult(RESULT_OK, ShortcutManagerCompat.createShortcutResultIntent(this, info))
        finish()
    }
}

/** "Snap screen". */
class SnapScreenShortcutActivity : SnapShortcutActivity(
    shortcutId = "snap_screen",
    crop = false,
    shortLabelRes = R.string.snap_shortcut_snap_short,
    longLabelRes = R.string.snap_shortcut_snap_long,
    iconRes = R.drawable.ic_snap_screen,
)

/** "Snap & crop". */
class SnapCropShortcutActivity : SnapShortcutActivity(
    shortcutId = "snap_crop",
    crop = true,
    shortLabelRes = R.string.snap_shortcut_crop_short,
    longLabelRes = R.string.snap_shortcut_crop_long,
    iconRes = R.drawable.ic_snap_crop,
)
