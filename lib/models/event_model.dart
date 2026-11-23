import 'dart:math';

import 'package:intl/intl.dart';

import 'field_evidence.dart';
import 'recurrence.dart';

/// Represents a calendar event with all necessary properties.
///
/// Times are always stored in **local** time (`isUtc == false`); UTC inputs
/// are converted with [DateTime.toLocal] by the constructor and [fromJson].
///
/// All-day events ([isAllDay]) store midnights: [startDateTime] is the first
/// day at 00:00 and [endDateTime] is **exclusive** (the day after the last
/// day, 00:00). The constructor normalises all-day inputs by flooring the start
/// and ceiling the end to midnight, so e.g. `10:00–11:00 on May 25` becomes
/// `May 25 00:00 – May 26 00:00`.
class EventModel {
  /// Stable local identifier (generated when absent). Not part of `==` /
  /// [hashCode]; preserved by [copyWith]. Used e.g. for the iCalendar UID.
  final String id;

  /// The title/summary of the event (required, non-blank).
  String title;

  /// Optional description providing additional details about the event.
  String? description;

  /// Optional location where the event takes place.
  String? location;

  /// Start of the event, local time.
  DateTime startDateTime;

  /// End of the event, local time (exclusive midnight for all-day events).
  DateTime endDateTime;

  /// Whether this is an all-day (date-only) event.
  bool isAllDay;

  /// Per-field AI evidence. Empty for manually created events.
  Map<EventField, FieldEvidence> evidence;

  /// How the event repeats; `null` for a one-off event. [startDateTime] /
  /// [endDateTime] describe the first occurrence.
  RecurrenceRule? recurrence;

  /// Creates an EventModel.
  ///
  /// Throws [ArgumentError] when [title] is blank or when [endDateTime] is not
  /// after [startDateTime] (after all-day normalisation).
  EventModel({
    String? id,
    required this.title,
    this.description,
    this.location,
    required DateTime startDateTime,
    required DateTime endDateTime,
    this.isAllDay = false,
    Map<EventField, FieldEvidence> evidence = const {},
    this.recurrence,
  }) : id = (id == null || id.isEmpty) ? generateId() : id,
       startDateTime = isAllDay
           ? _floorToMidnight(startDateTime.toLocal())
           : startDateTime.toLocal(),
       endDateTime = isAllDay
           ? _ceilToMidnight(endDateTime.toLocal())
           : endDateTime.toLocal(),
       evidence = Map.unmodifiable(evidence) {
    if (!this.endDateTime.isAfter(this.startDateTime)) {
      throw ArgumentError('End time must be after start time');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError('Title cannot be empty');
    }
  }

