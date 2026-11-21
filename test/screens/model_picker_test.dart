import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/themes/app_theme.dart';
import 'package:event_snap_2/widgets/settings/capability_badges.dart';
import 'package:event_snap_2/widgets/settings/model_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_test_helpers.dart';

/// Records what the picker route completed with.
class _PickerResult {
  AiModelInfo? model;
  bool closed = false;
}

void main() {
  Future<_PickerResult> openPicker(
    WidgetTester tester,
    ScriptedModelCatalog catalog, {
    AiProvider provider = AiProvider.opper,
    String apiKey = 'key',
    String? selected,
    bool settle = true,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    usePhoneView(tester, height: 1600);
    final result = _PickerResult();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showModelPicker(
                  context,
                  catalog: catalog,
                  provider: provider,
                  apiKey: apiKey,
                  selectedModelId: selected,
                ).then((model) {
                  result
                    ..model = model
                    ..closed = true;
                });
              },
              child: const Text('open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open picker'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
    return result;
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(SearchBar), query);
    await tester.pumpAndSettle();
  }

  Finder modelRows() => find.byType(ModelListTile);

  group('loading', () {
    testWidgets('shows progress, then the list', (tester) async {
      final catalog = ScriptedModelCatalog()..listGate = Completer<void>();
      await openPicker(tester, catalog, settle: false);
      expect(find.text('Loading models…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      catalog.listGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Loading models…'), findsNothing);
      expect(modelRows(), findsNWidgets(2));
      expect(find.text('2 models'), findsOneWidget);
    });

    testWidgets('error state retries', (tester) async {
      final catalog = ScriptedModelCatalog(
        error: const AiException(AiErrorKind.network, 'offline'),
      );
      await openPicker(tester, catalog);
      expect(find.text("Couldn't load models"), findsOneWidget);
      expect(
        find.text(AiException.userMessageFor(AiErrorKind.network)),
        findsOneWidget,
      );

      catalog.error = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load models"), findsNothing);
      expect(modelRows(), findsNWidgets(2));
      expect(catalog.forceRefreshFlags, [false, true]);
    });

    testWidgets('a missing key asks for one', (tester) async {
      final catalog = ScriptedModelCatalog(
        error: const AiException(AiErrorKind.notConfigured, 'no key'),
      );
      await openPicker(
        tester,
        catalog,
        provider: AiProvider.openai,
        apiKey: '',
      );
      expect(
        find.text('Add a valid OpenAI API key to load the model list.'),
        findsOneWidget,
      );
      // A model id can still be entered by hand.
      expect(find.text('Use a custom model id'), findsOneWidget);
    });

    testWidgets('empty catalog state', (tester) async {
      final catalog = ScriptedModelCatalog(models: {AiProvider.opper: []});
      await openPicker(tester, catalog);
      expect(find.text('No models available'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Use a custom model id'), findsOneWidget);
    });
  });

  group('list', () {
    testWidgets('recommended models come first', (tester) async {
      final catalog = ScriptedModelCatalog(
        models: {AiProvider.opper: generateModels(300)},
      );
      await openPicker(tester, catalog);
      double top(Finder f) => tester.getTopLeft(f).dy;

      expect(find.text('Recommended'), findsOneWidget);
      expect(
        top(find.text('Recommended')),
        lessThan(top(find.text('Model 0'))),
      );
      expect(top(find.text('Model 0')), lessThan(top(find.text('Model 100'))));
      expect(
        top(find.text('Model 200')),
        lessThan(top(find.text('All models'))),
      );
      expect(top(find.text('All models')), lessThan(top(find.text('Model 1'))));
    });

    testWidgets('rows show vendor, speed, quality and capabilities', (
      tester,
    ) async {
      await openPicker(tester, ScriptedModelCatalog());
      expect(
        find.text('openai/gpt-5-mini · OpenAI · Fast · Great quality'),
        findsOneWidget,
      );
      expect(
        find.text('anthropic/claude-sonnet-5-5 · Anthropic'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: modelRows(),
          matching: find.text('Structured output'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('marks the selected model and returns the tapped one', (
      tester,
    ) async {
      final result = await openPicker(
        tester,
        ScriptedModelCatalog(),
        selected: 'openai/gpt-5-mini',
      );
      final selectedTile = tester.widget<ListTile>(
        find.descendant(
          of: find.widgetWithText(ModelListTile, 'GPT-5 mini'),
          matching: find.byType(ListTile),
        ),
      );
      expect(selectedTile.selected, isTrue);
      expect(find.byIcon(Icons.check), findsWidgets);

      await tester.tap(find.text('Claude Sonnet 5.5'));
      await tester.pumpAndSettle();
      expect(result.closed, isTrue);
      expect(result.model?.id, 'anthropic/claude-sonnet-5-5');
      expect(result.model?.supportsVision, isTrue);
    });

    testWidgets('closing returns null', (tester) async {
      final result = await openPicker(tester, ScriptedModelCatalog());
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(result.closed, isTrue);
      expect(result.model, isNull);
    });

    testWidgets('a custom current model is listed on top', (tester) async {
      await openPicker(
        tester,
        ScriptedModelCatalog(),
        selected: 'my/fine-tune',
      );
      expect(find.text('Current model'), findsOneWidget);
      expect(find.text('my/fine-tune'), findsOneWidget);
      expect(find.text('Structured output unknown'), findsOneWidget);
    });

    testWidgets('stays lazy with 1,300 models', (tester) async {
      final catalog = ScriptedModelCatalog(
        models: {AiProvider.opper: generateModels(1300)},
      );
      await openPicker(tester, catalog);
      expect(find.text('1,300 models'), findsOneWidget);
      // Only the visible rows are built.
      expect(modelRows().evaluate().length, lessThan(40));
      expect(find.text('Model 1234'), findsNothing);

      await search(tester, 'model-1234');
      expect(find.text('Model 1234'), findsOneWidget);
      expect(find.text('1 of 1,300 models'), findsOneWidget);

      await tester.tap(find.text('Model 1234'));
      await tester.pumpAndSettle();
      expect(find.byType(ModelPickerScreen), findsNothing);
    });

    testWidgets('scrolls through a long list', (tester) async {
      final catalog = ScriptedModelCatalog(
        models: {AiProvider.opper: generateModels(1300)},
      );
      await openPicker(tester, catalog);
      await tester.scrollUntilVisible(
        find.text('Model 150'),
        800,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Model 150'), findsOneWidget);
    });
  });

  group('search and filters', () {
    testWidgets('search matches id, name and vendor', (tester) async {
      await openPicker(tester, ScriptedModelCatalog());

      await search(tester, 'claude');
      expect(modelRows(), findsOneWidget);
      expect(find.text('Claude Sonnet 5.5'), findsOneWidget);

      await search(tester, 'Anthropic');
      expect(find.text('Claude Sonnet 5.5'), findsOneWidget);

      await search(tester, 'gpt 5 mini');
      expect(modelRows(), findsOneWidget);
      expect(find.text('GPT-5 mini'), findsOneWidget);
      expect(find.text('1 of 2 models'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(modelRows(), findsNWidgets(2));
    });

    testWidgets('filter chips require the capability', (tester) async {
      const models = [
        AiModelInfo(
          id: 'a/both',
          provider: AiProvider.opper,
          supportsStructuredOutput: true,
          supportsVision: true,
        ),
        AiModelInfo(
          id: 'b/json-only',
          provider: AiProvider.opper,
          supportsStructuredOutput: true,
          supportsVision: false,
        ),
        AiModelInfo(id: 'c/unknown', provider: AiProvider.opper),
        AiModelInfo(
          id: 'd/vision-only',
          provider: AiProvider.opper,
          supportsStructuredOutput: false,
          supportsVision: true,
        ),
      ];
      await openPicker(
        tester,
        ScriptedModelCatalog(models: {AiProvider.opper: models}),
      );
      expect(modelRows(), findsNWidgets(4));

      await tester.tap(find.widgetWithText(FilterChip, 'Structured output'));
      await tester.pumpAndSettle();
      expect(modelRows(), findsNWidgets(2));
      expect(find.text('b/json-only'), findsOneWidget);
      expect(find.text('c/unknown'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Vision'));
      await tester.pumpAndSettle();
      expect(modelRows(), findsOneWidget);
      expect(find.text('a/both'), findsOneWidget);
      expect(find.text('1 of 4 models'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Structured output'));
      await tester.pumpAndSettle();
      expect(modelRows(), findsNWidgets(2));
      expect(find.text('d/vision-only'), findsOneWidget);
    });

    testWidgets('no matches offers to clear the filters', (tester) async {
      await openPicker(tester, ScriptedModelCatalog());
      await search(tester, 'nothing like this');
      expect(find.text('No matching models'), findsOneWidget);
      expect(modelRows(), findsNothing);

      await tester.tap(find.text('Clear search and filters'));
      await tester.pumpAndSettle();
      expect(modelRows(), findsNWidgets(2));
    });
  });

  group('custom model id', () {
    testWidgets('a partial id that matches models offers both', (tester) async {
      final result = await openPicker(tester, ScriptedModelCatalog());
      await search(tester, 'openai/gpt-5');
      expect(find.text('Use “openai/gpt-5”'), findsOneWidget);
      expect(find.text('GPT-5 mini'), findsOneWidget);
      await tester.tap(find.text('Use “openai/gpt-5”'));
      await tester.pumpAndSettle();
      expect(result.model?.id, 'openai/gpt-5');
    });

    testWidgets('an exact catalog id is not offered as custom', (tester) async {
      await openPicker(tester, ScriptedModelCatalog());
      await search(tester, 'openai/gpt-5-mini');
      expect(find.textContaining('Use “'), findsNothing);
      expect(find.text('GPT-5 mini'), findsOneWidget);
    });

    testWidgets('can be entered in a dialog', (tester) async {
      final result = await openPicker(tester, ScriptedModelCatalog());
      await tester.tap(find.text('Use a custom model id'));
      await tester.pumpAndSettle();
      expect(find.text('Custom model id'), findsOneWidget);

      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '  mistral/mistral-large-3 ');
      await tester.pump();
      await tester.tap(find.text('Use model'));
      await tester.pumpAndSettle();

      expect(result.model?.id, 'mistral/mistral-large-3');
      expect(result.model?.provider, AiProvider.opper);
      expect(result.model?.supportsStructuredOutput, isNull);
      expect(result.model?.supportsVision, isNull);
    });

    testWidgets('the dialog needs a non-empty id', (tester) async {
      final result = await openPicker(tester, ScriptedModelCatalog());
      await tester.tap(find.text('Use a custom model id'));
      await tester.pumpAndSettle();
      final use = find.widgetWithText(TextButton, 'Use model');
      expect(tester.widget<TextButton>(use).enabled, isFalse);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(result.closed, isFalse);
    });

    testWidgets('a pasted id can be used straight from the search', (
      tester,
    ) async {
      final result = await openPicker(tester, ScriptedModelCatalog());
      await search(tester, 'deepseek/deepseek-v4');
      expect(find.text('No matching models'), findsOneWidget);
      await tester.tap(find.text('Use “deepseek/deepseek-v4”'));
      await tester.pumpAndSettle();
      expect(result.model?.id, 'deepseek/deepseek-v4');
    });

    testWidgets('an id from the catalog keeps its metadata', (tester) async {
      final result = await openPicker(tester, ScriptedModelCatalog());
      await tester.tap(find.text('Use a custom model id'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'anthropic/claude-sonnet-5-5',
      );
      await tester.pump();
      await tester.tap(find.text('Use model'));
      await tester.pumpAndSettle();
      expect(result.model?.displayName, 'Claude Sonnet 5.5');
      expect(result.model?.supportsStructuredOutput, isTrue);
    });
  });

  group('refresh', () {
    testWidgets('the refresh button forces a reload', (tester) async {
      final catalog = ScriptedModelCatalog();
      await openPicker(tester, catalog);
      await tester.tap(find.byTooltip('Refresh model list'));
      await tester.pumpAndSettle();
      expect(catalog.forceRefreshFlags, [false, true]);
    });

    testWidgets('pull to refresh forces a reload', (tester) async {
      final catalog = ScriptedModelCatalog();
      await openPicker(tester, catalog);
      await tester.fling(find.text('GPT-5 mini'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(catalog.forceRefreshFlags, [false, true]);
    });

    testWidgets('a failed refresh keeps the list', (tester) async {
      final catalog = ScriptedModelCatalog();
      await openPicker(tester, catalog);
      catalog.error = const AiException(AiErrorKind.timeout, 'slow');
      await tester.tap(find.byTooltip('Refresh model list'));
      await tester.pumpAndSettle();
      expect(modelRows(), findsNWidgets(2));
      expect(
        find.text(AiException.userMessageFor(AiErrorKind.timeout)),
        findsOneWidget,
      );
    });
  });

  group('accessibility', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('fits a small phone at 2x text (${mode.name})', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final catalog = ScriptedModelCatalog(
          models: {AiProvider.opper: generateModels(50)},
        );
        await openPicker(tester, catalog, themeMode: mode);
        tester.view.physicalSize = const Size(360, 720);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await search(tester, 'nothing like this');
        expect(find.text('No matching models'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CapabilityBadges', () {
    Future<void> pumpBadges(WidgetTester tester, Widget badges) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Center(child: badges)),
        ),
      );
    }

    testWidgets('labels every state', (tester) async {
      await pumpBadges(
        tester,
        const Column(
          children: [
            CapabilityBadges(structuredOutput: true, vision: false),
            CapabilityBadges(structuredOutput: null, vision: true),
            CapabilityBadges(structuredOutput: false, vision: null),
          ],
        ),
      );
      for (final label in [
        'Structured output',
        'No vision',
        'Structured output unknown',
        'Vision',
        'No structured output',
        'Vision unknown',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('has screen reader labels', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBadges(
        tester,
        const CapabilityBadges(structuredOutput: true, vision: null),
      );
      expect(
        find.bySemanticsLabel('Supports structured output'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Image support unknown'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('compact mode hides unsupported capabilities', (tester) async {
      await pumpBadges(
        tester,
        const CapabilityBadges(
          structuredOutput: false,
          vision: true,
          compact: true,
        ),
      );
      expect(find.text('No structured output'), findsNothing);
      expect(find.text('Vision'), findsOneWidget);
      expect(
        const CapabilityBadges(
          structuredOutput: false,
          vision: false,
          compact: true,
        ).hasBadges,
        isFalse,
      );
    });

    testWidgets('forModel(null) shows unknown capabilities', (tester) async {
      await pumpBadges(tester, CapabilityBadges.forModel(null));
      expect(find.text('Structured output unknown'), findsOneWidget);
      expect(find.text('Vision unknown'), findsOneWidget);
    });
  });
}
