import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/widgets/review/source_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  ExtractionInput input(String text) => ExtractionInput(text: text);

  Future<SourceCardState> pump(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: SourceCard(input: input(text))),
        ),
      ),
    );
    return tester.state<SourceCardState>(find.byType(SourceCard));
  }

  test('short single-line text starts expanded', () {
    expect(SourceCard.shouldStartExpanded(input('Lunch at noon')), isTrue);
    expect(SourceCard.shouldStartExpanded(input('a' * 280)), isTrue);
    expect(SourceCard.shouldStartExpanded(input('a\nb\nc\nd\ne')), isTrue);
  });

  test('text over 280 characters or 5 lines starts collapsed', () {
    expect(SourceCard.shouldStartExpanded(input('a' * 281)), isFalse);
    expect(SourceCard.shouldStartExpanded(input('a\nb\nc\nd\ne\nf')), isFalse);
  });

  testWidgets('long text is collapsed with a preview', (tester) async {
    final state = await pump(tester, 'Long text. ' * 40);
    expect(state.isExpanded, isFalse);
    expect(find.byKey(const ValueKey('source_preview')), findsOneWidget);
  });

  testWidgets('short text is expanded', (tester) async {
    final state = await pump(tester, 'Dinner on Friday at 7');
    expect(state.isExpanded, isTrue);
    expect(find.byKey(const ValueKey('source_preview')), findsNothing);
  });
}
