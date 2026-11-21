import 'dart:async';

import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/models/shared_content.dart';
import 'package:event_snap_2/services/platform/android_shared_content_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel(AndroidSharedContentSource.channelName);

/// Mimics `SharedContentHandler.kt`: serves the launch payload once, queues
/// live shares until Dart sends `ready`, then pushes them via
/// `onSharedContent`.
class FakeNativeShareSide {
  FakeNativeShareSide() {
    _messenger.setMockMethodCallHandler(_channel, _handle);
  }

  final TestDefaultBinaryMessenger _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final List<MethodCall> calls = [];
  Object? initialPayload;
  bool _initialConsumed = false;
  bool ready = false;
  final List<Object?> _queue = [];

  /// Replies of Dart to pushes: true = handled, false = no Dart handler.
  final List<bool> pushReplies = [];

  /// Makes `getInitialSharedContent` fail with this error.
  Object? initialError;

  int count(String method) => calls.where((c) => c.method == method).length;

  List<String> get methods => calls.map((c) => c.method).toList();

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case AndroidSharedContentSource.getInitialMethod:
        if (initialError != null) throw initialError!;
        if (_initialConsumed) return null;
        _initialConsumed = true;
        return initialPayload;
      case AndroidSharedContentSource.readyMethod:
        ready = true;
        final pending = List.of(_queue);
        _queue.clear();
        // Like the native side: reply first, then flush the queue.
        scheduleMicrotask(() async {
          for (final payload in pending) {
            await push(payload);
          }
        });
        return null;
    }
    throw MissingPluginException();
  }

  /// A share delivered through `onNewIntent`.
  Future<void> share(Object? payload) async {
    if (ready) {
      await push(payload);
    } else {
      _queue.add(payload);
    }
  }

  /// Sends `onSharedContent` to Dart regardless of the handshake.
  Future<bool> push(
    Object? payload, {
    String method = AndroidSharedContentSource.onSharedContentMethod,
  }) async {
    final reply = Completer<ByteData?>();
    await _messenger.handlePlatformMessage(
      _channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, payload)),
      reply.complete,
    );
    final handled = await reply.future != null;
    pushReplies.add(handled);
    return handled;
  }

  void dispose() => _messenger.setMockMethodCallHandler(_channel, null);
}

Map<String, Object?> _payload({
  String? text,
  List<Map<String, Object?>> images = const [],
}) => {'text': text, 'images': images};

Map<String, Object?> _image(String path, [String? mimeType = 'image/jpeg']) => {
  'path': path,
  'mimeType': mimeType,
};

