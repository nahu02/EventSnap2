package hu.nahu02.event_snap_2

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private companion object {
        const val CALENDAR_CHANNEL = "hu.nahu02.event_snap_2/calendar"
        const val FILE_PROVIDER_AUTHORITY = "hu.nahu02.event_snap_2.fileprovider"
        const val CALENDAR_MIME_TYPE = "text/calendar"
    }

    // Created lazily: configureFlutterEngine runs inside super.onCreate.
    private val sharedContent by lazy {
        SharedContentHandler(SharedImageProcessor(applicationContext), SnapContract.directory(applicationContext))
    }
    private val snapChannel by lazy { SnapChannelHandler(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share sheet / "Open with" content → Flutter (see SharedContentHandler).
        sharedContent.attach(flutterEngine.dartExecutor.binaryMessenger)
        // Screen snap helpers (status, accessibility settings, crop).
        snapChannel.attach(flutterEngine.dartExecutor.binaryMessenger)

        // Set up method channel for calendar integration
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareCalendarFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val success = shareCalendarFile(filePath)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("CALENDAR_SHARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    }
                }
                "hasCalendarApps" -> {
                    try {
                        val hasApps = hasCalendarApps()
                        result.success(hasApps)
                    } catch (e: Exception) {
                        result.error("CALENDAR_CHECK_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sharedContent.detach()
        snapChannel.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sharedContent.deleteStaleFilesAsync()
        // A recreated activity (e.g. after process death) must not deliver its
        // launch intent again: it was handled by the previous instance.
        if (savedInstanceState == null) sharedContent.handleInitialIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedContent.handleNewIntent(intent)
    }

    override fun onDestroy() {
        sharedContent.release()
        snapChannel.release()
        super.onDestroy()
    }

    /**
     * Share a calendar file (.ics) with calendar applications
     * Uses FileProvider for secure file sharing on Android 7+
     */
    private fun shareCalendarFile(filePath: String): Boolean {
        try {
            val file = File(filePath)
            if (!file.exists()) {
                throw Exception("Calendar file does not exist: $filePath")
            }

            // Create file provider URI for secure sharing
            val fileUri: Uri = FileProvider.getUriForFile(this, FILE_PROVIDER_AUTHORITY, file)

            // Create intent for viewing calendar files
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, CALENDAR_MIME_TYPE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            // Check if there are apps (other than this one, which also opens .ics
            // files) that can handle calendar files
            if (hasOtherHandler(intent)) {
                startActivity(chooser(intent))
                return true
            } else {
                // Fallback: try with generic file sharing
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = CALENDAR_MIME_TYPE
                    putExtra(Intent.EXTRA_STREAM, fileUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }

                if (hasOtherHandler(shareIntent)) {
                    startActivity(chooser(shareIntent))
                    return true
                }

                return false
            }
        } catch (e: Exception) {
            throw Exception("Failed to share calendar file: ${e.message}")
        }
    }

    /**
     * Check if there are calendar applications installed
     */
    private fun hasCalendarApps(): Boolean {
        return try {
            // Test intent for calendar files (with a content URI: many calendar
            // apps only match intents that carry one)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse("content://$FILE_PROVIDER_AUTHORITY/cache/event.ics"), CALENDAR_MIME_TYPE)
            }
            hasOtherHandler(intent)
        } catch (e: Exception) {
            false
        }
    }

    /** "Add to Calendar" chooser without this app (it handles .ics files too). */
    private fun chooser(target: Intent): Intent =
        Intent.createChooser(target, "Add to Calendar").apply {
            putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(ComponentName(this@MainActivity, MainActivity::class.java)))
        }

    /** Needs the matching `<queries>` entries in the manifest (Android 11+ package visibility). */
    private fun hasOtherHandler(intent: Intent): Boolean =
        queryActivities(intent).any { it.activityInfo?.packageName != packageName }

    private fun queryActivities(intent: Intent): List<ResolveInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
}
