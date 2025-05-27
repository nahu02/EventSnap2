import 'package:event_snap_2/models/calendar_event_properties.dart';

/// Abstract interface for calendar event interpretation services
///
/// This interface allows for different AI service implementations
/// while maintaining a consistent contract for event interpretation.
/// Currently implemented by OpenAiCalendarEventInterpreter.
abstract class CalendarEventInterpreter {
  /// Converts natural language text into structured calendar event properties
  ///
  /// Takes a [eventText] string containing natural language description
  /// and returns a [CalendarEventProperties] object with extracted event details.
  ///
  /// May throw exceptions for network errors, API errors, or parsing failures.
  ///
  /// Example:
  /// ```dart
  /// final interpreter = OpenAiCalendarEventInterpreter(apiKey);
  /// final properties = await interpreter.eventToCalendarPropertiesAsync(
  ///   "Meeting with John tomorrow at 2pm for 1 hour"
  /// );
  /// ```
  Future<CalendarEventProperties> eventToCalendarPropertiesAsync(
    String eventText,
  );
}