/// Lets queued microtasks and platform message futures run.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeShareSide native;
  late AndroidSharedContentSource source;

  setUp(() {
    native = FakeNativeShareSide();
    source = AndroidSharedContentSource(isSupported: true);
  });

  tearDown(() {
    source.dispose();
    native.dispose();
  });

  group('initial content', () {
    test('is returned once, then null', () async {
      native.initialPayload = _payload(
        text: 'Party on Friday at 8',
        images: [_image('/cache/shared_images/a.jpg')],
      );

      expect(
        await source.takeInitialSharedContent(),
        const SharedContent(
          text: 'Party on Friday at 8',
          images: [InputImage(path: '/cache/shared_images/a.jpg')],
        ),
      );
      expect(await source.takeInitialSharedContent(), isNull);
      expect(native.count(AndroidSharedContentSource.getInitialMethod), 1);
    });

    test('text only', () async {
      native.initialPayload = _payload(text: '  Dinner tomorrow at 7\n');
      expect(
        await source.takeInitialSharedContent(),
        const SharedContent(text: 'Dinner tomorrow at 7'),
      );
    });

    test('images only, keeping order and MIME types', () async {
      native.initialPayload = {
        'text': null,
        'images': [_image('/c/1.jpg'), _image('/c/2.png', 'image/png')],
      };
      final content = await source.takeInitialSharedContent();
      expect(content?.text, isNull);
      expect(content?.images, const [
        InputImage(path: '/c/1.jpg'),
        InputImage(path: '/c/2.png', mimeType: 'image/png'),
      ]);
    });

    test('null when the app was not launched by a share', () async {
      expect(await source.takeInitialSharedContent(), isNull);
    });

    test('channel errors yield null', () async {
      native.initialError = PlatformException(code: 'boom');
      expect(await source.takeInitialSharedContent(), isNull);
    });

    test('missing native implementation yields null', () async {
      native.dispose(); // no handler at all → MissingPluginException
      expect(await source.takeInitialSharedContent(), isNull);
    });
  });

  group('ready handshake', () {
    test('the source does not claim the channel before it is used', () async {
      expect(await native.push(_payload(text: 'too early')), isFalse);
      expect(native.calls, isEmpty);
    });

    test('listening installs the handler and sends ready once', () async {
      final sub1 = source.sharedContentStream.listen((_) {});
      final sub2 = source.sharedContentStream.listen((_) {});
      await source.takeInitialSharedContent();
      await _settle();

      expect(native.count(AndroidSharedContentSource.readyMethod), 1);
      await sub1.cancel();
      await sub2.cancel();
    });

    test('takeInitialSharedContent alone sends ready after reading the '
        'initial content', () async {
      native.initialPayload = _payload(text: 'launch');
      await source.takeInitialSharedContent();
      await _settle();

      expect(native.methods, [
        AndroidSharedContentSource.getInitialMethod,
        AndroidSharedContentSource.readyMethod,
      ]);
    });

    test('shares that arrive before ready are delivered after it '
        '(cold start)', () async {
      native.initialPayload = _payload(text: 'launch share');
      await native.share(_payload(text: 'second share'));
      expect(native.ready, isFalse);

      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);
      await _settle();

      expect(native.ready, isTrue);
      expect(received, [const SharedContent(text: 'second share')]);
      expect(
        await source.takeInitialSharedContent(),
        const SharedContent(text: 'launch share'),
      );
      await sub.cancel();
    });
  });

  group('live content', () {
    test('onSharedContent events are emitted on the stream', () async {
      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);
      await _settle();

      await native.share(_payload(text: 'Lunch at noon'));
      await native.share(_payload(images: [_image('/c/flyer.jpg')]));
      await _settle();

      expect(received, const [
        SharedContent(text: 'Lunch at noon'),
        SharedContent(images: [InputImage(path: '/c/flyer.jpg')]),
      ]);
      expect(native.pushReplies, [true, true]);
      await sub.cancel();
    });

    test('content arriving without listeners is buffered until the next '
        'listener', () async {
      await source.takeInitialSharedContent(); // activates, no listener
      await _settle();
      await native.share(_payload(text: 'while nobody listens'));

      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);
      await _settle();

      expect(received, [const SharedContent(text: 'while nobody listens')]);
      await sub.cancel();
    });

    test('the buffer keeps only the newest entries', () async {
      await source.takeInitialSharedContent();
      await _settle();
      const extra = 3;
      for (
        var i = 0;
        i < AndroidSharedContentSource.maxBufferedContent + extra;
        i++
      ) {
        await native.share(_payload(text: 'share $i'));
      }

      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);
      await _settle();

      expect(
        received,
        hasLength(AndroidSharedContentSource.maxBufferedContent),
      );
      expect(received.first.text, 'share $extra');
      await sub.cancel();
    });

    test('malformed and empty live payloads are ignored', () async {
      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);
      await _settle();

      await native.share('not a map');
      await native.share(_payload(text: '   '));
      await native.share({'images': 'nope'});
      await native.share(_payload(text: 'valid'));
      await _settle();

      expect(received, [const SharedContent(text: 'valid')]);
      // Dart still acknowledges them, so native does not re-queue.
      expect(native.pushReplies, everyElement(isTrue));
      await sub.cancel();
    });

    test('unknown native methods are rejected', () async {
      final sub = source.sharedContentStream.listen((_) {});
      await _settle();
      expect(await native.push(null, method: 'somethingElse'), isFalse);
      await sub.cancel();
    });
  });

  group('parsePayload', () {
    SharedContent? parse(Object? payload) =>
        AndroidSharedContentSource.parsePayload(payload);

    test('rejects non-map payloads', () {
      expect(parse(null), isNull);
      expect(parse('text'), isNull);
      expect(parse(42), isNull);
      expect(parse([_image('/a.jpg')]), isNull);
    });

    test('empty content is null', () {
      expect(parse(<String, Object?>{}), isNull);
      expect(parse(_payload(text: ' \n ')), isNull);
      expect(
        parse(
          _payload(
            images: [
              {'path': ''},
            ],
          ),
        ),
        isNull,
      );
    });

    test('skips malformed image entries but keeps the rest', () {
      expect(
        parse({
          'text': 'Concert',
          'images': [
            'not a map',
            {'mimeType': 'image/jpeg'},
            {'path': 42},
            {'path': '   '},
            _image('/ok.jpg'),
          ],
        }),
        const SharedContent(
          text: 'Concert',
          images: [InputImage(path: '/ok.jpg')],
        ),
      );
    });

    test('defaults missing or non-image MIME types to image/jpeg', () {
      expect(
        parse({
          'images': [
            {'path': '/a'},
            {'path': '/b', 'mimeType': 7},
            {'path': '/c', 'mimeType': 'text/plain'},
            {'path': '/d', 'mimeType': 'image/webp'},
          ],
        })?.images,
        const [
          InputImage(path: '/a'),
          InputImage(path: '/b'),
          InputImage(path: '/c'),
          InputImage(path: '/d', mimeType: 'image/webp'),
        ],
      );
    });

    test('ignores wrongly typed fields', () {
      expect(
        parse({
          'text': 12,
          'images': [_image('/a.jpg')],
        }),
        const SharedContent(images: [InputImage(path: '/a.jpg')]),
      );
      expect(
        parse({'text': 'hi', 'images': 'x'}),
        const SharedContent(text: 'hi'),
      );
    });

    test('parsed image lists are unmodifiable', () {
      final content = parse(_payload(images: [_image('/a.jpg')]))!;
      expect(
        () => content.images.add(const InputImage(path: '/b.jpg')),
        throwsUnsupportedError,
      );
    });
  });

  group('lifecycle', () {
    test('unsupported platforms never touch the channel', () async {
      final noop = AndroidSharedContentSource(isSupported: false);
      native.initialPayload = _payload(text: 'x');
      final received = <SharedContent>[];
      final sub = noop.sharedContentStream.listen(received.add);

      expect(await noop.takeInitialSharedContent(), isNull);
      await _settle();
      expect(native.calls, isEmpty);
      expect(await native.push(_payload(text: 'y')), isFalse);
      expect(received, isEmpty);

      await sub.cancel();
      noop.dispose();
    });

    test('dispose closes the stream and releases the channel', () async {
      final done = Completer<void>();
      source.sharedContentStream.listen(null, onDone: done.complete);
      await _settle();

      source.dispose();
      await done.future.timeout(const Duration(seconds: 1));
      expect(await native.push(_payload(text: 'late')), isFalse);
      expect(await source.takeInitialSharedContent(), isNull);
      source.dispose(); // idempotent
    });
  });
}
