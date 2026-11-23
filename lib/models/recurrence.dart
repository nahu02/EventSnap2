/// How often a recurring event repeats.
enum RecurrenceFrequency { daily, weekly, monthly, yearly }

/// An RFC 5545 style repeat rule for an `EventModel` (immutable).
///
/// The event's own start/end describe the **first** occurrence; this rule
/// describes the rest.
///
/// - [interval]: every N days/weeks/months/years (>= 1).
/// - [byWeekdays]: ISO weekdays (`DateTime.monday` = 1 … `DateTime.sunday` =
///   7). For weekly rules the days of the week; for monthly rules with a
///   [weekdayOrdinal] exactly one weekday. Empty weekly = the start's weekday.
/// - Monthly mode: [byMonthDay] (1..31; null = the start's day) **or**
///   [weekdayOrdinal] (1..4, or -1 for the last) with one weekday in
///   [byWeekdays], e.g. "first Tuesday", "last Friday".
/// - End: never (both null), [count] occurrences (>= 1) or [until] (inclusive
///   date, stored at local midnight). [count] and [until] are mutually
///   exclusive.
class RecurrenceRule {
  RecurrenceRule({
    required this.frequency,
    this.interval = 1,
    Set<int> byWeekdays = const {},
    this.byMonthDay,
    this.weekdayOrdinal,
    this.count,
    DateTime? until,
  }) : byWeekdays = Set.unmodifiable(byWeekdays),
       until = until == null
           ? null
           : DateTime(until.year, until.month, until.day);

  final RecurrenceFrequency frequency;
  final int interval;
  final Set<int> byWeekdays;
  final int? byMonthDay;
  final int? weekdayOrdinal;
  final int? count;
  final DateTime? until;

  /// Whether the rule ends after [count] occurrences or on [until].
  bool get hasEnd => count != null || until != null;

  /// Monthly rule in "nth weekday" mode.
  bool get isNthWeekday =>
      frequency == RecurrenceFrequency.monthly && weekdayOrdinal != null;

  /// Valid ordinals for "nth weekday".
  static const List<int> validOrdinals = [1, 2, 3, 4, -1];

  /// Human-readable problems; empty when the rule is valid.
  ///
  /// When [start] is given, [until] must not be before its date.
  List<String> validate({DateTime? start}) {
    final errors = <String>[];
    if (interval < 1) errors.add('Interval must be at least 1');
    if (count != null && count! < 1) errors.add('Count must be at least 1');
    if (count != null && until != null) {
      errors.add('Use either a count or an end date, not both');
    }
    if (byWeekdays.any((d) => d < 1 || d > 7)) {
      errors.add('Weekdays must be between Monday and Sunday');
    }
    final day = byMonthDay;
    if (day != null) {
      if (frequency != RecurrenceFrequency.monthly) {
        errors.add('A day of the month only applies to monthly repeats');
      } else if (day < 1 || day > 31) {
        errors.add('Day of the month must be between 1 and 31');
      }
    }
    final ordinal = weekdayOrdinal;
    if (ordinal != null) {
      if (frequency != RecurrenceFrequency.monthly) {
        errors.add('An ordinal weekday only applies to monthly repeats');
      } else if (!validOrdinals.contains(ordinal)) {
        errors.add('Ordinal must be 1 to 4 or -1 (last)');
      }
      if (byWeekdays.length != 1) {
        errors.add('An ordinal weekday needs exactly one weekday');
      }
      if (day != null) {
        errors.add('Use either a day of the month or an ordinal weekday');
      }
    } else if (byWeekdays.isNotEmpty &&
        frequency != RecurrenceFrequency.weekly) {
      errors.add('Weekdays only apply to weekly repeats');
    }
    final end = until;
    if (start != null && end != null) {
      final first = DateTime(start.year, start.month, start.day);
      if (end.isBefore(first)) {
        errors.add('The end date must not be before the start date');
      }
    }
    return errors;
  }

  bool get isValid => validate().isEmpty;

  RecurrenceRule copyWith({
    RecurrenceFrequency? frequency,
    int? interval,
    Set<int>? byWeekdays,
    int? byMonthDay,
    int? weekdayOrdinal,
    int? count,
    DateTime? until,
    bool clearByMonthDay = false,
    bool clearWeekdayOrdinal = false,
    bool clearCount = false,
    bool clearUntil = false,
  }) {
    return RecurrenceRule(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      byWeekdays: byWeekdays ?? this.byWeekdays,
      byMonthDay: clearByMonthDay ? null : byMonthDay ?? this.byMonthDay,
      weekdayOrdinal: clearWeekdayOrdinal
          ? null
          : weekdayOrdinal ?? this.weekdayOrdinal,
      count: clearCount ? null : count ?? this.count,
      until: clearUntil ? null : until ?? this.until,
    );
  }

  /// Throws [FormatException] when the shape is wrong (values are not
  /// range-checked; use [validate]).
  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    final name = json['frequency'];
    final frequency = RecurrenceFrequency.values.where((f) => f.name == name);
    if (frequency.isEmpty) {
      throw FormatException('Unknown recurrence frequency: $name');
    }
    final weekdays = json['byWeekdays'];
    final until = json['until'];
    return RecurrenceRule(
      frequency: frequency.first,
      interval: (json['interval'] as num?)?.toInt() ?? 1,
      byWeekdays: weekdays is List
          ? {for (final d in weekdays) (d as num).toInt()}
          : const {},
      byMonthDay: (json['byMonthDay'] as num?)?.toInt(),
      weekdayOrdinal: (json['weekdayOrdinal'] as num?)?.toInt(),
      count: (json['count'] as num?)?.toInt(),
      until: until is String ? DateTime.parse(until) : null,
    );
  }

  Map<String, dynamic> toJson() {
    final end = until;
    return {
      'frequency': frequency.name,
      'interval': interval,
      'byWeekdays': byWeekdays.toList()..sort(),
      'byMonthDay': byMonthDay,
      'weekdayOrdinal': weekdayOrdinal,
      'count': count,
      'until': end == null
          ? null
          : '${end.year.toString().padLeft(4, '0')}-'
                '${end.month.toString().padLeft(2, '0')}-'
                '${end.day.toString().padLeft(2, '0')}',
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecurrenceRule &&
        other.frequency == frequency &&
        other.interval == interval &&
        other.byWeekdays.length == byWeekdays.length &&
        other.byWeekdays.containsAll(byWeekdays) &&
        other.byMonthDay == byMonthDay &&
        other.weekdayOrdinal == weekdayOrdinal &&
        other.count == count &&
        other.until == until;
  }

  @override
  int get hashCode => Object.hash(
    frequency,
    interval,
    Object.hashAllUnordered(byWeekdays),
    byMonthDay,
    weekdayOrdinal,
    count,
    until,
  );

  @override
  String toString() =>
      'RecurrenceRule(${frequency.name}, interval: $interval, '
      'byWeekdays: ${(byWeekdays.toList()..sort())}, byMonthDay: $byMonthDay, '
      'weekdayOrdinal: $weekdayOrdinal, count: $count, until: $until)';
}
