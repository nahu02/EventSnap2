import 'dart:convert';

import '../../models/event_model.dart';
import '../../models/field_evidence.dart';
import '../../models/recurrence.dart';
import 'ai_exceptions.dart';

/// Events and user-presentable notes parsed from a model response.
class ParsedExtraction {
  const ParsedExtraction({required this.events, required this.warnings});

  final List<EventModel> events;
  final List<String> warnings;
}

/// Lenient parser for extraction responses.
///
/// Accepts the strict schema output as well as what models produce without
/// structured output: code fences, prose around the JSON, a bare array, a
/// single event object, v2 capitalised keys (`Summary`, `Start`, …) and common
/// synonyms. Normalises into [EventModel]s (local time, `isAllDay`, evidence)
/// and never throws because of a single bad event: unrecoverable events are
/// skipped with a warning; fixable ones (missing end, end before start,
/// missing title) are repaired and their evidence says so with low
/// confidence.
///
/// Only content that contains no JSON at all throws
/// `AiException(invalidResponse)`.
class ExtractionResponseParser {
  ExtractionResponseParser({required this.referenceOffset});

  /// The UTC offset the prompt told the model to use (the user's offset when
  /// the request was made). A timestamp carrying exactly this offset is read
  /// as local wall-clock time, so events on the other side of a DST change
  /// keep the time the source stated. Other offsets are converted.
  final Duration referenceOffset;

  static const Duration _defaultDuration = Duration(hours: 1);
  static const String untitled = 'Untitled event';

  static const Map<EventField, List<String>> _fieldKeys = {
    EventField.title: ['title', 'summary', 'name', 'eventtitle', 'subject'],
    EventField.description: ['description', 'details', 'notes', 'desc'],
    EventField.location: ['location', 'place', 'venue', 'where', 'address'],
    EventField.start: [
      'start',
      'starttime',
      'startdatetime',
      'startdate',
      'begin',
      'dtstart',
      'from',
      'date',
      'datetime',
    ],
    EventField.end: [
      'end',
      'endtime',
      'enddatetime',
      'enddate',
      'dtend',
      'to',
      'until',
    ],
    EventField.recurrence: ['recurrence', 'repeat', 'repeats', 'rrule'],
  };
  static const List<String> _allDayKeys = [
    'allday',
    'isallday',
    'wholeday',
    'fullday',
  ];
  static const List<String> _evidenceKeys = ['evidence', 'justification'];
  static const Set<String> _nullWords = {'null', 'none', 'n/a', 'na', '-'};

