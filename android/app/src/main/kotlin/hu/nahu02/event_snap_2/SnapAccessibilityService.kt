package hu.nahu02.event_snap_2

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Exists only so [SnapCapture] can call `takeScreenshot` (API 30+). It listens
 * to no events and reads no window content (see
 * `res/xml/snap_accessibility_service.xml`): it does nothing until a Snap
 * shortcut asks for a screenshot.
 */
class SnapAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        /** The connected service, or null while it is off. */
        @Volatile
        var instance: SnapAccessibilityService? = null
            private set
    }
}
