import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/event_model.dart';
import 'android_calendar_service.dart';
import 'calendar_creator.dart';
import 'ical_serializer.dart';

/// [CalendarCreator] writing RFC 5545 `.ics` files (see [ICalSerializer]).
///
/// Files go to the app's temporary directory; on Android they are opened via
/// the native `FileProvider` + chooser ([AndroidCalendarService]), elsewhere
/// via `url_launcher`.
class ICalendarCreator implements CalendarCreator {
  ICalendarCreator({
    DateTime Function()? clock,
    Future<Directory> Function()? directoryProvider,
    Future<bool> Function(String filePath)? fileOpener,
  }) : _clock = clock ?? DateTime.now,
       _directoryProvider = directoryProvider ?? getTemporaryDirectory,
       _fileOpener = fileOpener ?? _defaultFileOpener;

  static int _fileCounter = 0;

  final DateTime Function() _clock;
  final Future<Directory> Function() _directoryProvider;
  final Future<bool> Function(String filePath) _fileOpener;

  @override
  String buildIcs(List<EventModel> events) =>
      ICalSerializer.serialize(events, timestamp: _clock());

  @override
  Future<String> createIcsFile(List<EventModel> events) async {
    final content = buildIcs(events);
    final directory = await _directoryProvider();
    final fileName =
        'eventsnap_${_clock().microsecondsSinceEpoch}_${_fileCounter++}.ics';
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, encoding: utf8, flush: true);
    return file.path;
  }

  @override
  Future<bool> openInCalendarApp(String filePath) async {
    if (!await File(filePath).exists()) {
      debugPrint('ICalendarCreator: file does not exist: $filePath');
      return false;
    }
    return _fileOpener(filePath);
  }

  static Future<bool> _defaultFileOpener(String filePath) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await AndroidCalendarService.shareCalendarFile(filePath);
      } on PlatformException catch (e) {
        debugPrint('ICalendarCreator: Android calendar share failed: $e');
        return false;
      } on MissingPluginException catch (e) {
        debugPrint('ICalendarCreator: calendar channel unavailable: $e');
        return false;
      }
    }
    try {
      return await launchUrl(
        Uri.file(filePath),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('ICalendarCreator: could not open $filePath: $e');
      return false;
    }
  }
}
