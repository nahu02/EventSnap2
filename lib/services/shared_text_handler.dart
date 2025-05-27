import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'android_platform_service.dart';
import '../navigation/app_router.dart';

/// Service for handling shared text from Android intents
///
/// Manages the coordination between Android shared text and Flutter app navigation.
/// Handles both app launch scenarios: direct launch vs shared text launch.
class SharedTextHandler {
  static SharedTextHandler? _instance;
  String? _pendingSharedText;

  // Private constructor for singleton
  SharedTextHandler._();

  /// Get singleton instance
  static SharedTextHandler get instance {
    _instance ??= SharedTextHandler._();
    return _instance!;
  }

  /// Check if app was launched with shared text and store it
  ///
  /// This should be called during app initialization to check if there's
  /// shared text available and store it for later processing.
  Future<void> _checkForSharedText() async {
    try {
      final sharedText = await AndroidPlatformService.getSharedText();

      if (sharedText != null && sharedText.trim().isNotEmpty) {
        _pendingSharedText = sharedText;
        // Clear the shared text from platform to prevent reprocessing
        await AndroidPlatformService.clearSharedText();
      }
    } on PlatformException catch (e) {
      debugPrint('Error checking shared text: ${e.message}');
    }
  }

  /// Get and consume pending shared text
  ///
  /// Returns the shared text if available and clears it from memory.
  /// This should be called by screens that want to handle shared text.
  String? consumePendingSharedText() {
    final text = _pendingSharedText;
    _pendingSharedText = null;
    return text;
  }

  /// Check if there's pending shared text
  bool hasPendingSharedText() {
    return _pendingSharedText != null;
  }

  /// Handle shared text by navigating to appropriate screen
  ///
  /// If shared text is available, navigates to EventTextInputScreen
  /// with the shared text pre-filled.
  Future<void> checkAndHandleSharedTextNavigation(BuildContext context) async {
    await _checkForSharedText();

    final sharedText = consumePendingSharedText();

    if (sharedText != null) {
      // Use post frame callback to ensure navigation happens after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppRouter.navigateToEventTextInput(context, initialText: sharedText);
      });
    }
  }
}
