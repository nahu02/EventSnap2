import 'package:flutter/services.dart';

/// Service for Android-specific calendar integration
///
/// Provides methods for sharing calendar files (.ics) with calendar applications
/// using Android's native file provider and intent system for better compatibility.
class AndroidCalendarService {
  static const MethodChannel _channel = MethodChannel(
    'hu.nahu02.event_snap_2/calendar',
  );

  /// Share a calendar file with calendar applications
  ///
  /// Takes the [filePath] of a .ics file and attempts to open it with
  /// available calendar applications using Android's file provider system.
  ///
  /// Returns true if the file was successfully shared, false if no compatible
  /// calendar applications were found.
  ///
  /// Throws [PlatformException] if there's an error during the sharing process.
  static Future<bool> shareCalendarFile(String filePath) async {
    try {
      final bool success = await _channel.invokeMethod('shareCalendarFile', {
        'filePath': filePath,
      });
      return success;
    } on PlatformException catch (e) {
      throw Exception('Failed to share calendar file: ${e.message}');
    }
  }

  /// Check if there are calendar applications installed on the device
  ///
  /// Returns true if there are applications that can handle calendar files,
  /// false otherwise. This can be used to provide appropriate user feedback
  /// when no calendar apps are available.
  static Future<bool> hasCalendarApps() async {
    try {
      final bool hasApps = await _channel.invokeMethod('hasCalendarApps');
      return hasApps;
    } on PlatformException catch (_) {
      // If we can't check, assume there might be apps available
      return true;
    }
  }
}
