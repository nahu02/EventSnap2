import '../../models/event_model.dart';

/// Turns events into an iCalendar file and hands it to a calendar app.
abstract class CalendarCreator {
  /// Pure RFC 5545 serialisation of [events] into a `VCALENDAR`.
  ///
  /// Throws [ArgumentError] if [events] is empty or an event is invalid.
  String buildIcs(List<EventModel> events);

  /// Writes [buildIcs] output to the temp directory and returns the file path.
  Future<String> createIcsFile(List<EventModel> events);

  /// Opens the file with a calendar app (Android: FileProvider + chooser).
  /// Returns false if no app can handle it.
  Future<bool> openInCalendarApp(String filePath);
}
