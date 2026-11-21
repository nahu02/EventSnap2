import '../../models/event_model.dart';

/// Minimal RFC 5545 (iCalendar) writer for [EventModel]s.
///
/// - `VCALENDAR` with `VERSION`, `PRODID`, `CALSCALE:GREGORIAN`,
///   `METHOD:PUBLISH`.
/// - One `VEVENT` per event with `UID`, `DTSTAMP`, `DTSTART`/`DTEND` (UTC
///   `…Z` date-times, or `;VALUE=DATE` for all-day events), `SUMMARY` and
///   optional `DESCRIPTION` / `LOCATION`.
/// - TEXT values are escaped (`\\`, `\;`, `\,`, `\n`), lines end with CRLF and
///   are folded at 75 octets without splitting UTF-8 sequences.
class ICalSerializer {
  ICalSerializer._();

  static const String productId = '-//EventSnap//EventSnap2 3.0//EN';
  static const String uidDomain = 'eventsnap.app';
  static const String crlf = '\r\n';
  static const int maxLineOctets = 75;

  /// Serialises [events] into a complete iCalendar document.
  ///
  /// [timestamp] is used for every `DTSTAMP`.
  /// Throws [ArgumentError] if [events] is empty or contains an invalid event.
  static String serialize(
    List<EventModel> events, {
    required DateTime timestamp,
  }) {
    if (events.isEmpty) {
      throw ArgumentError.value(
        events,
        'events',
        'At least one event is required',
      );
    }
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:$productId',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
    ];
    final dtStamp = formatUtcDateTime(timestamp);
    for (final event in events) {
      final errors = event.validate();
      if (errors.isNotEmpty) {
        throw ArgumentError(
          'Invalid event "${event.title}": ${errors.join(', ')}',
        );
      }
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${escapeText('${event.id}@$uidDomain')}')
        ..add('DTSTAMP:$dtStamp');
      if (event.isAllDay) {
        lines
          ..add('DTSTART;VALUE=DATE:${formatDate(event.startDateTime)}')
          ..add('DTEND;VALUE=DATE:${formatDate(event.endDateTime)}');
      } else {
        lines
          ..add('DTSTART:${formatUtcDateTime(event.startDateTime)}')
          ..add('DTEND:${formatUtcDateTime(event.endDateTime)}');
      }
      lines.add('SUMMARY:${escapeText(event.title.trim())}');
      final description = event.description?.trim();
      if (description != null && description.isNotEmpty) {
        lines.add('DESCRIPTION:${escapeText(description)}');
      }
      final location = event.location?.trim();
      if (location != null && location.isNotEmpty) {
        lines.add('LOCATION:${escapeText(location)}');
      }
      lines.add('END:VEVENT');
    }
    lines.add('END:VCALENDAR');

    final buffer = StringBuffer();
    for (final line in lines) {
      buffer
        ..write(foldLine(line))
        ..write(crlf);
    }
    return buffer.toString();
  }

  /// Escapes a TEXT property value (RFC 5545 §3.3.11).
  ///
  /// Backslash, semicolon and comma are backslash-escaped; CRLF, CR and LF
  /// become `\n`; other control characters (except TAB) are dropped.
  static String escapeText(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final buffer = StringBuffer();
    for (final rune in normalized.runes) {
      switch (rune) {
        case 0x5C: // \
          buffer.write(r'\\');
        case 0x3B: // ;
          buffer.write(r'\;');
        case 0x2C: // ,
          buffer.write(r'\,');
        case 0x0A: // LF
          buffer.write(r'\n');
        default:
          final isControl = (rune < 0x20 && rune != 0x09) || rune == 0x7F;
          if (!isControl) buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Folds a content line so that no physical line exceeds [maxLineOctets]
  /// UTF-8 octets (excluding the CRLF). Continuation lines start with a single
  /// space. Multi-octet characters are never split.
  static String foldLine(String line) {
    final buffer = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final length = _utf8Length(rune);
      if (octets + length > maxLineOctets) {
        buffer.write('$crlf ');
        octets = 1; // the leading space
      }
      buffer.writeCharCode(rune);
      octets += length;
    }
    return buffer.toString();
  }

  /// `yyyyMMddTHHmmssZ` in UTC.
  static String formatUtcDateTime(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return '${_pad(utc.year, 4)}${_pad(utc.month)}${_pad(utc.day)}'
        'T${_pad(utc.hour)}${_pad(utc.minute)}${_pad(utc.second)}Z';
  }

  /// `yyyyMMdd` of the (local) calendar date of [dateTime].
  static String formatDate(DateTime dateTime) =>
      '${_pad(dateTime.year, 4)}${_pad(dateTime.month)}${_pad(dateTime.day)}';

  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');

  static int _utf8Length(int rune) {
    if (rune < 0x80) return 1;
    if (rune < 0x800) return 2;
    if (rune < 0x10000) return 3;
    return 4;
  }
}
