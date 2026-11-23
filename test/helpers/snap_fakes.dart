/// Fakes for the screen-snap services.
library;

import 'dart:io';
import 'dart:ui' show Rect;

import 'package:event_snap_2/models/extraction.dart';
import 'package:event_snap_2/services/platform/snap_file_store.dart';
import 'package:event_snap_2/services/platform/snap_service.dart';

/// [SnapService] with a scriptable status and crop result.
class FakeSnapService implements SnapService {
  FakeSnapService({
    this.status = const SnapStatus(supported: true, enabled: true),
  });

  SnapStatus status;
  int openSettingsCalls = 0;
  final List<({InputImage source, Rect region})> crops = [];

  /// When set, [cropImage] throws it.
  SnapException? cropFailure;

  @override
  Future<SnapStatus> getStatus() async => status;

  @override
  Future<bool> openAccessibilitySettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<InputImage> cropImage(InputImage source, Rect region) async {
    final failure = cropFailure;
    if (failure != null) throw failure;
    crops.add((source: source, region: region));
    return InputImage(
      path: '/cache/snaps/crop_${crops.length}.jpg',
      isEphemeral: true,
    );
  }
}

/// Records deletions instead of touching the file system (widget tests run in
/// fake async, where real file I/O never completes).
class RecordingSnapFileStore extends SnapFileStore {
  RecordingSnapFileStore()
    : super(baseDirectory: () async => Directory.systemTemp);

  /// Images passed to [delete] that were ephemeral, in order.
  final List<InputImage> deleted = [];

  /// `keep` arguments of [deleteLeftovers] calls.
  final List<List<InputImage>> leftoverKeeps = [];

  @override
  Future<int> delete(Iterable<InputImage> images) async {
    final doomed = images.where((i) => i.isEphemeral).toList();
    deleted.addAll(doomed);
    return doomed.length;
  }

  @override
  Future<int> deleteLeftovers({
    Iterable<InputImage> keep = const [],
    Duration minAge = const Duration(seconds: 20),
    DateTime? now,
  }) async {
    leftoverKeeps.add(keep.toList());
    return 0;
  }
}