  /// Parses [content]. Throws `AiException(invalidResponse)` only when no
  /// JSON can be found.
  ParsedExtraction parse(String content) {
    final decoded = decodeLenient(content);
    final items = _eventItems(decoded);
    final events = <EventModel>[];
    final warnings = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) {
        warnings.add(
          'Skipped event ${i + 1}: it was not in the expected format.',
        );
        continue;
      }
      try {
        final event = _event(_normalizedKeys(item), warnings);
        if (event == null) {
          warnings.add('Skipped event ${i + 1}: it has no valid start date.');
        } else {
          events.add(event);
        }
      } catch (_) {
        warnings.add('Skipped event ${i + 1}: it could not be read.');
      }
    }
    return ParsedExtraction(events: events, warnings: warnings);
  }

  /// Decodes the JSON in [raw]: strips code fences and falls back to the
  /// outermost `{…}` / `[…]` span.
  static Object? decodeLenient(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'```[a-zA-Z0-9_-]*\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    try {
      return jsonDecode(text);
    } on FormatException {
      // Try the outermost JSON-looking span below.
    }
    final objectStart = text.indexOf('{');
    final arrayStart = text.indexOf('[');
    final candidates = <(int, String)>[
      if (objectStart >= 0) (objectStart, '}'),
      if (arrayStart >= 0) (arrayStart, ']'),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (start, closer) in candidates) {
      final end = text.lastIndexOf(closer);
      if (end <= start) continue;
      try {
        return jsonDecode(text.substring(start, end + 1));
      } on FormatException {
        continue;
      }
    }
    final excerpt = raw.length > 200 ? '${raw.substring(0, 200)}…' : raw;
    throw AiException(
      AiErrorKind.invalidResponse,
      'The model response contains no readable JSON: $excerpt',
    );
  }

  static List<Object?> _eventItems(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final map = _normalizedKeys(decoded);
      final events = map['events'];
      if (events is List) return events;
      if (events is Map) return [events];
      final looksLikeEvent = [
        ..._fieldKeys[EventField.title]!,
        ..._fieldKeys[EventField.start]!,
      ].any(map.containsKey);
      if (looksLikeEvent) return [decoded];
      final lists = map.values.whereType<List<Object?>>().toList();
      if (lists.length == 1) return lists.single;
      return const [];
    }
    throw AiException(
      AiErrorKind.invalidResponse,
      'Unexpected JSON in the model response: ${decoded.runtimeType}',
    );
  }

  /// Lower-cases keys and drops everything but letters
  /// (`all_day`, `allDay`, `All-Day` → `allday`).
  static Map<String, Object?> _normalizedKeys(Map<Object?, Object?> map) => {
    for (final entry in map.entries)
      entry.key.toString().toLowerCase().replaceAll(RegExp('[^a-z]'), ''):
          entry.value,
  };

  static Object? _lookup(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) return map[key];
    }
    return null;
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || _nullWords.contains(trimmed.toLowerCase())) {
      return null;
    }
    return trimmed;
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true' || 'yes':
          return true;
        case 'false' || 'no':
          return false;
      }
    }
    return null;
  }

  EventModel? _event(Map<String, Object?> json, List<String> warnings) {
    final startRaw = _string(_lookup(json, _fieldKeys[EventField.start]!));
    final start = startRaw == null ? null : parseTimestamp(startRaw);
    if (start == null) return null;
    final endRaw = _string(_lookup(json, _fieldKeys[EventField.end]!));
    final end = endRaw == null ? null : parseTimestamp(endRaw);

    final evidence = _evidence(json);
    final title = _string(_lookup(json, _fieldKeys[EventField.title]!));
    final description = _string(
      _lookup(json, _fieldKeys[EventField.description]!),
    );
    final location = _string(_lookup(json, _fieldKeys[EventField.location]!));
    if (title == null) {
      evidence[EventField.title] = const FieldEvidence(
        reasoning: 'No title was found in the input.',
        confidence: EvidenceConfidence.low,
      );
    }
    if (description == null) evidence.remove(EventField.description);
    if (location == null) evidence.remove(EventField.location);

    final allDayFlag = _bool(_lookup(json, _allDayKeys));
    final allDay =
        allDayFlag == true || (start.dateOnly && (end == null || end.dateOnly));

    DateTime startTime;
    DateTime endTime;
    if (allDay) {
      (startTime, endTime) = _allDayRange(start, end, evidence);
    } else {
      (startTime, endTime) = _timedRange(start, end, evidence);
    }
    final shift = weekdayCorrection(
      startTime,
      evidence[EventField.start]?.quote,
    );
    if (shift != 0) {
      startTime = _addDays(startTime, shift);
      endTime = _addDays(endTime, shift);
      final weekday = _weekdayNames[startTime.weekday - 1];
      evidence[EventField.start] = FieldEvidence(
        quote: evidence[EventField.start]?.quote,
        reasoning:
            'Moved to the ${_capitalize(weekday)} named in the source '
            '(the model returned a different weekday).',
        confidence: EvidenceConfidence.medium,
      );
    }

    _downgradeDefaultedEnd(evidence, startTime, endTime, allDay: allDay);

    final recurrence = _recurrence(
      _lookup(json, _fieldKeys[EventField.recurrence]!),
      startTime,
      evidence,
      warnings,
      title ?? untitled,
    );

    return EventModel(
      title: title ?? untitled,
      description: description,
      location: location,
      startDateTime: startTime,
      endDateTime: endTime,
      isAllDay: allDay,
      evidence: evidence,
      recurrence: recurrence,
    );
  }

  static const Map<String, RecurrenceFrequency> _frequencies = {
    'daily': RecurrenceFrequency.daily,
    'day': RecurrenceFrequency.daily,
    'days': RecurrenceFrequency.daily,
    'weekly': RecurrenceFrequency.weekly,
    'week': RecurrenceFrequency.weekly,
    'weeks': RecurrenceFrequency.weekly,
    'monthly': RecurrenceFrequency.monthly,
    'month': RecurrenceFrequency.monthly,
    'months': RecurrenceFrequency.monthly,
    'yearly': RecurrenceFrequency.yearly,
    'annually': RecurrenceFrequency.yearly,
    'year': RecurrenceFrequency.yearly,
    'years': RecurrenceFrequency.yearly,
  };

  /// Reads the optional `recurrence` object. A missing or null value means a
  /// one-off event. An unreadable or invalid rule is dropped (the single event
  /// is kept) with a warning and a low-confidence evidence note.
  RecurrenceRule? _recurrence(
    Object? raw,
    DateTime start,
    Map<EventField, FieldEvidence> evidence,
    List<String> warnings,
    String title,
  ) {
    RecurrenceRule? rule;
    var invalid = false;
    if (raw == null || (raw is String && _string(raw) == null)) {
      // One-off event.
    } else {
      rule = raw is Map ? _readRule(_normalizedKeys(raw), start) : null;
      invalid = rule == null;
    }
    if (rule == null && !invalid) {
      // Nothing repeats: evidence for it would only be noise.
      evidence.remove(EventField.recurrence);
      return null;
    }
    if (invalid) {
      final old = evidence[EventField.recurrence];
      evidence[EventField.recurrence] = FieldEvidence(
        quote: old?.quote,
        reasoning:
            'The repeat pattern could not be read, so it was left out. '
            'Set it yourself if the event repeats.',
        confidence: EvidenceConfidence.low,
      );
      warnings.add(
        'Could not read how “$title” repeats; it was added as a single '
        'event.',
      );
      return null;
    }
    return rule;
  }

  RecurrenceRule? _readRule(Map<String, Object?> json, DateTime start) {
    final freqText = _string(_lookup(json, ['frequency', 'freq']));
    final frequency = freqText == null
        ? null
        : _frequencies[freqText.toLowerCase()];
    if (frequency == null) return null;

    final intervalRaw = _lookup(json, ['interval']);
    final interval = intervalRaw == null ? 1 : _int(intervalRaw);
    final countRaw = _lookup(json, ['count', 'occurrences', 'times']);
    final count = countRaw == null ? null : _int(countRaw);
    if (interval == null || (countRaw != null && count == null)) return null;

    final untilRaw = _string(_lookup(json, ['until', 'enddate', 'end']));
    DateTime? until;
    if (untilRaw != null) {
      until = parseTimestamp(untilRaw)?.wallDate;
      if (until == null) return null;
    }

    final weekdaysRaw = _lookup(json, [
      'weekdays',
      'byday',
      'byweekdays',
      'days',
      'weekday',
    ]);
    final weekdays = <int>{};
    if (weekdaysRaw != null) {
      final items = weekdaysRaw is List ? weekdaysRaw : [weekdaysRaw];
      for (final item in items) {
        final day = item is String ? _weekdayNumber(item) : null;
        if (day == null) return null;
        weekdays.add(day);
      }
    }
    final monthDayRaw = _lookup(json, ['monthday', 'bymonthday', 'dayofmonth']);
    final monthDay = monthDayRaw == null ? null : _int(monthDayRaw);
    final ordinalRaw = _lookup(json, [
      'weekdayordinal',
      'ordinal',
      'nth',
      'bysetpos',
      'setpos',
    ]);
    final ordinal = ordinalRaw == null ? null : _int(ordinalRaw);
    if ((monthDayRaw != null && monthDay == null) ||
        (ordinalRaw != null && ordinal == null)) {
      return null;
    }

    final monthly = frequency == RecurrenceFrequency.monthly;
    final nth = monthly && ordinal != null && weekdays.length == 1;
    final rule = RecurrenceRule(
      frequency: frequency,
      interval: interval,
      byWeekdays: frequency == RecurrenceFrequency.weekly || nth
          ? weekdays
          : const {},
      byMonthDay: monthly && !nth ? monthDay : null,
      weekdayOrdinal: nth ? ordinal : null,
      count: count,
      until: until,
    );
    return rule.isValid && rule.validate(start: start).isEmpty ? rule : null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static int? _weekdayNumber(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.length < 2) return null;
    for (var i = 0; i < _weekdayNames.length; i++) {
      if (_weekdayNames[i].startsWith(text.substring(0, 2)) &&
          (text.length == 2 ||
              _weekdayNames[i].startsWith(text.replaceAll('.', '')))) {
        return i + 1;
      }
    }
    return null;
  }

  /// All-day: `start` = first day, `end` = last day **inclusive** (as asked in
  /// the prompt). A timestamp at exactly midnight on a later day is read as
  /// an exclusive end; `23:59:59` style ends use their date. The model
  /// representation is exclusive: last day + 1, 00:00.
  (DateTime, DateTime) _allDayRange(
    ParsedTimestamp start,
    ParsedTimestamp? end,
    Map<EventField, FieldEvidence> evidence,
  ) {
    final firstDay = start.wallDate;
    var lastDay = firstDay;
    if (end == null) {
      evidence[EventField.end] ??= const FieldEvidence(
        reasoning: 'No end date was given; treated as a one-day event.',
        confidence: EvidenceConfidence.medium,
      );
    } else {
      lastDay = end.wallDate;
      if (!end.dateOnly && end.isWallMidnight && lastDay.isAfter(firstDay)) {
        lastDay = DateTime(lastDay.year, lastDay.month, lastDay.day - 1);
      }
      if (lastDay.isBefore(firstDay)) {
        lastDay = firstDay;
        evidence[EventField.end] = FieldEvidence(
          quote: evidence[EventField.end]?.quote,
          reasoning:
              'The end date was before the start; treated as a '
              'one-day event.',
          confidence: EvidenceConfidence.low,
        );
      }
    }
    return (firstDay, DateTime(lastDay.year, lastDay.month, lastDay.day + 1));
  }

  (DateTime, DateTime) _timedRange(
    ParsedTimestamp start,
    ParsedTimestamp? end,
    Map<EventField, FieldEvidence> evidence,
  ) {
    var startTime = start.local;
    if (start.dateOnly) {
      // Date without a time but the event is not all-day (the end has one).
      startTime = DateTime(startTime.year, startTime.month, startTime.day, 9);
      evidence[EventField.start] = FieldEvidence(
        quote: evidence[EventField.start]?.quote,
        reasoning: 'No start time was given; assumed 09:00.',
        confidence: EvidenceConfidence.low,
      );
    }

    if (end == null || end.dateOnly) {
      evidence[EventField.end] = const FieldEvidence(
        reasoning: 'No end time was given; assumed 1 hour.',
        confidence: EvidenceConfidence.low,
      );
      return (startTime, startTime.add(_defaultDuration));
    }

    var endTime = end.local;
    if (!endTime.isAfter(startTime)) {
      final nextDay = DateTime(
        endTime.year,
        endTime.month,
        endTime.day + 1,
        endTime.hour,
        endTime.minute,
        endTime.second,
      );
      if (nextDay.isAfter(startTime) &&
          nextDay.difference(startTime) < const Duration(hours: 24)) {
        endTime = nextDay;
        evidence[EventField.end] = FieldEvidence(
          quote: evidence[EventField.end]?.quote,
          reasoning:
              'The end time is earlier than the start, so the event '
              'ends after midnight.',
          confidence: EvidenceConfidence.medium,
        );
      } else {
        endTime = startTime.add(_defaultDuration);
        evidence[EventField.end] = FieldEvidence(
          quote: evidence[EventField.end]?.quote,
          reasoning: 'The end was before the start; assumed 1 hour.',
          confidence: EvidenceConfidence.low,
        );
      }
    }
    return (startTime, endTime);
  }

  static const List<String> _weekdayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  static final RegExp _weekdayPattern = RegExp(
    r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?\b',
  );
  static final RegExp _explicitDatePattern = RegExp(
    r'\d{1,2}(st|nd|rd|th)\b|\d{1,2}\s*[./-]\s*\d{1,2}|\d{4}|'
    r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b',
  );

  /// Days to move [start] so it falls on the weekday its evidence [quote]
  /// names, or 0. Safety net for cheap models that mis-resolve "next Friday"
  /// (seen live: a Saturday a week out). Applies only when the quote names
  /// exactly one English weekday and no explicit date; moves to the nearest
  /// such day (at most 3 days either way).
  static int weekdayCorrection(DateTime start, String? quote) {
    if (quote == null) return 0;
    final lower = quote.toLowerCase();
    if (_explicitDatePattern.hasMatch(lower)) return 0;
    final named = _weekdayPattern
        .allMatches(lower)
        .map((m) => m.group(1)!)
        .toSet();
    if (named.length != 1) return 0;
    final target = _weekdayNames.indexOf(named.single) + 1;
    var delta = (target - start.weekday) % 7;
    if (delta > 3) delta -= 7;
    return delta;
  }

  /// Models often justify a defaulted end ("no end given → +1 h") with the
  /// start's quote and "high" confidence. An end that merely repeats the
  /// start quote with exactly one hour of duration is an assumption, so it
  /// is marked low confidence (shown as "Check" on the review screen).
  static void _downgradeDefaultedEnd(
    Map<EventField, FieldEvidence> evidence,
    DateTime start,
    DateTime end, {
    required bool allDay,
  }) {
    if (allDay || end.difference(start) != const Duration(hours: 1)) return;
    final endEvidence = evidence[EventField.end];
    if (endEvidence == null ||
        endEvidence.confidence == EvidenceConfidence.low) {
      return;
    }
    final startQuote = evidence[EventField.start]?.quote?.trim().toLowerCase();
    final endQuote = endEvidence.quote?.trim().toLowerCase();
    if (endQuote != null && endQuote != startQuote) return;
    evidence[EventField.end] = FieldEvidence(
      quote: null,
      reasoning: 'No end time given; assumed a 1-hour event.',
      confidence: EvidenceConfidence.low,
    );
  }

  static DateTime _addDays(DateTime d, int days) => DateTime(
    d.year,
    d.month,
    d.day + days,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
    d.microsecond,
  );

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Map<EventField, FieldEvidence> _evidence(Map<String, Object?> json) {
    final result = <EventField, FieldEvidence>{};
    final raw = _lookup(json, _evidenceKeys);
    if (raw is! Map) return result;
    final map = _normalizedKeys(raw);
    for (final field in EventField.values) {
      final value = _lookup(map, _fieldKeys[field]!);
      if (value is Map) {
        final evidence = _normalizedKeys(value);
        // Models without structured output sometimes write "null" as text.
        evidence['quote'] = _string(evidence['quote']);
        result[field] = FieldEvidence.fromJson(evidence);
      } else if (value is String && value.trim().isNotEmpty) {
        result[field] = FieldEvidence(
          reasoning: value.trim(),
          confidence: EvidenceConfidence.low,
        );
      }
    }
    return result;
  }

  static final RegExp _dateOnly = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
  static final RegExp _dateTime = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})[T ](\d{1,2}):(\d{2})'
    r'(?::(\d{2})(?:[.,]\d+)?)?\s*(Z|z|[+-]\d{2}(?::?\d{2})?)?$',
  );

  /// Parses an ISO 8601 date or date-time. Returns `null` when unreadable or
  /// out of range (e.g. February 30).
  ParsedTimestamp? parseTimestamp(String raw) {
    final text = raw.trim();
    final dateMatch = _dateOnly.firstMatch(text);
    if (dateMatch != null) {
      final date = _validDate(
        int.parse(dateMatch.group(1)!),
        int.parse(dateMatch.group(2)!),
        int.parse(dateMatch.group(3)!),
      );
      if (date == null) return null;
      return ParsedTimestamp(
        local: date,
        wallDate: date,
        dateOnly: true,
        isWallMidnight: true,
      );
    }

    final match = _dateTime.firstMatch(text);
    if (match == null) {
      final fallback = DateTime.tryParse(text);
      if (fallback == null) return null;
      final local = fallback.toLocal();
      return ParsedTimestamp(
        local: local,
        wallDate: DateTime(local.year, local.month, local.day),
        dateOnly: false,
        isWallMidnight: local.hour == 0 && local.minute == 0,
      );
    }

    final date = _validDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6) ?? '0');
    if (date == null ||
        hour > 24 ||
        minute > 59 ||
        second > 59 ||
        (hour == 24 && (minute != 0 || second != 0))) {
      return null;
    }
    final offset = _parseOffset(match.group(7));
    final wall = DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
      second,
    );
    final DateTime local;
    if (offset == null || offset == referenceOffset) {
      local = wall;
    } else {
      local = DateTime.utc(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
        second,
      ).subtract(offset).toLocal();
    }
    return ParsedTimestamp(
      local: local,
      wallDate: date,
      dateOnly: false,
      isWallMidnight: (hour == 0 || hour == 24) && minute == 0 && second == 0,
    );
  }

  static DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  static Duration? _parseOffset(String? raw) {
    if (raw == null) return null;
    if (raw == 'Z' || raw == 'z') return Duration.zero;
    final sign = raw.startsWith('-') ? -1 : 1;
    final digits = raw.substring(1).replaceAll(':', '');
    final hours = int.parse(digits.substring(0, 2));
    final minutes = digits.length >= 4 ? int.parse(digits.substring(2, 4)) : 0;
    return Duration(minutes: sign * (hours * 60 + minutes));
  }
}

/// A timestamp read from a model response.
class ParsedTimestamp {
  const ParsedTimestamp({
    required this.local,
    required this.wallDate,
    required this.dateOnly,
    required this.isWallMidnight,
  });

  /// The instant in local time (see [ExtractionResponseParser.referenceOffset]).
  final DateTime local;

  /// The calendar date as written (offset ignored), at local midnight.
  final DateTime wallDate;

  /// Written as `YYYY-MM-DD` without a time.
  final bool dateOnly;

  /// Written time is exactly 00:00:00 (or 24:00).
  final bool isWallMidnight;
}
