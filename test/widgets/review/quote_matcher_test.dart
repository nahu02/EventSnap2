import 'package:event_snap_2/widgets/review/quote_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuoteMatcher.find', () {
    String found(String source, String quote) {
      final m = QuoteMatcher.find(source, quote);
      expect(m, isNotNull, reason: 'expected to find "$quote"');
      return source.substring(m!.start, m.end);
    }

    test('finds an exact quote and returns original offsets', () {
      const source = 'Dinner at Luigi on Friday at 7pm.';
      final m = QuoteMatcher.find(source, 'Friday at 7pm');
      expect(m, const QuoteMatch(19, 32));
      expect(m!.length, 13);
    });

    test('is case-insensitive and keeps the original casing', () {
      expect(found('Meet at the OSLO Office', 'oslo office'), 'OSLO Office');
    });

    test('is whitespace-insensitive across line breaks', () {
      const source = 'Concert on Saturday,\n   June  7\tat 8pm';
      expect(
        found(source, 'Saturday, June 7 at 8pm'),
        'Saturday,\n   June  7\tat 8pm',
      );
    });

    test('treats typographic quotes and dashes as equal', () {
      expect(
        found('It’s on 10–12 May', "It's on 10-12 May"),
        'It’s on 10–12 May',
      );
    });

    test('strips quotation marks the model wrapped around the quote', () {
      expect(found('Party at 9', '"Party at 9"'), 'Party at 9');
      expect(found('Party at 9', '“Party at 9”'), 'Party at 9');
      expect(found('Party at 9 tonight', 'Party at 9...'), 'Party at 9');
    });

    test('falls back to ignoring punctuation', () {
      expect(
        found('Starts 10.00, room 3', 'starts 10:00 room 3'),
        'Starts 10.00, room 3',
      );
      expect(found('Fri., May 25', 'Fri May 25'), 'Fri., May 25');
    });

    test('falls back to the longest segment of an elided quote', () {
      const source = 'Team offsite in Bergen. Bring boots. Starts Monday 9am.';
      expect(
        found(source, 'Team offsite ... Starts Monday 9am'),
        'Starts Monday 9am',
      );
    });

    test('returns null when the quote is missing or absent', () {
      expect(QuoteMatcher.find('Lunch at noon', 'dinner at 8'), isNull);
      expect(QuoteMatcher.find('Lunch at noon', null), isNull);
      expect(QuoteMatcher.find('Lunch at noon', '   '), isNull);
      expect(QuoteMatcher.find('', 'noon'), isNull);
      expect(QuoteMatcher.find('Lunch at noon', '""'), isNull);
    });

    test('matches the first occurrence', () {
      expect(
        QuoteMatcher.find('at 5, then at 5', 'at 5'),
        const QuoteMatch(0, 4),
      );
    });
  });

  group('QuoteMatcher.snippet', () {
    test('returns the whole text when it is short', () {
      const source = 'Lunch with Sam\nat noon';
      final m = QuoteMatcher.find(source, 'with sam')!;
      final s = QuoteMatcher.snippet(source, m);
      expect(s.before, 'Lunch ');
      expect(s.match, 'with Sam');
      expect(s.after, ' at noon');
    });

    test('cuts the context at sentence boundaries', () {
      const source =
          'Welcome. The party is on Friday at 8pm sharp! Bring snacks.\n\nBye';
      final m = QuoteMatcher.find(source, 'friday at 8pm')!;
      final s = QuoteMatcher.snippet(source, m);
      expect(s.before, 'The party is on ');
      expect(s.after, ' sharp!');
    });

    test('truncates long context at word boundaries with ellipses', () {
      final source =
          '${List.filled(30, 'word').join(' ')} KEY PHRASE '
          '${List.filled(30, 'tail').join(' ')}';
      final m = QuoteMatcher.find(source, 'key phrase')!;
      final s = QuoteMatcher.snippet(source, m, context: 20);
      expect(s.match, 'KEY PHRASE');
      expect(s.before, startsWith('…'));
      expect(s.before, endsWith('word '));
      expect(s.before.length, lessThanOrEqualTo(22));
      expect(s.after, startsWith(' tail'));
      expect(s.after, endsWith('…'));
      expect(s.before.substring(1), isNot(startsWith(' ')));
    });
  });
}
