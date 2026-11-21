import '../../models/extraction.dart';

/// Picks images (gallery / camera) as AI input.
abstract class ImageInputService {
  bool get isCameraSupported;

  /// Returns null when the user cancels.
  ///
  /// Implementations may throw [ImageInputException] when no image can be
  /// obtained (e.g. photo access denied).
  Future<InputImage?> pickFromGallery();

  /// Returns null when the user cancels.
  ///
  /// Implementations may throw [ImageInputException] when no image can be
  /// obtained (e.g. no camera app, camera access denied).
  Future<InputImage?> captureWithCamera();
}

/// Picking or capturing an image failed (not thrown for user cancellation).
class ImageInputException implements Exception {
  const ImageInputException(this.message, {this.cause});

  /// Friendly, user-presentable sentence.
  final String message;

  /// The underlying error, for logs.
  final Object? cause;

  @override
  String toString() => 'ImageInputException: $message (cause: $cause)';
}
