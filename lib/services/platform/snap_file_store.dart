import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/extraction.dart';

/// Owns the deletion policy for screen snaps (docs/v3_plan.md §9).
///
/// Snaps are app-private JPEGs in `<cacheDir>/snaps/` (never the gallery /
/// MediaStore). They are marked with [InputImage.isEphemeral]; only such
/// images — and only files really inside the snaps directory — are ever
/// deleted here, so gallery and shared images are safe.
class SnapFileStore {
  /// [baseDirectory] resolves the cache directory (default: the platform
  /// temporary directory, which is `cacheDir` on Android); tests pass a
  /// temp dir.
  SnapFileStore({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getTemporaryDirectory;

  /// Name of the snaps folder inside the cache directory (must match
  /// `SnapStore.DIRECTORY_NAME` in Kotlin).
  static const String directoryName = 'snaps';

  final Future<Directory> Function() _baseDirectory;

  Future<Directory> get directory async =>
      Directory(p.join((await _baseDirectory()).path, directoryName));

  /// Deletes the files of the ephemeral [images]; returns how many were
  /// removed. Non-ephemeral images, files outside the snaps directory and
  /// missing files are skipped. Never throws.
  Future<int> delete(Iterable<InputImage> images) async {
    var deleted = 0;
    try {
      final root = p.canonicalize((await directory).path);
      for (final image in images) {
        if (!image.isEphemeral) continue;
        final path = p.canonicalize(image.path);
        if (!p.isWithin(root, path)) {
          debugPrint('SnapFileStore: refusing to delete outside snaps: $path');
          continue;
        }
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            deleted++;
          }
        } catch (e) {
          debugPrint('SnapFileStore: could not delete $path: $e');
        }
      }
    } catch (e) {
      debugPrint('SnapFileStore: delete failed: $e');
    }
    return deleted;
  }

  /// Deletes leftovers of earlier sessions (app start). Files in [keep] and
  /// files younger than [minAge] (a snap that arrived while this runs) are
  /// spared. Returns how many were removed. Never throws.
  Future<int> deleteLeftovers({
    Iterable<InputImage> keep = const [],
    Duration minAge = const Duration(seconds: 20),
    DateTime? now,
  }) async {
    var deleted = 0;
    try {
      final dir = await directory;
      if (!await dir.exists()) return 0;
      final kept = {for (final i in keep) p.canonicalize(i.path)};
      final cutoff = (now ?? DateTime.now()).subtract(minAge);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || kept.contains(p.canonicalize(entity.path))) {
          continue;
        }
        try {
          if ((await entity.lastModified()).isAfter(cutoff)) continue;
          await entity.delete();
          deleted++;
        } catch (e) {
          debugPrint('SnapFileStore: could not delete ${entity.path}: $e');
        }
      }
    } catch (e) {
      debugPrint('SnapFileStore: leftover cleanup failed: $e');
    }
    return deleted;
  }
}
