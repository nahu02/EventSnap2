import '../../models/shared_content.dart';

/// Content shared into the app from other apps (Android share sheet).
abstract class SharedContentSource {
  /// Content that launched the app (consumed once; later calls return null).
  Future<SharedContent?> takeInitialSharedContent();

  /// Content shared while the app is running.
  Stream<SharedContent> get sharedContentStream;

  void dispose();
}
