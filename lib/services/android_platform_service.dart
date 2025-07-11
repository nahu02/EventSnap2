import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service for handling Android platform-specific functionality
/// including shared text intents and method channel communication
class AndroidPlatformService {
  static const MethodChannel _channel = MethodChannel(
    'hu.nahu02.event_snap_2/share',
  );

  /// Gets shared text from Android intent if available
  /// Returns null if no shared text is available
  static Future<String?> getSharedText() async {
    try {
      final String? sharedText = await _channel.invokeMethod('getSharedText');
      return sharedText;
    } on PlatformException catch (e) {
      debugPrint('Error getting shared text: ${e.message}');
      return null;
    }
  }

  /// Clears the shared text from the platform side
  /// This should be called after processing shared text to prevent reprocessing
  static Future<void> clearSharedText() async {
    try {
      await _channel.invokeMethod('clearSharedText');
    } on PlatformException catch (e) {
      debugPrint('Error clearing shared text: ${e.message}');
    }
  }
}
