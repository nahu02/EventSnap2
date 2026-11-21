import 'package:flutter/services.dart';

/// Android calendar integration over the `hu.nahu02.event_snap_2/calendar`
/// method channel (implemented in `MainActivity.kt`).
///
/// Opens `.ics` files in calendar apps via `FileProvider` + an intent chooser.
class AndroidCalendarService {
  static const MethodChannel channel = MethodChannel(
    'hu.nahu02.event_snap_2/calendar',
  );

  /// Opens the `.ics` file at [filePath] with a calendar app.
  ///
  /// Returns true if an app was launched, false if no compatible app exists.
  /// Throws [PlatformException] if the native side fails.
  static Future<bool> shareCalendarFile(String filePath) async {
    final bool? success = await channel.invokeMethod<bool>(
      'shareCalendarFile',
      {'filePath': filePath},
    );
    return success ?? false;
  }

  /// Whether any app can handle `text/calendar` files. Assumes true if the
  /// check itself fails.
  static Future<bool> hasCalendarApps() async {
    try {
      final bool? hasApps = await channel.invokeMethod<bool>('hasCalendarApps');
      return hasApps ?? true;
    } on PlatformException catch (_) {
      return true;
    }
  }
}
