import '../../models/extraction.dart';
import 'image_input_service.dart';

/// TEMPORARY stub [ImageInputService]: image input is not available yet.
/// Workstream C replaces it with an `image_picker` based implementation.
class UnsupportedImageInputService implements ImageInputService {
  const UnsupportedImageInputService();

  @override
  bool get isCameraSupported => false;

  @override
  Future<InputImage?> pickFromGallery() async => null;

  @override
  Future<InputImage?> captureWithCamera() async => null;
}
