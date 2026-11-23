import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/extraction.dart';

/// State of the screen-snap capability (Android accessibility service).
class SnapStatus {
  const SnapStatus({required this.supported, required this.enabled});

  /// Android 11+ (API 30), the first with a screenshot API for accessibility
  /// services. False on older Android and on other platforms.
  final bool supported;

  /// The EventSnap accessibility service is switched on in system settings.
  final bool enabled;

  /// Not available (web, iOS, desktop, old Android).
  static const unsupported = SnapStatus(supported: false, enabled: false);

  bool get isReady => supported && enabled;

  @override
  bool operator ==(Object other) =>
      other is SnapStatus &&
      other.supported == supported &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(supported, enabled);
}

/// Cropping the screenshot failed.
class SnapException implements Exception {
  const SnapException(this.message, {this.cause});

  /// Friendly, user-presentable sentence.
  final String message;
  final Object? cause;

  @override
  String toString() => 'SnapException: $message (cause: $cause)';
}

/// Native helpers for the "Snap screen" feature. Capturing itself happens
/// natively (shortcut → trampoline activity → accessibility service) and
/// reaches Dart as snap [SharedContent]; this service covers the rest.
abstract class SnapService {
  /// Whether snaps are supported and the accessibility service is enabled.
  Future<SnapStatus> getStatus();

  /// Opens the system accessibility settings. Returns false if that failed.
  Future<bool> openAccessibilitySettings();

  /// Crops [source] to [region] (fractions of the image, `0..1`), writes the
  /// result as JPEG (≤ 2048 px) next to it in `cacheDir/snaps/` and returns it
  /// as an ephemeral image. The source file is left alone (the caller deletes
  /// it). Throws [SnapException].
  Future<InputImage> cropImage(InputImage source, Rect region);
}

/// [SnapService] backed by `SnapChannelHandler.kt`.
///
/// Channel `hu.nahu02.event_snap_2/snap`:
/// - `getStatus` → `{supported: bool, enabled: bool}`
/// - `openAccessibilitySettings` → bool
/// - `cropImage {path, left, top, right, bottom}` → `{path, mimeType}`
class AndroidSnapService implements SnapService {
  AndroidSnapService({MethodChannel? channel, bool? isSupported})
    : _channel = channel ?? const MethodChannel(channelName),
      _isSupported =
          isSupported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const String channelName = 'hu.nahu02.event_snap_2/snap';

  final MethodChannel _channel;
  final bool _isSupported;

  @override
  Future<SnapStatus> getStatus() async {
    if (!_isSupported) return SnapStatus.unsupported;
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getStatus',
      );
      return SnapStatus(
        supported: result?['supported'] == true,
        enabled: result?['enabled'] == true,
      );
    } catch (e) {
      debugPrint('AndroidSnapService: cannot read status: $e');
      return SnapStatus.unsupported;
    }
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    if (!_isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('openAccessibilitySettings') ??
          false;
    } catch (e) {
      debugPrint('AndroidSnapService: cannot open settings: $e');
      return false;
    }
  }

  @override
  Future<InputImage> cropImage(InputImage source, Rect region) async {
    if (!_isSupported) {
      throw const SnapException("Cropping isn't available on this device");
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'cropImage',
        {
          'path': source.path,
          'left': region.left,
          'top': region.top,
          'right': region.right,
          'bottom': region.bottom,
        },
      );
      final path = result?['path'];
      if (path is! String || path.isEmpty) {
        throw const SnapException("Couldn't crop the screenshot");
      }
      return InputImage(
        path: path,
        mimeType: (result?['mimeType'] as String?) ?? 'image/jpeg',
        isEphemeral: true,
      );
    } on SnapException {
      rethrow;
    } catch (e) {
      throw SnapException("Couldn't crop the screenshot", cause: e);
    }
  }
}
