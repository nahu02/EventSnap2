import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/services/platform/image_input_service.dart';
import 'package:event_snap_2/services/platform/picker_image_input_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46]);
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, //
]);

Uint8List _ascii(String header) => Uint8List.fromList(header.codeUnits);

/// Records [PickImageFunction] calls and answers with a scripted result.
class FakePicker {
  FakePicker({this.result, this.error});

  XFile? result;
  Object? error;
  final List<
    ({
      ImageSource source,
      double? maxWidth,
      double? maxHeight,
      int? imageQuality,
    })
  >
  calls = [];

  Future<XFile?> call({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) async {
    calls.add((
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    ));
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PickerImageInputService create(FakePicker picker, {bool camera = true}) =>
      PickerImageInputService(
        pickImage: picker.call,
        isCameraSupported: camera,
      );

  group('pickFromGallery', () {
    test('asks for a downscaled, compressed image from the gallery', () async {
      final picker = FakePicker(
        result: XFile.fromData(_jpeg, path: '/cache/image_picker/photo.jpg'),
      );

      final image = await create(picker).pickFromGallery();

      expect(
        image,
        const InputImage(
          path: '/cache/image_picker/photo.jpg',
          mimeType: 'image/jpeg',
        ),
      );
      expect(picker.calls, hasLength(1));
      final call = picker.calls.single;
      expect(call.source, ImageSource.gallery);
      expect(call.maxWidth, 2048);
      expect(call.maxHeight, 2048);
      expect(call.imageQuality, 85);
    });

    test('returns null when the user cancels', () async {
      expect(await create(FakePicker()).pickFromGallery(), isNull);
    });

    test('uses the real content type when the file name lies', () async {
      // The plugin keeps the original name when it re-encodes.
      final picker = FakePicker(
        result: XFile.fromData(_png, path: '/cache/scaled_photo.jpg'),
      );
      expect((await create(picker).pickFromGallery())?.mimeType, 'image/png');
    });

    test('maps plugin errors to ImageInputException', () async {
      final picker = FakePicker(
        error: PlatformException(code: 'photo_access_denied'),
      );
      await expectLater(
        create(picker).pickFromGallery(),
        throwsA(
          isA<ImageInputException>()
              .having((e) => e.message, 'message', contains('Photo access'))
              .having((e) => e.cause, 'cause', isA<PlatformException>()),
        ),
      );
    });

    test('wraps unexpected errors', () async {
      final picker = FakePicker(error: StateError('no delegate'));
      await expectLater(
        create(picker).pickFromGallery(),
        throwsA(
          isA<ImageInputException>().having(
            (e) => e.message,
            'message',
            'Could not open the image.',
          ),
        ),
      );
    });
  });

  group('captureWithCamera', () {
    test('uses the camera source with the same limits', () async {
      final picker = FakePicker(
        result: XFile.fromData(_jpeg, path: '/cache/camera.jpg'),
      );

      final image = await create(picker).captureWithCamera();

      expect(image, const InputImage(path: '/cache/camera.jpg'));
      final call = picker.calls.single;
      expect(call.source, ImageSource.camera);
      expect(call.maxWidth, 2048);
      expect(call.maxHeight, 2048);
      expect(call.imageQuality, 85);
    });

    test('returns null when the user cancels', () async {
      expect(await create(FakePicker()).captureWithCamera(), isNull);
    });

    test('throws without calling the plugin when unsupported', () async {
      final picker = FakePicker();
      await expectLater(
        create(picker, camera: false).captureWithCamera(),
        throwsA(isA<ImageInputException>()),
      );
      expect(picker.calls, isEmpty);
    });

    test('friendly messages for known plugin error codes', () async {
      const expected = {
        'camera_access_denied': 'Camera access',
        'no_available_camera': 'No camera app',
        'already_active': 'already open',
        'something_else': 'Could not take a photo.',
      };
      for (final entry in expected.entries) {
        final picker = FakePicker(error: PlatformException(code: entry.key));
        await expectLater(
          create(picker).captureWithCamera(),
          throwsA(
            isA<ImageInputException>().having(
              (e) => e.message,
              'message',
              contains(entry.value),
            ),
          ),
          reason: entry.key,
        );
      }
    });
  });

  group('isCameraSupported', () {
    test('Android and iOS only, never on the web', () {
      bool supported(TargetPlatform p, {bool web = false}) =>
          PickerImageInputService.cameraSupportedOn(p, isWeb: web);

      expect(supported(TargetPlatform.android), isTrue);
      expect(supported(TargetPlatform.iOS), isTrue);
      expect(supported(TargetPlatform.android, web: true), isFalse);
      expect(supported(TargetPlatform.iOS, web: true), isFalse);
      expect(supported(TargetPlatform.linux), isFalse);
      expect(supported(TargetPlatform.macOS), isFalse);
      expect(supported(TargetPlatform.windows), isFalse);
      expect(supported(TargetPlatform.fuchsia), isFalse);
    });

    test('defaults to the current platform', () {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        expect(PickerImageInputService().isCameraSupported, isTrue);
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        expect(PickerImageInputService().isCameraSupported, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('can be overridden', () {
      expect(create(FakePicker(), camera: false).isCameraSupported, isFalse);
      expect(create(FakePicker()).isCameraSupported, isTrue);
    });
  });

  group('MIME type detection', () {
    test('recognises common image signatures', () {
      String? sniff(List<int> bytes) =>
          PickerImageInputService.mimeTypeFromHeader(bytes);

      expect(sniff(_jpeg), 'image/jpeg');
      expect(sniff(_png), 'image/png');
      expect(sniff(_ascii('GIF89a')), 'image/gif');
      expect(sniff(_ascii('RIFF\x00\x00\x00\x00WEBPVP8 ')), 'image/webp');
      expect(sniff(_ascii('BM\x00\x00')), 'image/bmp');
      expect(sniff(_ascii('\x00\x00\x00\x18ftypheic')), 'image/heic');
      expect(sniff(_ascii('\x00\x00\x00\x18ftypmif1')), 'image/heif');
      expect(sniff(_ascii('\x00\x00\x00\x1cftypavif')), 'image/avif');
      expect(sniff(_ascii('\x00\x00\x00\x18ftypmp42')), isNull);
      expect(sniff(_ascii('RIFF\x00\x00\x00\x00WAVE')), isNull);
      expect(sniff(_ascii('hello world')), isNull);
      expect(sniff(const []), isNull);
      expect(sniff(const [0xFF]), isNull);
    });

    test('maps file extensions', () {
      String? fromPath(String path) =>
          PickerImageInputService.mimeTypeFromPath(path);

      expect(fromPath('/a/b.JPG'), 'image/jpeg');
      expect(fromPath('/a/b.jpeg'), 'image/jpeg');
      expect(fromPath('/a/b.png'), 'image/png');
      expect(fromPath('/a/b.webp'), 'image/webp');
      expect(fromPath('/a/b.heic'), 'image/heic');
      expect(fromPath('/a/b.gif'), 'image/gif');
      expect(fromPath('/a/b.txt'), isNull);
      expect(fromPath('/a/b'), isNull);
      expect(fromPath('/a/b.'), isNull);
    });

    test(
      'falls back to the declared type, then the extension, then JPEG',
      () async {
        Future<String> detect(XFile f) =>
            PickerImageInputService.detectMimeType(f);
        final unknownBytes = _ascii('not an image at all');

        expect(
          await detect(
            XFile.fromData(
              unknownBytes,
              path: '/x.png',
              mimeType: 'image/webp',
            ),
          ),
          'image/webp',
        );
        expect(
          await detect(
            XFile.fromData(
              unknownBytes,
              path: '/x.png',
              mimeType: 'application/octet-stream',
            ),
          ),
          'image/png',
        );
        expect(
          await detect(XFile.fromData(unknownBytes, path: '/x')),
          'image/jpeg',
        );
      },
    );

    test('unreadable files fall back to the extension', () async {
      expect(
        await PickerImageInputService.detectMimeType(
          XFile('/definitely/not/here/picture.webp'),
        ),
        'image/webp',
      );
    });
  });
}
