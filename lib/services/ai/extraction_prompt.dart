import '../../models/extraction.dart';
import 'extraction_schema.dart';

/// Builds the system prompt and the user message for an extraction.
class ExtractionPrompt {
  ExtractionPrompt._();

  /// Days covered by the date lookup table (today included).
  static const int lookupDays = 21;

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// The system prompt for the user's local time [now].
  ///
  /// [includeSchema] appends the JSON schema (JSON mode / prompt-only mode,
  /// where the API does not enforce it).
  static String system({required DateTime now, required bool includeSchema}) {
    final local = now.toLocal();
    final offset = formatOffset(local.timeZoneOffset);
    final zoneName = local.timeZoneName.trim();
    final zone = zoneName.isEmpty
        ? 'UTC offset $offset'
        : '$zoneName (UTC offset $offset)';
    final example = '${isoDate(local)}T19:00:00$offset';

    final buffer = StringBuffer()
      ..writeln(
        "You extract calendar events from the user's input - text and/or "
        'images such as flyers, posters, screenshots, invitations, tickets '
        'or chat messages - and return them as JSON.',
      )
      ..writeln()
      ..writeln('## Context')
      ..writeln(
        '- Now: ${weekdayName(local)} ${isoDate(local)} '
        "${_two(local.hour)}:${_two(local.minute)} (the user's local time)",
      )
      ..writeln('- Time zone: $zone')
      ..writeln(
        '- Date lookup table. Resolve weekdays and relative dates by finding '
        'the matching line (e.g. "next Friday" -> the line labelled "next '
        'Friday"); never compute dates or weekdays yourself:',
      );
    for (final line in dateTable(local)) {
      buffer.writeln('  $line');
    }
    buffer
      ..writeln()
      ..writeln('## Rules')
      ..writeln(
        '1. Events: return every distinct event (a different date, time or '
        'place usually means a different event). If there is no event, '
        'return {"events": []}.',
      )
      ..writeln(
        '2. title: short and specific like a calendar entry (e.g. "Dinner '
        'with Anna"), in the language of the source. '
        'description: useful extra details from the source (agenda, people, '
        'links, booking or ticket numbers) in the source language, or null. '
        'location: only if stated, else null. Never invent details.',
      )
      ..writeln(
        '3. Dates: resolve relative expressions ("tomorrow", "next Friday", '
        '"in two weeks") with the lookup table. A weekday on its own, "this '
        '<weekday>" or "next <weekday>" means the line labelled "next '
        '<weekday>" (the first such day after today) unless the text clearly '
        'says otherwise. A date without a year is its next occurrence (today '
        'or later).',
      )
      ..writeln(
        "4. Times: write start and end as the user's local wall-clock time "
        'with the offset, e.g. $example. If the source names another time '
        "zone, convert to the user's time zone. Vague times: morning 09:00, "
        'noon 12:00, afternoon 14:00, evening 18:00, night 20:00. If there '
        'is no end, end = start + 1 hour and its evidence has quote null and '
        'confidence "low".',
      )
      ..writeln(
        '5. All-day events: dates without a time for things that naturally '
        'last whole days (birthdays, holidays, deadlines, trips, festivals, '
        'conferences) -> all_day true, start = first day and end = last day '
        '(inclusive), both YYYY-MM-DD; a one-day event has start = end. Any '
        'other date without a time -> 09:00-10:00 with confidence "low".',
      )
      ..writeln(
        '6. Evidence for title, description, location, start and end:\n'
        '   - quote: the shortest verbatim span (max ~8 words) from the input '
        'that supports the value, copied exactly as written (same language, '
        'spelling and case; for images, the text as printed); null if the '
        'value was inferred or defaulted, or the field is null.\n'
        '   - reasoning: one short English sentence on how the value was '
        'derived. For a relative date in start or end, name the lookup line '
        "you used, e.g. \"'next Friday' -> Friday ${_nextFriday(local)} = "
        'next Friday."\n'
        '   - confidence: "high" if stated explicitly, "medium" if inferred '
        'from clear context, "low" if guessed or defaulted.',
      )
      ..writeln()
      ..writeln('## Output');
    if (includeSchema) {
      buffer
        ..writeln(
          'Reply with a single JSON object only (no prose, no code fences) '
          'that matches this JSON Schema:',
        )
        ..write(ExtractionSchema.schemaText);
    } else {
      buffer.write('Return the events as JSON in the requested format.');
    }
    return buffer.toString();
  }

  /// The user message text for [input] (images are sent as separate parts).
  static String user(ExtractionInput input) {
    final parts = <String>[];
    if (input.hasText) {
      parts.add(
        'Extract the calendar events from this text:\n"""\n'
        '${input.text.trim()}\n"""',
      );
    }
    if (input.hasImages) {
      final images = input.images.length == 1
          ? 'the attached image'
          : 'the ${input.images.length} attached images';
      parts.add(
        input.hasText
            ? 'Also read the text in $images; it belongs to the same request.'
            : 'Extract the calendar events from $images.',
      );
    }
    return parts.join('\n\n');
  }

  /// One line per day for [lookupDays] days, labelled with the phrases a
  /// cheap model would otherwise get wrong (seen live: "next Friday" asked on
  /// a Saturday resolved to the following Saturday):
  /// `Saturday 2026-11-21 = today`, `Sunday 2026-11-22 = tomorrow = next
  /// Sunday`, … `Friday 2026-11-27 = next Friday`, … `Friday 2026-12-04 =
  /// Friday after next`, then unlabelled days.
  static List<String> dateTable(DateTime now, {int days = lookupDays}) {
    return [
      for (var i = 0; i < days; i++)
        () {
          final day = DateTime(now.year, now.month, now.day + i);
          final name = weekdayName(day);
          final labels = [
            if (i == 0) 'today',
            if (i == 1) 'tomorrow',
            if (i >= 1 && i <= 7) 'next $name',
            if (i >= 8 && i <= 14) '$name after next',
          ];
          final suffix = labels.isEmpty ? '' : ' = ${labels.join(' = ')}';
          return '$name ${isoDate(day)}$suffix';
        }(),
    ];
  }

  /// English weekday name (independent of the app locale).
  static String weekdayName(DateTime date) => _weekdays[date.weekday - 1];

  /// `YYYY-MM-DD`.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-'
      '${_two(date.day)}';

  /// `+HH:MM` / `-HH:MM`.
  static String formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }

  static String _nextFriday(DateTime now) {
    var day = DateTime(now.year, now.month, now.day + 1);
    while (day.weekday != DateTime.friday) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return isoDate(day);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
