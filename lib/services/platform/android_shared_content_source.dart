import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/extraction.dart';
import '../../models/shared_content.dart';
import 'shared_content_source.dart';

/// [SharedContentSource] for the Android share sheet (text and up to four
/// images) and "Open with" for `.ics` files, implemented natively by
/// `SharedContentHandler.kt`.
///
/// Protocol on the [channelName] method channel:
/// - Dart → native [getInitialMethod]: the payload of the intent that launched
///   the app, or null. Answered once; native waits until the images are
///   processed before replying.
/// - Dart → native [readyMethod]: sent once, after its handler is installed
///   and [takeInitialSharedContent] has completed (so a newer live share can
///   never be overtaken by the older initial payload). If nobody calls take
///   within [readyFallbackDelay] of the first stream listener, ready is sent
///   anyway. Native queues live shares until then, so nothing is lost on
///   cold start.
/// - native → Dart [onSharedContentMethod]: content shared while the app is
///   running (`onNewIntent`).
///
/// Payload: `{text: String?, images: [{path: String, mimeType: String}],
/// failedImages: int?}`;
/// image files are JPEGs (≤ 2048 px) in the app's cache, kept for 24 hours.
///
/// On other platforms (web, iOS, desktop) this is a no-op: no initial content
/// and an empty stream.
class AndroidSharedContentSource implements SharedContentSource {
  AndroidSharedContentSource({
    MethodChannel? channel,
    bool? isSupported,
    this.readyFallbackDelay = const Duration(seconds: 2),
  }) : _channel = channel ?? const MethodChannel(channelName),
       _isSupported =
           isSupported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const String channelName = 'hu.nahu02.event_snap_2/share';
  static const String getInitialMethod = 'getInitialSharedContent';
  static const String readyMethod = 'ready';
  static const String onSharedContentMethod = 'onSharedContent';

  /// Live shares kept while nobody listens to [sharedContentStream].
  static const int maxBufferedContent = 8;

  /// How long after the first stream listener `ready` waits for
  /// [takeInitialSharedContent] before being sent anyway.
  final Duration readyFallbackDelay;

  final MethodChannel _channel;
  final bool _isSupported;

  late final StreamController<SharedContent> _controller =
      StreamController<SharedContent>.broadcast(onListen: _onListen);
  final List<SharedContent> _buffer = [];
  bool _activated = false;
  bool _readySent = false;
  Timer? _readyTimer;
  bool _initialTaken = false;
  bool _disposed = false;

  @override
  Future<SharedContent?> takeInitialSharedContent() async {
    if (_initialTaken || !_isSupported || _disposed) {
      _initialTaken = true;
      return null;
    }
    _initialTaken = true;
    try {
      final payload = await _channel.invokeMethod<Object?>(getInitialMethod);
      if (_disposed) return null;
      return parsePayload(payload);
    } catch (e) {
      debugPrint('AndroidSharedContentSource: cannot read initial content: $e');
      return null;
    } finally {
      // After the initial content, so shares queued natively meanwhile (newer)
      // arrive after it.
      _install();
      _sendReadyOnce();
    }
  }

  @override
  Stream<SharedContent> get sharedContentStream => _controller.stream;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _readyTimer?.cancel();
    if (_activated) _channel.setMethodCallHandler(null);
    _buffer.clear();
    unawaited(_controller.close());
  }

  /// Installs the handler for native pushes.
  void _install() {
    if (_activated || !_isSupported || _disposed) return;
    _activated = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Tells native it may push (once).
  void _sendReadyOnce() {
    _readyTimer?.cancel();
    if (_readySent || !_activated || _disposed) return;
    _readySent = true;
    unawaited(_sendReady());
  }

  Future<void> _sendReady() async {
    try {
      await _channel.invokeMethod<void>(readyMethod);
    } catch (e) {
      debugPrint('AndroidSharedContentSource: ready handshake failed: $e');
    }
  }

  void _onListen() {
    _install();
    // take (if called) sends ready when done; otherwise fall back to a timer.
    if (_activated && !_readySent && !_initialTaken && _readyTimer == null) {
      _readyTimer = Timer(readyFallbackDelay, _sendReadyOnce);
    }
    if (_buffer.isEmpty) return;
    final pending = List.of(_buffer);
    _buffer.clear();
    pending.forEach(_controller.add);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case onSharedContentMethod:
        final content = parsePayload(call.arguments);
        if (content != null) _deliver(content);
        return null;
      default:
        throw MissingPluginException(
          'AndroidSharedContentSource: unknown method ${call.method}',
        );
    }
  }

  void _deliver(SharedContent content) {
    if (_disposed) return;
    if (_controller.hasListener) {
      _controller.add(content);
      return;
    }
    if (_buffer.length >= maxBufferedContent) _buffer.removeAt(0);
    _buffer.add(content);
  }

  /// Parses a channel payload; returns null for empty or malformed payloads
  /// (malformed parts are skipped and logged with [debugPrint]).
  @visibleForTesting
  static SharedContent? parsePayload(Object? payload) {
    if (payload == null) return null;
    if (payload is! Map) {
      debugPrint(
        'AndroidSharedContentSource: ignoring malformed payload '
        '(${payload.runtimeType})',
      );
      return null;
    }

    String? text;
    final rawText = payload['text'];
    if (rawText is String) {
      final trimmed = rawText.trim();
      text = trimmed.isEmpty ? null : trimmed;
    } else if (rawText != null) {
      debugPrint(
        'AndroidSharedContentSource: ignoring non-text "text" '
        '(${rawText.runtimeType})',
      );
    }

    final images = <InputImage>[];
    final rawImages = payload['images'];
    if (rawImages is List) {
      for (final rawImage in rawImages) {
        final image = _parseImage(rawImage);
        if (image != null) {
          images.add(image);
        } else {
          debugPrint(
            'AndroidSharedContentSource: ignoring malformed image entry '
            '($rawImage)',
          );
        }
      }
    } else if (rawImages != null) {
      debugPrint(
        'AndroidSharedContentSource: ignoring non-list "images" '
        '(${rawImages.runtimeType})',
      );
    }

    final rawFailed = payload['failedImages'];
    final failed = rawFailed is int && rawFailed > 0 ? rawFailed : 0;

    final content = SharedContent(
      text: text,
      images: List.unmodifiable(images),
      failedImageCount: failed,
    );
    return content.isEmpty && failed == 0 ? null : content;
  }

  static InputImage? _parseImage(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.trim().isEmpty) return null;
    final mimeType = raw['mimeType'];
    return InputImage(
      path: path,
      mimeType: mimeType is String && mimeType.startsWith('image/')
          ? mimeType
          : 'image/jpeg',
    );
  }
}
