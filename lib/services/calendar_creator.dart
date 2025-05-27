import 'package:event_snap_2/models/calendar_event_properties.dart';

/// Abstract interface for calendar file creation services
///
/// This interface allows for different calendar format implementations
/// while maintaining a consistent contract for calendar file generation.
/// Currently implemented by ICalendarCreator.
abstract class CalendarCreator {
  /// Creates an iCalendar (.ics) file from calendar event properties
  ///
  /// Takes [properties] containing the event data and returns the absolute
  /// file path to the generated .ics file saved in the app's temporary directory.
  ///
  /// The generated file follows RFC 5545 (iCalendar specification) and includes:
  /// - Unique UID for the event
  /// - Proper timezone handling
  /// - Required iCalendar properties (DTSTAMP, VERSION, etc.)
  ///
  /// May throw exceptions for file system errors or invalid event data.
  ///
  /// Example:
  /// ```dart
  /// final creator = ICalendarCreator();
  /// final filePath = await creator.createIcalFile(properties);
  /// // File can now be shared with calendar applications
  /// ```
  Future<String> createIcalFile(CalendarEventProperties properties);
}
