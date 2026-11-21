import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/extraction.dart';
import 'image_input_service.dart';

/// The part of [ImagePicker] this service uses; a seam for tests.
typedef PickImageFunction = Future<XFile?> Function({
  required ImageSource source,
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
});

/// [ImageInputService] backed by `package:image_picker`.
///
/// Images are downscaled to ≤ [maxDimension] px and re-encoded at
/// [imageQuality] by the plugin. The camera uses the system camera app, so the
/// app needs no camera permission.
class PickerImageInputService implements ImageInputService {
  PickerImageInputService({
    PickImageFunction? pickImage,
    bool? isCameraSupported,
  }) : _pickImage = pickImage ?? ImagePicker().pickImage,
       _isCameraSupported =
           isCameraSupported ??
           cameraSupportedOn(defaultTargetPlatform, isWeb: kIsWeb);

  static const double maxDimension = 2048;
  static const int imageQuality = 85;

  final PickImageFunction _pickImage;
  final bool _isCameraSupported;

  /// The camera is offered on Android and iOS only (not web or desktop).
  @visibleForTesting
  static bool cameraSupportedOn(
    TargetPlatform platform, {
    required bool isWeb,
  }) =>
      !isWeb &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);

  @override
  bool get isCameraSupported => _isCameraSupported;

  @override
  Future<InputImage?> pickFromGallery() => _pick(ImageSource.gallery);

  @override
  Future<InputImage?> captureWithCamera() async {
    if (!_isCameraSupported) {
      throw const ImageInputException(
        'Taking photos is not supported on this device.',
      );
    }
    return _pick(ImageSource.camera);
  }

  Future<InputImage?> _pick(ImageSource source) async {
    final XFile? file;
    try {
      file = await _pickImage(
        source: source,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: imageQuality,
      );
    } on PlatformException catch (e) {
      throw ImageInputException(_messageFor(e.code, source), cause: e);
    } catch (e) {
      throw ImageInputException(_messageFor(null, source), cause: e);
    }
    if (file == null) return null;
    return InputImage(path: file.path, mimeType: await detectMimeType(file));
  }

  static String _messageFor(String? code, ImageSource source) {
    switch (code) {
      case 'camera_access_denied':
        return 'Camera access is turned off. Allow it in the system settings.';
      case 'photo_access_denied':
        return 'Photo access is turned off. Allow it in the system settings.';
      case 'no_available_camera':
        return 'No camera app is available.';
      case 'already_active':
        return 'An image picker is already open.';
    }
    return source == ImageSource.camera
        ? 'Could not take a photo.'
        : 'Could not open the image.';
  }

  /// MIME type from the file's magic bytes, then its declared type, then its
  /// extension; `image/jpeg` as the last resort.
  ///
  /// Sniffing comes first because the plugin keeps the original file name
  /// when it re-encodes (a resized `.png` may contain JPEG data).
  @visibleForTesting
  static Future<String> detectMimeType(XFile file) async {
    try {
      const headerLength = 16;
      final header = <int>[];
      // No end bound: in-memory XFiles throw if it exceeds their length.
      await for (final chunk in file.openRead()) {
        header.addAll(chunk.take(headerLength - header.length));
        if (header.length >= headerLength) break;
      }
      final sniffed = mimeTypeFromHeader(header);
      if (sniffed != null) return sniffed;
    } catch (e) {
      debugPrint('PickerImageInputService: cannot read image header: $e');
    }
    final declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) return declared;
    return mimeTypeFromPath(file.path) ?? 'image/jpeg';
  }

  /// Recognises JPEG, PNG, GIF, WebP, BMP, HEIC/HEIF and AVIF signatures.
  @visibleForTesting
  static String? mimeTypeFromHeader(List<int> b) {
    bool matches(int offset, List<int> signature) {
      if (b.length < offset + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (b[offset + i] != signature[i]) return false;
      }
      return true;
    }

    if (matches(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (matches(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (matches(0, 'GIF8'.codeUnits)) return 'image/gif';
    if (matches(0, 'RIFF'.codeUnits) && matches(8, 'WEBP'.codeUnits)) {
      return 'image/webp';
    }
    if (matches(0, 'BM'.codeUnits)) return 'image/bmp';
    if (matches(4, 'ftyp'.codeUnits) && b.length >= 12) {
      final brand = String.fromCharCodes(b.sublist(8, 12));
      switch (brand) {
        case 'heic' || 'heix' || 'hevc' || 'hevx' || 'heim' || 'heis':
          return 'image/heic';
        case 'mif1' || 'msf1' || 'heif':
          return 'image/heif';
        case 'avif' || 'avis':
          return 'image/avif';
      }
    }
    return null;
  }

  @visibleForTesting
  static String? mimeTypeFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    switch (path.substring(dot + 1).toLowerCase()) {
      case 'jpg' || 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'avif':
        return 'image/avif';
    }
    return null;
  }
}