  /// Creates an EventModel from JSON data (format written by [toJson]).
  ///
  /// `id`, `isAllDay` and `evidence` are optional for compatibility with the
  /// v2 format.
  factory EventModel.fromJson(Map<String, dynamic> json) {
    final rawEvidence = json['evidence'];
    final evidence = <EventField, FieldEvidence>{};
    if (rawEvidence is Map) {
      for (final entry in rawEvidence.entries) {
        final field = _fieldByName(entry.key.toString());
        final value = entry.value;
        if (field != null && value is Map) {
          evidence[field] = FieldEvidence.fromJson(
            Map<String, dynamic>.from(value),
          );
        }
      }
    }
    RecurrenceRule? recurrence;
    final rawRecurrence = json['recurrence'];
    if (rawRecurrence is Map) {
      try {
        recurrence = RecurrenceRule.fromJson(
          Map<String, dynamic>.from(rawRecurrence),
        );
      } catch (_) {
        recurrence = null;
      }
    }
    return EventModel(
      id: json['id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      location: json['location'] as String?,
      startDateTime: DateTime.parse(json['startDateTime'] as String),
      endDateTime: DateTime.parse(json['endDateTime'] as String),
      isAllDay: json['isAllDay'] as bool? ?? false,
      evidence: evidence,
      recurrence: recurrence,
    );
  }

  /// Converts the EventModel to JSON (local ISO 8601 timestamps).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'location': location,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'isAllDay': isAllDay,
      'recurrence': recurrence?.toJson(),
      'evidence': {
        for (final entry in evidence.entries)
          entry.key.name: entry.value.toJson(),
      },
    };
  }

  /// Creates a copy with optional field updates. The [id] is preserved.
  ///
  /// [clearDescription] / [clearLocation] / [clearRecurrence] reset those fields to null (they
  /// win over a given value).
  EventModel copyWith({
    String? title,
    String? description,
    String? location,
    DateTime? startDateTime,
    DateTime? endDateTime,
    bool? isAllDay,
    Map<EventField, FieldEvidence>? evidence,
    bool clearDescription = false,
    bool clearLocation = false,
    RecurrenceRule? recurrence,
    bool clearRecurrence = false,
  }) {
    return EventModel(
      id: id,
      title: title ?? this.title,
      description: clearDescription ? null : description ?? this.description,
      location: clearLocation ? null : location ?? this.location,
      startDateTime: startDateTime ?? this.startDateTime,
      endDateTime: endDateTime ?? this.endDateTime,
      isAllDay: isAllDay ?? this.isAllDay,
      evidence: evidence ?? this.evidence,
      recurrence: clearRecurrence ? null : recurrence ?? this.recurrence,
    );
  }

  /// Validates the event model and returns a list of validation errors.
  ///
  /// Returns an empty list if the model is valid.
  List<String> validate() {
    final errors = <String>[];

    if (title.trim().isEmpty) {
      errors.add('Title is required');
    }

    if (endDateTime.isBefore(startDateTime)) {
      errors.add('End time must be after start time');
    }

    if (endDateTime.isAtSameMomentAs(startDateTime)) {
      errors.add('End time must be different from start time');
    }

    if (isAllDay &&
        (!_isMidnight(startDateTime) || !_isMidnight(endDateTime))) {
      errors.add('All-day events must start and end at midnight');
    }

    errors.addAll(recurrence?.validate(start: startDateTime) ?? const []);

    return errors;
  }

  /// Returns true if the event model is valid.
  bool get isValid => validate().isEmpty;

  /// Gets the duration of the event.
  Duration get duration => endDateTime.difference(startDateTime);

  /// The last day covered by an all-day event (inclusive), i.e. the day
  /// before [endDateTime]. For timed events this is the day of [endDateTime].
  DateTime get lastDay {
    if (isAllDay) {
      return DateTime(endDateTime.year, endDateTime.month, endDateTime.day - 1);
    }
    return DateTime(endDateTime.year, endDateTime.month, endDateTime.day);
  }

  /// Formats the start time for display.
  String get formattedStartTime => isAllDay
      ? DateFormat('MMM dd, yyyy').format(startDateTime)
      : DateFormat('MMM dd, yyyy - HH:mm').format(startDateTime);

  /// Formats the end time for display (last day for all-day events).
  String get formattedEndTime => isAllDay
      ? DateFormat('MMM dd, yyyy').format(lastDay)
      : DateFormat('MMM dd, yyyy - HH:mm').format(endDateTime);

  /// Gets a formatted string representing the time range of the event.
  String get formattedTimeRange {
    final now = DateTime.now();
    final isStartInCurrentYear = startDateTime.year == now.year;

    if (isAllDay) {
      final last = lastDay;
      final startFormatted = DateFormat(
        isStartInCurrentYear ? 'MMM dd' : 'MMM dd, yyyy',
      ).format(startDateTime);
      if (_isSameDay(startDateTime, last)) return '$startFormatted (all day)';
      final endFormatted = DateFormat(
        last.year == now.year ? 'MMM dd' : 'MMM dd, yyyy',
      ).format(last);
      return '$startFormatted - $endFormatted (all day)';
    }

    final isEndInCurrentYear = endDateTime.year == now.year;
    final startFormat = isStartInCurrentYear
        ? 'MMM dd; HH:mm'
        : 'MMM dd, yyyy; HH:mm';
    final startFormatted = DateFormat(startFormat).format(startDateTime);

    final String endFormatted;
    if (_isSameDay(startDateTime, endDateTime)) {
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

  /// Gets a human-readable duration string.
  String get formattedDuration {
    if (isAllDay) {
      final days = _calendarDaysBetween(startDateTime, endDateTime);
      return '$days day${days > 1 ? 's' : ''}';
    }
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
    return 'EventModel(id: $id, title: $title, startDateTime: $startDateTime, '
        'endDateTime: $endDateTime, isAllDay: $isAllDay, recurrence: $recurrence, location: $location, '
        'description: $description, evidence: ${evidence.length} fields)';
  }

  /// Equality ignores [id].
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventModel &&
        other.title == title &&
        other.description == description &&
        other.location == location &&
        other.startDateTime == startDateTime &&
        other.endDateTime == endDateTime &&
        other.isAllDay == isAllDay &&
        other.recurrence == recurrence &&
        _evidenceEquals(other.evidence, evidence);
  }

  @override
  int get hashCode => Object.hash(
    title,
    description,
    location,
    startDateTime,
    endDateTime,
    isAllDay,
    recurrence,
    Object.hashAllUnordered(
      evidence.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  // ---------------------------------------------------------------------------

  static final Random _random = Random();
  static int _idCounter = 0;

  /// Generates a new unique local id.
  static String generateId() {
    _idCounter = (_idCounter + 1) & 0xFFFFFF;
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final counter = _idCounter.toRadixString(36);
    final random = _random.nextInt(1 << 32).toRadixString(36);
    return 'evt-$time-$counter-$random';
  }

  static EventField? _fieldByName(String name) {
    for (final field in EventField.values) {
      if (field.name == name) return field;
    }
    return null;
  }

  static bool _evidenceEquals(
    Map<EventField, FieldEvidence> a,
    Map<EventField, FieldEvidence> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _isMidnight(DateTime d) =>
      d.hour == 0 &&
      d.minute == 0 &&
      d.second == 0 &&
      d.millisecond == 0 &&
      d.microsecond == 0;

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _floorToMidnight(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime _ceilToMidnight(DateTime d) =>
      _isMidnight(d) ? d : DateTime(d.year, d.month, d.day + 1);

  static int _calendarDaysBetween(DateTime start, DateTime end) {
    // Use UTC dates to avoid DST-length days skewing the count.
    final a = DateTime.utc(start.year, start.month, start.day);
    final b = DateTime.utc(end.year, end.month, end.day);
    return b.difference(a).inDays;
  }
}
