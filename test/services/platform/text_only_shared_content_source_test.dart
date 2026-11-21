import 'dart:async';

import 'package:event_snap_2/models/shared_content.dart';
import 'package:event_snap_2/services/platform/text_only_shared_content_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextOnlySharedContentSource', () {
    late String? platformText;
    late int clearCalls;

    TextOnlySharedContentSource create({bool supported = true}) {
      return TextOnlySharedContentSource(
        isSupported: supported,
        readSharedText: () async => platformText,
        clearSharedText: () async {
          clearCalls++;
          platformText = null;
        },
      );
    }

    setUp(() {
      platformText = null;
      clearCalls = 0;
    });

    test(
      'initial content is returned once and cleared on the platform',
      () async {
        platformText = 'Party on Friday at 8';
        final source = create();
        expect(
          await source.takeInitialSharedContent(),
          const SharedContent(text: 'Party on Friday at 8'),
        );
        expect(clearCalls, 1);
        expect(await source.takeInitialSharedContent(), isNull);
        source.dispose();
      },
    );

    test('blank text is ignored', () async {
      platformText = '   ';
      final source = create();
      expect(await source.takeInitialSharedContent(), isNull);
      expect(clearCalls, 0);
      source.dispose();
    });

    test('unsupported platforms never touch the channel', () async {
      platformText = 'x';
      final source = create(supported: false);
      expect(await source.takeInitialSharedContent(), isNull);
      await source.checkForNewContent();
      expect(platformText, 'x');
      source.dispose();
    });

    test('content shared while running is emitted on the stream', () async {
      final source = create();
      await source.takeInitialSharedContent();
      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);

      platformText = 'Dinner tomorrow at 7';
      await source.checkForNewContent();
      await source.checkForNewContent(); // already consumed
      await Future<void>.delayed(Duration.zero);

      expect(received, [const SharedContent(text: 'Dinner tomorrow at 7')]);
      await sub.cancel();
      source.dispose();
    });

    test('launch content is left for takeInitialSharedContent', () async {
      platformText = 'Launch share';
      final source = create();
      final received = <SharedContent>[];
      final sub = source.sharedContentStream.listen(received.add);
      await source.checkForNewContent();
      expect(received, isEmpty);
      expect(
        await source.takeInitialSharedContent(),
        const SharedContent(text: 'Launch share'),
      );
      await sub.cancel();
      source.dispose();
    });

    test('channel errors are swallowed', () async {
      final source = TextOnlySharedContentSource(
        isSupported: true,
        readSharedText: () async => throw Exception('channel down'),
        clearSharedText: () async {},
      );
      expect(await source.takeInitialSharedContent(), isNull);
      source.dispose();
    });

    test('dispose closes the stream', () async {
      final source = create();
      final done = Completer<void>();
      source.sharedContentStream.listen(null, onDone: done.complete);
      source.dispose();
      await done.future.timeout(const Duration(seconds: 1));
    });
  });
}
