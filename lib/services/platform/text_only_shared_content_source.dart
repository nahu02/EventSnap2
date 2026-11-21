import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/shared_content.dart';
import '../android_platform_service.dart';
import 'shared_content_source.dart';

/// TEMPORARY text-only [SharedContentSource] over the v2 share method channel
/// (`getSharedText` / `clearSharedText`).
///
/// The v2 `MainActivity` stores the text of `ACTION_SEND` intents (also from
/// `onNewIntent`) but never pushes it to Flutter, so live shares are picked up
/// by polling the channel whenever the app returns to the foreground.
/// Workstream C replaces this with `AndroidSharedContentSource`.
class TextOnlySharedContentSource implements SharedContentSource {
  TextOnlySharedContentSource({
    Future<String?> Function()? readSharedText,
    Future<void> Function()? clearSharedText,
    bool? isSupported,
  }) : _read = readSharedText ?? AndroidPlatformService.getSharedText,
       _clear = clearSharedText ?? AndroidPlatformService.clearSharedText,
       _isSupported =
           isSupported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final Future<String?> Function() _read;
  final Future<void> Function() _clear;
  final bool _isSupported;

  late final StreamController<SharedContent> _controller =
      StreamController<SharedContent>.broadcast(
        onListen: _startListening,
        onCancel: _stopListening,
      );
  AppLifecycleListener? _lifecycleListener;
  Future<SharedContent?> _pending = Future.value();
  bool _initialTaken = false;
  bool _disposed = false;

  @override
  Future<SharedContent?> takeInitialSharedContent() {
    if (_initialTaken || !_isSupported || _disposed) {
      _initialTaken = true;
      return Future.value();
    }
    _initialTaken = true;
    return _fetch();
  }

  @override
  Stream<SharedContent> get sharedContentStream => _controller.stream;

  /// Checks the channel for newly shared text and emits it on
  /// [sharedContentStream]. Called on app resume; public for tests.
  @visibleForTesting
  Future<void> checkForNewContent() async {
    // Leave launch content to takeInitialSharedContent().
    if (!_initialTaken || !_isSupported || _disposed) return;
    final content = await _fetch();
    if (content != null && !_disposed && _controller.hasListener) {
      _controller.add(content);
    }
  }

  /// Serialised read-and-clear so concurrent callers never get the same text.
  Future<SharedContent?> _fetch() {
    final next = _pending.then((_) async {
      try {
        final text = await _read();
        if (text == null || text.trim().isEmpty) return null;
        await _clear();
        return SharedContent(text: text);
      } catch (e) {
        debugPrint(
          'TextOnlySharedContentSource: failed to read shared text: $e',
        );
        return null;
      }
    });
    _pending = next;
    return next;
  }

  void _startListening() {
    if (!_isSupported || _disposed) return;
    _lifecycleListener ??= AppLifecycleListener(
      onResume: () => unawaited(checkForNewContent()),
    );
  }

  void _stopListening() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopListening();
    unawaited(_controller.close());
  }
}
