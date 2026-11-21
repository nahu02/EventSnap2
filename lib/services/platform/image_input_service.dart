import '../../models/extraction.dart';

/// Picks images (gallery / camera) as AI input.
abstract class ImageInputService {
  bool get isCameraSupported;

  /// Returns null when the user cancels.
  Future<InputImage?> pickFromGallery();

  /// Returns null when the user cancels.
  Future<InputImage?> captureWithCamera();
}
