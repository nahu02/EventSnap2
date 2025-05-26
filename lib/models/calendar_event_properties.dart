import 'package:event_snap_2/models/event_model.dart';

/// Represents calendar event properties as returned by the AI service
/// This class is specifically designed to match the OpenAI API response format
/// and can be easily converted to/from EventModel
class CalendarEventProperties {
  /// Event title/summary (maps to EventModel.title)
  String? summary;

  /// Event description providing additional details
  String? description;

  /// Location where the event takes place
  String? location;

  /// Start date and time in ISO 8601 format (e.g., "2025-05-25T10:00:00.000Z")
  String? start;

  /// End date and time in ISO 8601 format (e.g., "2025-05-25T11:00:00.000Z")
  String? end;

  /// Creates a CalendarEventProperties instance
  ///
  /// All fields are optional to accommodate incomplete AI responses
  CalendarEventProperties({
    this.summary,
    this.description,
    this.location,
    this.start,
    this.end,
  });

  /// Creates CalendarEventProperties from JSON data (typically from OpenAI response)
  ///
  /// Expected JSON format from AI:
  /// ```json
  /// {
  ///   "Summary": "Meeting with team",
  ///   "Description": "Weekly standup meeting",
  ///   "Location": "Conference Room A",
  ///   "Start": "2025-05-25T10:00:00.000Z",
  ///   "End": "2025-05-25T11:00:00.000Z"
  /// }
  /// ```
  factory CalendarEventProperties.fromJson(Map<String, dynamic> json) {
    return CalendarEventProperties(
      summary: json['Summary'] as String? ?? json['summary'] as String?,
      description:
          json['Description'] as String? ?? json['description'] as String?,
      location: json['Location'] as String? ?? json['location'] as String?,
      start: json['Start'] as String? ?? json['start'] as String?,
      end: json['End'] as String? ?? json['end'] as String?,
    );
  }

  /// Converts CalendarEventProperties to JSON format
  ///
  /// Uses capitalized keys to match OpenAI expected format
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};

    if (summary != null) json['Summary'] = summary;
    if (description != null) json['Description'] = description;
    if (location != null) json['Location'] = location;
    if (start != null) json['Start'] = start;
    if (end != null) json['End'] = end;

    return json;
  }

  /// Converts CalendarEventProperties to EventModel
  ///
  /// Throws [ArgumentError] if required fields (summary, start, end) are missing
  /// or if date parsing fails
  EventModel toEventModel() {
    if (summary == null || summary!.trim().isEmpty) {
      throw ArgumentError('Summary/title is required to create EventModel');
    }

    if (start == null) {
      throw ArgumentError('Start time is required to create EventModel');
    }

    if (end == null) {
      throw ArgumentError('End time is required to create EventModel');
    }

    try {
      final startDateTime = DateTime.parse(start!);
      final endDateTime = DateTime.parse(end!);

      return EventModel(
        title: summary!,
        description: description,
        location: location,
        startDateTime: startDateTime,
        endDateTime: endDateTime,
      );
    } catch (e) {
      throw ArgumentError('Invalid date format in start or end time: $e');
    }
  }

  /// Creates CalendarEventProperties from EventModel
  ///
  /// Useful for converting user-edited events back to API format
  factory CalendarEventProperties.fromEventModel(EventModel event) {
    return CalendarEventProperties(
      summary: event.title,
      description: event.description,
      location: event.location,
      start: event.startDateTime.toIso8601String(),
      end: event.endDateTime.toIso8601String(),
    );
  }

  /// Creates a copy of this CalendarEventProperties with optional field updates
  CalendarEventProperties copyWith({
    String? summary,
    String? description,
    String? location,
    String? start,
    String? end,
  }) {
    return CalendarEventProperties(
      summary: summary ?? this.summary,
      description: description ?? this.description,
      location: location ?? this.location,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  /// Validates the calendar event properties
  ///
  /// Returns a list of validation errors, empty if valid
  List<String> validate() {
    List<String> errors = [];

    if (summary == null || summary!.trim().isEmpty) {
      errors.add('Summary/title is required');
    }

    if (start != null && end != null) {
      try {
        final startDateTime = DateTime.parse(start!);
        final endDateTime = DateTime.parse(end!);

        if (endDateTime.isBefore(startDateTime)) {
          errors.add('End time must be after start time');
        }

        if (endDateTime.isAtSameMomentAs(startDateTime)) {
          errors.add('End time must be different from start time');
        }
      } catch (e) {
        errors.add('Invalid date format: $e');
      }
    }

    return errors;
  }

  /// Returns true if the calendar event properties are valid
  bool get isValid => validate().isEmpty;

  /// Returns true if this represents a complete event (has all required fields)
  bool get isComplete => summary != null && start != null && end != null;

  @override
  String toString() {
    return 'CalendarEventProperties(summary: $summary, start: $start, end: $end, location: $location, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalendarEventProperties &&
        other.summary == summary &&
        other.description == description &&
        other.location == location &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode {
    return summary.hashCode ^
        description.hashCode ^
        location.hashCode ^
        start.hashCode ^
        end.hashCode;
  }
}
