package com.example.event_snap_2

import android.content.Intent
import android.os.Bundle
import android.net.Uri
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.event_snap_2/share"
    private val CALENDAR_CHANNEL = "com.example.event_snap_2/calendar"
    private var sharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Set up method channel for shared text communication with Flutter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    result.success(sharedText)
                }
                "clearSharedText" -> {
                    sharedText = null
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        when (intent.action) {
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain") {
                    sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                }
            }
        }
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
            val fileUri: Uri = FileProvider.getUriForFile(
                this,
                "com.example.event_snap_2.fileprovider",
                file
            )
            
            // Create intent for viewing calendar files
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(fileUri, "text/calendar")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            
            // Check if there are apps that can handle calendar files
            if (packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                startActivity(Intent.createChooser(intent, "Add to Calendar"))
                return true
            } else {
                // Fallback: try with generic file sharing
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/calendar"
                    putExtra(Intent.EXTRA_STREAM, fileUri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                
                if (packageManager.resolveActivity(shareIntent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                    startActivity(Intent.createChooser(shareIntent, "Add to Calendar"))
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
        try {
            // Test intent for calendar files
            val intent = Intent(Intent.ACTION_VIEW).apply {
                type = "text/calendar"
            }
            
            val activities = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            return activities.isNotEmpty()
        } catch (e: Exception) {
            return false
        }
    }
}
