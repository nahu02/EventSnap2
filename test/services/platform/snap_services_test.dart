import 'dart:io';

import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/models/shared_content.dart';
import 'package:event_snap_2/services/platform/android_shared_content_source.dart';
import 'package:event_snap_2/services/platform/snap_file_store.dart';
import 'package:event_snap_2/services/platform/snap_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('snap payload parsing', () {
    test('a snap payload carries the snap and crop flags', () {
      final content = AndroidSharedContentSource.parsePayload({
        'text': null,
        'images': [
          {'path': '/cache/snaps/snap_1.jpg', 'mimeType': 'image/jpeg'},
        ],
        'failedImages': 0,
        'source': 'snap',
        'crop': true,
      })!;
      expect(content.isSnap, isTrue);
      expect(content.crop, isTrue);
      expect(content.snapError, isNull);
      expect(content.images.single.isEphemeral, isTrue);
      expect(content.images.single.path, '/cache/snaps/snap_1.jpg');
    });

    test('plain snap: crop defaults to false', () {
      final content = AndroidSharedContentSource.parsePayload({
        'images': [
          {'path': '/cache/snaps/snap_1.jpg'},
        ],
        'source': 'snap',
      })!;
      expect(content.isSnap, isTrue);
      expect(content.crop, isFalse);
    });

    test('shared images are not ephemeral and not snaps', () {
      final content = AndroidSharedContentSource.parsePayload({
        'images': [
          {'path': '/cache/shared_images/a.jpg'},
        ],
        'crop': true, // ignored without source: snap
      })!;
      expect(content.isSnap, isFalse);
      expect(content.crop, isFalse);
      expect(content.images.single.isEphemeral, isFalse);
    });

    test('a snap error without image is delivered', () {
      for (final error in SnapError.values) {
        final content = AndroidSharedContentSource.parsePayload({
          'images': <Object>[],
          'source': 'snap',
          'snapError': error.name,
        })!;
        expect(content.snapError, error);
        expect(content.images, isEmpty);
      }
    });

    test(
      'unknown error code becomes failed; snap without anything is null',
      () {
        expect(
          AndroidSharedContentSource.parsePayload({
            'source': 'snap',
            'snapError': 'weird',
          })!.snapError,
          SnapError.failed,
        );
        expect(
          AndroidSharedContentSource.parsePayload({'source': 'snap'}),
          isNull,
        );
      },
    );

    test('initial snap content flows through the share channel', () async {
      const channel = MethodChannel(AndroidSharedContentSource.channelName);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == AndroidSharedContentSource.getInitialMethod) {
          return {
            'images': [
              {'path': '/cache/snaps/snap_1.jpg', 'mimeType': 'image/jpeg'},
            ],
            'source': 'snap',
            'crop': true,
          };
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final source = AndroidSharedContentSource(isSupported: true);
      addTearDown(source.dispose);
      final content = await source.takeInitialSharedContent();
      expect(content!.isSnap, isTrue);
      expect(content.crop, isTrue);
      expect(content.images.single.isEphemeral, isTrue);
    });
  });

  group('InputImage.isEphemeral', () {
    test('is part of equality and the JSON format', () {
      const normal = InputImage(path: '/a.jpg');
      const ephemeral = InputImage(path: '/a.jpg', isEphemeral: true);
      expect(normal, isNot(ephemeral));
      expect(normal.toJson().containsKey('ephemeral'), isFalse);
      expect(InputImage.fromJson(ephemeral.toJson()), ephemeral);
      expect(InputImage.fromJson(normal.toJson()).isEphemeral, isFalse);
    });
  });

  group('SnapFileStore', () {
    late Directory root;
    late SnapFileStore store;
    late Directory snaps;

    setUp(() {
      root = Directory.systemTemp.createTempSync('snap_store_test_');
      snaps = Directory('${root.path}/snaps')..createSync();
      store = SnapFileStore(baseDirectory: () async => root);
    });
    tearDown(() => root.deleteSync(recursive: true));

    File snapFile(String name, {DateTime? modified}) {
      final file = File('${snaps.path}/$name')..writeAsBytesSync([1]);
      if (modified != null) file.setLastModifiedSync(modified);
      return file;
    }

    test('deletes ephemeral images inside the snaps directory', () async {
      final file = snapFile('a.jpg');
      final deleted = await store.delete([
        InputImage(path: file.path, isEphemeral: true),
      ]);
      expect(deleted, 1);
      expect(file.existsSync(), isFalse);
    });

    test('never deletes gallery / shared images', () async {
      final shared = File('${root.path}/shared.jpg')..writeAsBytesSync([1]);
      final insideButNotMarked = snapFile('b.jpg');
      expect(
        await store.delete([
          InputImage(path: shared.path),
          InputImage(path: insideButNotMarked.path),
        ]),
        0,
      );
      expect(shared.existsSync(), isTrue);
      expect(insideButNotMarked.existsSync(), isTrue);
    });

    test('refuses ephemeral paths outside the snaps directory', () async {
      final outside = File('${root.path}/other.jpg')..writeAsBytesSync([1]);
      final traversal = File('${snaps.path}/../other.jpg').path;
      expect(
        await store.delete([
          InputImage(path: outside.path, isEphemeral: true),
          InputImage(path: traversal, isEphemeral: true),
        ]),
        0,
      );
      expect(outside.existsSync(), isTrue);
    });

    test('missing files are not an error', () async {
      expect(
        await store.delete([
          InputImage(path: '${snaps.path}/gone.jpg', isEphemeral: true),
        ]),
        0,
      );
    });

    test('leftovers: old files go, kept and fresh ones stay', () async {
      final now = DateTime(2026, 11, 23, 12);
      final old = snapFile(
        'old.jpg',
        modified: now.subtract(const Duration(hours: 2)),
      );
      final kept = snapFile(
        'kept.jpg',
        modified: now.subtract(const Duration(hours: 2)),
      );
      final fresh = snapFile(
        'fresh.jpg',
        modified: now.subtract(const Duration(seconds: 3)),
      );

      final deleted = await store.deleteLeftovers(
        keep: [InputImage(path: kept.path, isEphemeral: true)],
        now: now,
      );
      expect(deleted, 1);
      expect(old.existsSync(), isFalse);
      expect(kept.existsSync(), isTrue);
      expect(fresh.existsSync(), isTrue);
    });

    test(
      'leftovers: no snaps directory is fine; other folders untouched',
      () async {
        snaps.deleteSync(recursive: true);
        expect(await store.deleteLeftovers(), 0);
        final other = File('${root.path}/shared_images.jpg')
          ..writeAsBytesSync([1]);
        snaps.createSync();
        await store.deleteLeftovers(minAge: Duration.zero);
        expect(other.existsSync(), isTrue);
      },
    );
  });

  group('AndroidSnapService', () {
    const channel = MethodChannel(AndroidSnapService.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    void mock(Future<Object?> Function(MethodCall) handler) {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    test('status comes from the channel', () async {
      mock((_) async => {'supported': true, 'enabled': false});
      final status = await AndroidSnapService(isSupported: true).getStatus();
      expect(status, const SnapStatus(supported: true, enabled: false));
      expect(status.isReady, isFalse);
    });

    test(
      'status falls back to unsupported on errors and other platforms',
      () async {
        mock((_) async => throw PlatformException(code: 'x'));
        expect(
          await AndroidSnapService(isSupported: true).getStatus(),
          SnapStatus.unsupported,
        );
        expect(
          await AndroidSnapService(isSupported: false).getStatus(),
          SnapStatus.unsupported,
        );
      },
    );

    test('opens the accessibility settings', () async {
      mock((_) async => true);
      expect(
        await AndroidSnapService(isSupported: true).openAccessibilitySettings(),
        isTrue,
      );
      expect(calls.single.method, 'openAccessibilitySettings');
    });

    test('crop sends fractions and returns an ephemeral image', () async {
      mock(
        (_) async => {
          'path': '/cache/snaps/crop_1.jpg',
          'mimeType': 'image/jpeg',
        },
      );
      final cropped = await AndroidSnapService(isSupported: true).cropImage(
        const InputImage(path: '/cache/snaps/snap_1.jpg', isEphemeral: true),
        const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
      );
      expect(cropped.isEphemeral, isTrue);
      expect(cropped.path, '/cache/snaps/crop_1.jpg');
      expect(calls.single.arguments, {
        'path': '/cache/snaps/snap_1.jpg',
        'left': 0.1,
        'top': 0.2,
        'right': 0.9,
        'bottom': 0.8,
      });
    });

    test('crop failures become SnapException', () async {
      mock((_) async => throw PlatformException(code: 'CROP_FAILED'));
      await expectLater(
        AndroidSnapService(isSupported: true).cropImage(
          const InputImage(path: '/a.jpg'),
          const Rect.fromLTRB(0, 0, 1, 1),
        ),
        throwsA(isA<SnapException>()),
      );
    });
  });
}
