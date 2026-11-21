import 'package:event_snap_2/models/field_evidence.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/widgets/review/evidence_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _source =
    'Hi all! Our quarterly planning meeting is on Friday, June 6 from 2pm.';

Future<void> _pump(
  WidgetTester tester,
  EvidenceLine line, {
  ThemeMode themeMode = ThemeMode.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: line),
      ),
    ),
  );
}

/// Plain text of every `Text`/`Text.rich` widget under [finder].
String _textOf(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  return text.data ?? text.textSpan!.toPlainText();
}

void main() {
  const quoted = FieldEvidence(
    quote: 'Friday, June 6 from 2pm',
    reasoning: 'Date and start time are stated explicitly.',
    confidence: EvidenceConfidence.high,
  );
  const inferred = FieldEvidence(
    reasoning: 'No end time given; assumed one hour.',
    confidence: EvidenceConfidence.low,
  );

  testWidgets('shows the quote and the reasoning', (tester) async {
    await _pump(
      tester,
      const EvidenceLine(
        field: EventField.start,
        evidence: quoted,
        sourceText: _source,
      ),
    );

    expect(find.byIcon(Icons.format_quote), findsOneWidget);
    expect(
      find.text(
        '“Friday, June 6 from 2pm” · Date and start time are stated explicitly.',
      ),
      findsOneWidget,
    );
    expect(find.byType(CheckBadge), findsNothing);
  });

  testWidgets('shows "Inferred" and a Check badge for low confidence '
      'without a quote', (tester) async {
    await _pump(
      tester,
      const EvidenceLine(field: EventField.end, evidence: inferred),
    );

    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    expect(
      find.text('Inferred · No end time given; assumed one hour.'),
      findsOneWidget,
    );
    expect(find.byType(CheckBadge), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);

    // The badge uses the tertiary container role.
    final badge = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(CheckBadge),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final scheme = AppTheme.light().colorScheme;
    expect(
      (badge.decoration as ShapeDecoration).color,
      scheme.tertiaryContainer,
    );
  });

  testWidgets('expands to show the quote in context, the confidence and '
      '"Show in source"', (tester) async {
    var activated = 0;
    var shown = 0;
    await _pump(
      tester,
      EvidenceLine(
        field: EventField.start,
        evidence: quoted,
        sourceText: _source,
        onActivate: () => activated++,
        onShowInSource: () => shown++,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('evidence_start')));
    await tester.pumpAndSettle();

    expect(activated, 1);
    expect(find.text('From your text'), findsOneWidget);
    expect(find.text('High confidence'), findsOneWidget);
    expect(
      find.text('Date and start time are stated explicitly.'),
      findsOneWidget,
    );

    final context = find.byKey(const ValueKey('evidence_quote_context'));
    expect(
      _textOf(tester, context),
      // Context is cut at sentence boundaries ("Hi all!" is dropped).
      'Our quarterly planning meeting is on Friday, June 6 from 2pm.',
    );
    final span = tester.widget<Text>(context).textSpan! as TextSpan;
    final highlighted = span.children!.cast<TextSpan>().singleWhere(
      (s) => s.style?.backgroundColor != null,
    );
    expect(highlighted.text, 'Friday, June 6 from 2pm');

    await tester.tap(find.text('Show in source'));
    expect(shown, 1);

    // Collapses again.
    await tester.tap(find.byKey(const ValueKey('evidence_start')));
    await tester.pumpAndSettle();
    expect(find.text('High confidence'), findsNothing);
    expect(activated, 2);
  });

  testWidgets('an unmatched quote with images reads "Read from your image" '
      'and offers no "Show in source"', (tester) async {
    await _pump(
      tester,
      EvidenceLine(
        field: EventField.location,
        evidence: const FieldEvidence(
          quote: 'Main Hall',
          reasoning: 'Printed on the flyer.',
          confidence: EvidenceConfidence.medium,
        ),
        sourceText: _source,
        hasImages: true,
        onShowInSource: () {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('evidence_location')));
    await tester.pumpAndSettle();

    expect(find.text('Read from your image'), findsOneWidget);
    expect(find.text('“Main Hall”'), findsOneWidget);
    expect(find.text('Medium confidence'), findsOneWidget);
    expect(find.text('Show in source'), findsNothing);
  });

  testWidgets('"Edited by you" replaces the reasoning and the Check badge', (
    tester,
  ) async {
    await _pump(
      tester,
      const EvidenceLine(
        field: EventField.end,
        evidence: inferred,
        edited: true,
        suggestedValue: 'Fri, Jun 6, 3:00 PM',
      ),
    );

    expect(find.text('Edited by you'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byType(CheckBadge), findsNothing);
    expect(find.textContaining('assumed one hour'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('evidence_end')));
    await tester.pumpAndSettle();
    expect(find.text('Suggested: Fri, Jun 6, 3:00 PM'), findsOneWidget);
    expect(find.text('No end time given; assumed one hour.'), findsOneWidget);
    expect(find.text('Low confidence: check this value'), findsOneWidget);
  });

  testWidgets('renders in dark mode at text scale 2 without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(
      tester,
      const EvidenceLine(
        field: EventField.end,
        evidence: FieldEvidence(
          quote: 'Friday, June 6 from 2pm',
          reasoning: 'A rather long explanation that will need to wrap.',
          confidence: EvidenceConfidence.low,
        ),
        sourceText: _source,
      ),
      themeMode: ThemeMode.dark,
    );
    await tester.tap(find.byKey(const ValueKey('evidence_end')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Low confidence: check this value'), findsOneWidget);
  });
}
