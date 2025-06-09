import 'package:intl/intl.dart';

/// Represents a calendar event with all necessary properties
/// Used throughout the application to store and manipulate event data
class EventModel {
  /// The title/summary of the event (required field)
  String title;

  /// Optional description providing additional details about the event
  String? description;

  /// Optional location where the event takes place
  String? location;

  /// Start date and time of the event (required field)
  DateTime startDateTime;

  /// End date and time of the event (required field)
  DateTime endDateTime;

  /// Creates an EventModel instance
  ///
  /// [title] and [startDateTime] and [endDateTime] are required
  /// [description] and [location] are optional
  EventModel({
    required this.title,
    this.description,
    this.location,
    required this.startDateTime,
    required this.endDateTime,
  }) {
    // Validate that end time is after start time
    if (endDateTime.isBefore(startDateTime)) {
      throw ArgumentError('End time must be after start time');
    }

    // Validate that title is not empty
    if (title.trim().isEmpty) {
      throw ArgumentError('Title cannot be empty');
    }
  }

  /// Creates an EventModel from JSON data
  ///
  /// Expected JSON format:
  /// ```json
  /// {
  ///   "title": "Meeting with team",
  ///   "description": "Weekly standup meeting",
  ///   "location": "Conference Room A",
  ///   "startDateTime": "2025-05-25T10:00:00.000Z",
  ///   "endDateTime": "2025-05-25T11:00:00.000Z"
  /// }
  /// ```
  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      title: json['title'] as String,
      description: json['description'] as String?,
      location: json['location'] as String?,
      startDateTime: DateTime.parse(json['startDateTime'] as String),
      endDateTime: DateTime.parse(json['endDateTime'] as String),
    );
  }

  /// Converts the EventModel to JSON format
  ///
  /// Returns a Map＜String, dynamic＞ suitable for JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
    };
  }

  /// Creates a copy of this EventModel with optional field updates
  ///
  /// Useful for state management and form editing
  EventModel copyWith({
    String? title,
    String? description,
    String? location,
    DateTime? startDateTime,
    DateTime? endDateTime,
  }) {
    return EventModel(
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
    );
  }

  /// Validates the event model and returns a list of validation errors
  ///
  /// Returns an empty list if the model is valid
  List<String> validate() {
    List<String> errors = [];

    if (title.trim().isEmpty) {
      errors.add('Title is required');
    }

    if (endDateTime.isBefore(startDateTime)) {
      errors.add('End time must be after start time');
    }

    if (endDateTime.isAtSameMomentAs(startDateTime)) {
      errors.add('End time must be different from start time');
    }

    return errors;
  }

  /// Returns true if the event model is valid
  bool get isValid => validate().isEmpty;

  /// Gets the duration of the event
  Duration get duration => endDateTime.difference(startDateTime);

  /// Formats the start time for display
  String get formattedStartTime =>
      DateFormat('MMM dd, yyyy - HH:mm').format(startDateTime);

  /// Formats the end time for display
  String get formattedEndTime =>
      DateFormat('MMM dd, yyyy - HH:mm').format(endDateTime);

  /// Gets a formatted string representing the time range of the event
  String get formattedTimeRange {
    final now = DateTime.now();
    final isStartInCurrentYear = startDateTime.year == now.year;
    final isEndInCurrentYear = endDateTime.year == now.year;

    final startFormat = isStartInCurrentYear
        ? 'MMM dd; HH:mm'
        : 'MMM dd, yyyy; HH:mm';
    final startFormatted = DateFormat(startFormat).format(startDateTime);

    final String endFormatted;
    if (startDateTime.day == endDateTime.day &&
        startDateTime.month == endDateTime.month &&
        startDateTime.year == endDateTime.year) {
      // Same day - only show time
      endFormatted = DateFormat('HH:mm').format(endDateTime);
    } else {
      // Different day - show date and time, include year if not current year
      final endFormat = isEndInCurrentYear
          ? 'MMM dd; HH:mm'
          : 'MMM dd, yyyy; HH:mm';
      endFormatted = DateFormat(endFormat).format(endDateTime);
    }

    return '$startFormatted - $endFormatted';
  }

  /// Gets a human-readable duration string
  String get formattedDuration {
    final duration = this.duration;
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? 's' : ''}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''}';
    } else {
      return '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
    }
  }

  @override
  String toString() {
    return 'EventModel(title: $title, startDateTime: $startDateTime, endDateTime: $endDateTime, location: $location, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventModel &&
        other.title == title &&
        other.description == description &&
        other.location == location &&
        other.startDateTime == startDateTime &&
        other.endDateTime == endDateTime;
  }

  @override
  int get hashCode {
    return title.hashCode ^
        description.hashCode ^
        location.hashCode ^
        startDateTime.hashCode ^
        endDateTime.hashCode;
  }
}
