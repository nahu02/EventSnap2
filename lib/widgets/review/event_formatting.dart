import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/event_model.dart';
import '../../models/recurrence.dart';

/// Locale- and 24-hour-aware date/time formatting for the review UI.
///
/// Uses the app locale when `intl` has date symbols for it (they are loaded by
/// the global Material localizations) and falls back to `en_US` otherwise.
class EventFormatter {
  EventFormatter({String? locale, this.use24HourFormat = false, DateTime? now})
    : locale = _supportedLocale(locale),
      now = now ?? DateTime.now();

  /// Formatter for the current [context] (locale + system 24-hour setting).
  factory EventFormatter.of(BuildContext context, {DateTime? now}) {
    return EventFormatter(
      locale: Localizations.maybeLocaleOf(context)?.toString(),
      use24HourFormat:
          MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false,
      now: now,
    );
  }

  /// `intl` locale used for formatting (`null` = intl default, en_US).
  final String? locale;

  /// Whether times use the 24-hour clock regardless of the locale.
  final bool use24HourFormat;

  /// Reference "now": the year is omitted for dates in the current year.
  final DateTime now;

  /// e.g. `Sun, May 25` (current year) or `Sun, May 25, 2025`.
  String date(DateTime d) => d.year == now.year
      ? DateFormat.MMMEd(locale).format(d)
      : DateFormat.yMMMEd(locale).format(d);

  /// e.g. `10:00 AM` or `10:00` (24-hour clock / locales that prefer it).
  String time(DateTime d) => use24HourFormat
      ? DateFormat.Hm(locale).format(d)
      : DateFormat.jm(locale).format(d);

  /// e.g. `Sun, May 25, 10:00 AM`.
  String dateTime(DateTime d) => '${date(d)}, ${time(d)}';

  /// One-line summary of when [event] happens, e.g.
  /// `Sun, May 25 · 10:00 AM – 11:00 AM`, `Sun, May 25 – Tue, May 27`
  /// (all-day, inclusive last day) or `Sun, May 25` (single all-day).
  String range(EventModel event) => rangeOf(
    start: event.startDateTime,
    end: event.endDateTime,
    isAllDay: event.isAllDay,
  );

  /// Like [range] for raw values (end is exclusive for all-day events).
  String rangeOf({
    required DateTime start,
    required DateTime end,
    required bool isAllDay,
  }) {
    if (isAllDay) {
      final last = DateTime(end.year, end.month, end.day - 1);
      if (!last.isAfter(_day(start))) return date(start);
      return '${date(start)} – ${date(last)}';
    }
    if (_sameDisplayDay(start, end)) {
      return '${date(start)} · ${time(start)} – ${time(end)}';
    }
    return '${dateTime(start)} – ${dateTime(end)}';
  }

  /// Human-readable length, e.g. `45 min`, `1 h 30 min`, `2 days`.
  String duration({
    required DateTime start,
    required DateTime end,
    required bool isAllDay,
  }) {
    if (isAllDay) {
      final days = DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      return days == 1 ? '1 day' : '$days days';
    }
    final total = end.difference(start).inMinutes;
    if (total <= 0) return '0 min';
    final days = total ~/ (24 * 60);
    final hours = (total % (24 * 60)) ~/ 60;
    final minutes = total % 60;
    return [
      if (days > 0) days == 1 ? '1 day' : '$days days',
      if (hours > 0) '$hours h',
      if (minutes > 0) '$minutes min',
    ].join(' ');
  }

  /// Display value of [field]-like date parts used in "Suggested: …" lines.
  String startValue(EventModel e) =>
      e.isAllDay ? date(e.startDateTime) : dateTime(e.startDateTime);

  String endValue(EventModel e) =>
      e.isAllDay ? date(e.lastDay) : dateTime(e.endDateTime);

  /// Short weekday name for an ISO [weekday] (1 = Monday), e.g. `Mon`.
  String weekdayShort(int weekday) =>
      DateFormat.E(locale).format(_isoWeekday(weekday));

  /// Full weekday name for an ISO [weekday], e.g. `Tuesday`.
  String weekdayLong(int weekday) =>
      DateFormat.EEEE(locale).format(_isoWeekday(weekday));

  /// e.g. `Dec 15, 2026`.
  String shortDate(DateTime d) => DateFormat.yMMMd(locale).format(d);

  static DateTime _isoWeekday(int weekday) =>
      DateTime(2024, 1, weekday); // 2024-01-01 is a Monday.

  /// English ordinal word for a monthly "nth weekday" rule.
  static String ordinalWord(int ordinal) => switch (ordinal) {
    1 => 'first',
    2 => 'second',
    3 => 'third',
    4 => 'fourth',
    -1 => 'last',
    _ => '$ordinal.',
  };

  /// One-line summary of how an event starting at [start] repeats, e.g.
  /// `Does not repeat`, `Every week on Mon, Wed · until Dec 15, 2026`,
  /// `Every 2 weeks on Fri · 10 times`, `Monthly on the first Tuesday`,
  /// `Every year`.
  String recurrence(RecurrenceRule? rule, DateTime start) {
    if (rule == null) return 'Does not repeat';
    final n = rule.interval;
    final String base;
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        base = n == 1 ? 'Every day' : 'Every $n days';
      case RecurrenceFrequency.weekly:
        final days = (rule.byWeekdays.isEmpty
            ? [start.weekday]
            : (rule.byWeekdays.toList()..sort()));
        base =
            '${n == 1 ? 'Every week' : 'Every $n weeks'} on '
            '${days.map(weekdayShort).join(', ')}';
      case RecurrenceFrequency.monthly:
        final ordinal = rule.weekdayOrdinal;
        final String when;
        if (ordinal != null && rule.byWeekdays.isNotEmpty) {
          when =
              'the ${ordinalWord(ordinal)} '
              '${weekdayLong(rule.byWeekdays.first)}';
        } else {
          when = 'day ${rule.byMonthDay ?? start.day}';
        }
        base = '${n == 1 ? 'Monthly' : 'Every $n months'} on $when';
      case RecurrenceFrequency.yearly:
        base = n == 1 ? 'Every year' : 'Every $n years';
    }
    final until = rule.until;
    final count = rule.count;
    if (until != null) return '$base · until ${shortDate(until)}';
    if (count != null) {
      return '$base · ${count == 1 ? '1 time' : '$count times'}';
    }
    return base;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Same calendar day, or ends at the following midnight (e.g. 22:00–00:00).
  static bool _sameDisplayDay(DateTime start, DateTime end) {
    if (_day(start) == _day(end)) return true;
    final isMidnight = end.hour == 0 && end.minute == 0 && end.second == 0;
    return isMidnight &&
        _day(end) == DateTime(start.year, start.month, start.day + 1);
  }

  static String? _supportedLocale(String? locale) {
    if (locale == null) return null;
    try {
      DateFormat.yMd(locale);
      return locale;
    } catch (_) {
      return null;
    }
  }
}
