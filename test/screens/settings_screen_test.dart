import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/navigation/app_router.dart';
import 'package:event_snap_2/screens/settings_screen.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/widgets/settings/api_key_field.dart';
import 'package:event_snap_2/widgets/settings/external_links.dart';
import 'package:event_snap_2/widgets/settings/model_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';
import 'settings_test_helpers.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'EventSnap',
      packageName: 'com.example.event_snap_2',
      version: '3.0.0',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  Future<TestServices> pumpSettings(
    WidgetTester tester, {
    Settings settings = const Settings(),
    ScriptedModelCatalog? catalog,
    bool themed = false,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    usePhoneView(tester);
    final services = servicesWith(settings: settings, catalog: catalog);
    await services.initAppState();
    await tester.pumpWidget(
      themed
          ? themedApp(services, const SettingsScreen())
          : services.wrap(const SettingsScreen(), themeMode: themeMode),
    );
    await tester.pumpAndSettle();
    return services;
  }

  Finder keyField() => find.descendant(
    of: find.byType(ApiKeyField),
    matching: find.byType(TextField),
  );
  String keyText(WidgetTester tester) =>
      tester.widget<TextField>(keyField()).controller!.text;
  Finder providerSegment(String label) => find.descendant(
    of: find.byType(SegmentedButton<AiProvider>),
    matching: find.text(label),
  );
  Finder verifyButton() => find.widgetWithText(OutlinedButton, 'Verify key');

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> expandAdvanced(WidgetTester tester) =>
      tapVisible(tester, find.text('Request options and debugging'));

  group('layout', () {
    testWidgets('shows every section', (tester) async {
      await pumpSettings(tester);
      for (final title in [
        'AI provider',
        'API key',
        'Model',
        'Sharing',
        'Appearance',
        'Advanced',
        'About',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Settings'), findsOneWidget);
      // No save button: changes are saved automatically.
      expect(find.text('Save'), findsNothing);
      expect(find.textContaining('Saved automatically'), findsOneWidget);
    });

    testWidgets('describes both providers', (tester) async {
      await pumpSettings(tester);
      expect(
        find.textContaining('One key, hundreds of models from many vendors'),
        findsOneWidget,
      );
      expect(find.textContaining('OpenAI key'), findsOneWidget);
    });

    testWidgets('advanced section starts collapsed', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Debug mode'), findsNothing);
      expect(
        find.text('Structured output auto · 2 retries · 60 s timeout'),
        findsOneWidget,
      );
      await expandAdvanced(tester);
      expect(find.text('Debug mode'), findsOneWidget);
      expect(find.text('Max retries'), findsOneWidget);
      expect(find.text('Timeout'), findsOneWidget);
    });

    testWidgets('shows a spinner until settings are loaded', (tester) async {
      usePhoneView(tester);
      final services = servicesWith();
      await tester.pumpWidget(services.wrap(const SettingsScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('AI provider'), findsNothing);

      await services.initAppState();
      await tester.pumpAndSettle();
      expect(find.text('AI provider'), findsOneWidget);
    });
  });

  group('provider and API keys', () {
    testWidgets('switching provider keeps both keys', (tester) async {
      final services = await pumpSettings(
        tester,
        settings: const Settings(openAiApiKey: 'sk-openai-1234567890'),
      );
      expect(keyText(tester), 'sk-openai-1234567890');
      expect(find.text('OpenAI API key'), findsOneWidget);

      await tester.tap(providerSegment('Opper'));
      await tester.pumpAndSettle();
      expect(services.settingsService.settings.provider, AiProvider.opper);
      expect(find.text('Opper API key'), findsOneWidget);
      expect(keyText(tester), isEmpty);

      await tester.enterText(keyField(), 'op-secret-key');
      await tester.pump(SettingsScreen.keySaveDelay);
      await tester.pumpAndSettle();
      final saved = services.settingsService.settings;
      expect(saved.opperApiKey, 'op-secret-key');
      expect(saved.openAiApiKey, 'sk-openai-1234567890');

      await tester.tap(providerSegment('OpenAI'));
      await tester.pumpAndSettle();
      expect(services.settingsService.settings.provider, AiProvider.openai);
      expect(keyText(tester), 'sk-openai-1234567890');
      expect(services.appState.settings.opperApiKey, 'op-secret-key');
    });

    testWidgets('typed keys are saved after a pause, trimmed', (tester) async {
      final services = await pumpSettings(tester);
      await tester.enterText(keyField(), '  sk-typed-key-123  ');
      await tester.pump(const Duration(milliseconds: 100));
      expect(services.settingsService.updates, isEmpty);

      await tester.pump(SettingsScreen.keySaveDelay);
      await tester.pumpAndSettle();
      expect(services.settingsService.updates, hasLength(1));
      expect(
        services.settingsService.settings.openAiApiKey,
        'sk-typed-key-123',
      );
      expect(services.appState.isConfigured, isTrue);
    });

    testWidgets('pop waits for pending edits to be saved', (tester) async {
      usePhoneView(tester);
      final services = servicesWith();
      await services.initAppState();
      Future<void>? popped;
      String? keyWhenPopped;
      await tester.pumpWidget(
        services.wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                popped = AppRouter.openSettings(context).then((_) {
                  keyWhenPopped = services.appState.settings.openAiApiKey;
                });
              },
              child: const Text('open settings'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();

      await tester.enterText(keyField(), 'sk-fresh-key-1234567');
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await popped;

      expect(find.byType(SettingsScreen), findsNothing);
      expect(keyWhenPopped, 'sk-fresh-key-1234567');
    });

    testWidgets('a pending key is saved when leaving the screen', (
      tester,
    ) async {
      usePhoneView(tester);
      final services = servicesWith();
      await services.initAppState();
      await tester.pumpWidget(
        services.wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => AppRouter.openSettings(context),
              child: const Text('open settings'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open settings'));
      await tester.pumpAndSettle();

      await tester.enterText(keyField(), 'sk-quick-exit-key');
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsNothing);
      expect(
        services.settingsService.settings.openAiApiKey,
        'sk-quick-exit-key',
      );
    });

    testWidgets('paste fills and saves the trimmed clipboard text', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': '  sk-from-clipboard-99 \n'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final services = await pumpSettings(tester);

      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      expect(keyText(tester), 'sk-from-clipboard-99');
      expect(
        services.settingsService.settings.openAiApiKey,
        'sk-from-clipboard-99',
      );
    });

    testWidgets('show/hide toggles obscuring', (tester) async {
      await pumpSettings(
        tester,
        settings: const Settings(openAiApiKey: 'sk-hidden-123456'),
      );
      expect(tester.widget<TextField>(keyField()).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show API key'));
      await tester.pump();
      expect(tester.widget<TextField>(keyField()).obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide API key'));
      await tester.pump();
      expect(tester.widget<TextField>(keyField()).obscureText, isTrue);
    });

    testWidgets('"Get a key" opens the selected provider\'s page', (
      tester,
    ) async {
      final launched = <Uri>[];
      final original = ExternalLinks.launcher;
      ExternalLinks.launcher = (uri) async {
        launched.add(uri);
        return true;
      };
      addTearDown(() => ExternalLinks.launcher = original);

      await pumpSettings(
        tester,
        settings: const Settings(provider: AiProvider.opper),
      );
      await tester.tap(find.text('Get a key'));
      await tester.pumpAndSettle();
      expect(launched, [AiProvider.opper.apiKeyHelpUrl]);
    });

    testWidgets('a failing link shows a snackbar', (tester) async {
      final original = ExternalLinks.launcher;
      ExternalLinks.launcher = (uri) async => false;
      addTearDown(() => ExternalLinks.launcher = original);

      await pumpSettings(tester);
      await tester.tap(find.text('Get a key'));
      await tester.pump();
      expect(find.textContaining("Couldn't open"), findsOneWidget);
    });

    testWidgets('warns about an OpenAI key without "sk-"', (tester) async {
      await pumpSettings(
        tester,
        settings: const Settings(openAiApiKey: 'not-a-real-key'),
      );
      expect(find.textContaining('usually start with "sk-"'), findsOneWidget);
    });
  });

  group('verify key', () {
    testWidgets('is disabled without a key', (tester) async {
      await pumpSettings(tester);
      expect(tester.widget<OutlinedButton>(verifyButton()).enabled, isFalse);
    });

    testWidgets('shows progress, then success', (tester) async {
      final catalog = ScriptedModelCatalog()..verifyGate = Completer<void>();
      await pumpSettings(
        tester,
        catalog: catalog,
        settings: const Settings(openAiApiKey: 'sk-valid-1234567890'),
      );

      await tester.tap(verifyButton());
      await tester.pump();
      expect(find.text('Checking key…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(verifyButton()).enabled, isFalse);

      catalog.verifyGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Checking key…'), findsNothing);
      expect(find.text('Key works with OpenAI'), findsOneWidget);
      expect(catalog.verifyCalls, [(AiProvider.openai, 'sk-valid-1234567890')]);
    });

    testWidgets('shows a friendly failure message', (tester) async {
      final catalog = ScriptedModelCatalog()
        ..verifyError = const AiException(AiErrorKind.auth, 'HTTP 401');
      await pumpSettings(
        tester,
        catalog: catalog,
        settings: const Settings(
          provider: AiProvider.opper,
          opperApiKey: 'op-bad-key',
        ),
      );

      await tester.tap(verifyButton());
      await tester.pumpAndSettle();
      expect(find.textContaining('Opper rejected this key'), findsOneWidget);
      expect(catalog.verifyCalls.single, (AiProvider.opper, 'op-bad-key'));
    });

    testWidgets('network failures use the AiException message', (tester) async {
      final catalog = ScriptedModelCatalog()
        ..verifyError = const AiException(AiErrorKind.network, 'offline');
      await pumpSettings(
        tester,
        catalog: catalog,
        settings: const Settings(openAiApiKey: 'sk-offline-123456'),
      );
      await tester.tap(verifyButton());
      await tester.pumpAndSettle();
      expect(
        find.text(AiException.userMessageFor(AiErrorKind.network)),
        findsOneWidget,
      );
    });

    testWidgets('the result disappears when the key changes', (tester) async {
      await pumpSettings(
        tester,
        settings: const Settings(openAiApiKey: 'sk-valid-1234567890'),
      );
      await tester.tap(verifyButton());
      await tester.pumpAndSettle();
      expect(find.text('Key works with OpenAI'), findsOneWidget);

      await tester.enterText(keyField(), 'sk-other-1234567890');
      await tester.pump();
      expect(find.text('Key works with OpenAI'), findsNothing);
      await tester.pump(SettingsScreen.keySaveDelay);
      await tester.pumpAndSettle();
    });

    testWidgets('results are kept per provider', (tester) async {
      await pumpSettings(
        tester,
        settings: const Settings(
          openAiApiKey: 'sk-valid-1234567890',
          opperApiKey: 'op-key',
        ),
      );
      await tester.tap(verifyButton());
      await tester.pumpAndSettle();
      await tester.tap(providerSegment('Opper'));
      await tester.pumpAndSettle();
      expect(find.text('Key works with OpenAI'), findsNothing);
      await tester.tap(providerSegment('OpenAI'));
      await tester.pumpAndSettle();
      expect(find.text('Key works with OpenAI'), findsOneWidget);
    });
  });

  group('model', () {
    testWidgets('shows the selected model with capability badges', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        settings: const Settings(provider: AiProvider.opper),
      );
      expect(find.text('GPT-5 mini'), findsOneWidget);
      expect(
        find.text('openai/gpt-5-mini · OpenAI · Fast · Great quality'),
        findsOneWidget,
      );
      expect(find.text('Structured output'), findsOneWidget);
      expect(find.text('Vision'), findsOneWidget);
      expect(find.textContaining('This model'), findsNothing);
    });

    testWidgets('warns when the model lacks structured output and vision', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        settings: const Settings(
          openAiApiKey: 'sk-test-1234567890',
          openAiModel: 'gpt-3.5-turbo',
        ),
      );
      expect(find.text('No structured output'), findsOneWidget);
      expect(find.text('No vision'), findsOneWidget);
      expect(
        find.textContaining('results may be less reliable'),
        findsOneWidget,
      );
      expect(find.textContaining("photos won't work"), findsOneWidget);
    });

    testWidgets('an unknown model shows unknown capabilities, no warnings', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        settings: const Settings(
          openAiApiKey: 'sk-test-1234567890',
          openAiModel: 'my-fine-tune',
        ),
      );
      expect(find.text('my-fine-tune'), findsOneWidget);
      expect(find.text('Structured output unknown'), findsOneWidget);
      expect(find.text('Vision unknown'), findsOneWidget);
      expect(find.textContaining('This model'), findsNothing);
    });

    testWidgets('catalog failures leave capabilities unknown', (tester) async {
      final catalog = ScriptedModelCatalog(
        error: const AiException(AiErrorKind.network, 'offline'),
      );
      await pumpSettings(
        tester,
        catalog: catalog,
        settings: const Settings(openAiApiKey: 'sk-test-1234567890'),
      );
      expect(find.text('gpt-5-mini'), findsOneWidget);
      expect(find.text('Vision unknown'), findsOneWidget);
    });

    testWidgets('picking a model persists it and updates warnings', (
      tester,
    ) async {
      final services = await pumpSettings(
        tester,
        settings: const Settings(openAiApiKey: 'sk-test-1234567890'),
      );
      await tapVisible(tester, find.text('gpt-5-mini'));
      expect(find.byType(ModelPickerScreen), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);

      await tester.tap(find.text('gpt-3.5-turbo'));
      await tester.pumpAndSettle();
      expect(find.byType(ModelPickerScreen), findsNothing);
      expect(services.settingsService.settings.openAiModel, 'gpt-3.5-turbo');
      expect(services.settingsService.settings.opperModel, 'openai/gpt-5-mini');
      expect(
        find.textContaining('results may be less reliable'),
        findsOneWidget,
      );
    });

    testWidgets('looks the model up again for the new provider', (
      tester,
    ) async {
      final catalog = ScriptedModelCatalog();
      await pumpSettings(
        tester,
        catalog: catalog,
        settings: const Settings(openAiApiKey: 'sk-test-1234567890'),
      );
      expect(catalog.findCalls, ['gpt-5-mini']);
      await tester.tap(providerSegment('Opper'));
      await tester.pumpAndSettle();
      expect(catalog.findCalls, ['gpt-5-mini', 'openai/gpt-5-mini']);
      expect(find.text('GPT-5 mini'), findsOneWidget);
    });

    testWidgets('a custom model id is saved with unknown capabilities', (
      tester,
    ) async {
      final services = await pumpSettings(
        tester,
        settings: const Settings(provider: AiProvider.opper),
      );
      await tapVisible(tester, find.text('GPT-5 mini'));
      await tester.tap(find.text('Use a custom model id'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'mistral/mistral-large-3',
      );
      await tester.pump();
      await tester.tap(find.text('Use model'));
      await tester.pumpAndSettle();

      expect(
        services.settingsService.settings.opperModel,
        'mistral/mistral-large-3',
      );
      expect(find.text('mistral/mistral-large-3'), findsOneWidget);
      expect(find.text('Structured output unknown'), findsOneWidget);
    });
  });

  group('preferences', () {
    testWidgets('theme change applies instantly', (tester) async {
      final services = await pumpSettings(tester, themed: true);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(SettingsScreen))).brightness;
      expect(brightness(), Brightness.light);

      await tapVisible(tester, find.text('Dark'));
      expect(services.settingsService.settings.themeMode, AppThemeMode.dark);
      expect(brightness(), Brightness.dark);

      await tapVisible(tester, find.text('Light'));
      expect(services.settingsService.settings.themeMode, AppThemeMode.light);
      expect(brightness(), Brightness.light);
    });

    testWidgets('auto-process shared content persists', (tester) async {
      final services = await pumpSettings(tester);
      await tapVisible(tester, find.text('Auto-process shared content'));
      expect(services.settingsService.settings.autoProcessShared, isFalse);
      await tapVisible(tester, find.text('Auto-process shared content'));
      expect(services.settingsService.settings.autoProcessShared, isTrue);
    });

    testWidgets('advanced values persist', (tester) async {
      final services = await pumpSettings(tester);
      await expandAdvanced(tester);

      await tapVisible(tester, find.text('Off'));
      expect(
        services.settingsService.settings.structuredOutputMode,
        StructuredOutputMode.off,
      );

      await tapVisible(tester, find.text('Debug mode'));
      expect(services.settingsService.settings.debugMode, isTrue);

      final retries = find.descendant(
        of: find.byKey(const Key('settings_max_retries')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(retries);
      await tester.pumpAndSettle();
      final updatesBefore = services.settingsService.updates.length;
      await tester.drag(retries, const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(
        services.settingsService.settings.maxRetries,
        Settings.maxRetriesLimit,
      );
      // One save when the drag ends, not one per tick.
      expect(services.settingsService.updates.length, updatesBefore + 1);

      final timeout = find.descendant(
        of: find.byKey(const Key('settings_timeout')),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(timeout);
      await tester.pumpAndSettle();
      await tester.drag(timeout, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(
        services.settingsService.settings.timeoutSeconds,
        Settings.minTimeoutSeconds,
      );

      expect(
        find.text('Structured output off · 10 retries · 5 s timeout'),
        findsOneWidget,
      );
    });

    testWidgets('a failed save keeps the change and offers a retry', (
      tester,
    ) async {
      final services = await pumpSettings(tester);
      services.settingsService.failNextUpdate = Exception('disk full');

      await tapVisible(tester, find.text('Auto-process shared content'));
      expect(find.text("Couldn't save your changes"), findsOneWidget);
      expect(services.settingsService.settings.autoProcessShared, isTrue);
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Auto-process shared content',
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(services.settingsService.settings.autoProcessShared, isFalse);
    });
  });

  group('about', () {
    testWidgets('shows version, source link and provider-aware privacy', (
      tester,
    ) async {
      final launched = <Uri>[];
      final original = ExternalLinks.launcher;
      ExternalLinks.launcher = (uri) async {
        launched.add(uri);
        return true;
      };
      addTearDown(() => ExternalLinks.launcher = original);

      await pumpSettings(tester);
      expect(find.text('3.0.0 (42)'), findsOneWidget);
      expect(
        find.textContaining('Your text and images are sent to OpenAI'),
        findsOneWidget,
      );

      await tapVisible(tester, find.text('Source code'));
      expect(launched, [Uri.parse('https://github.com/nahu02/EventSnap2')]);

      await tapVisible(tester, providerSegment('Opper'));
      expect(
        find.textContaining('Your text and images are sent to Opper'),
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
        final services = servicesWith(
          settings: const Settings(
            openAiApiKey: 'not-sk-key',
            openAiModel: 'gpt-3.5-turbo',
          ),
        );
        usePhoneView(tester, width: 360, height: 800);
        await services.initAppState();
        await tester.pumpWidget(
          services.wrap(const SettingsScreen(), themeMode: mode),
        );
        await tester.pumpAndSettle();
        await tester.tap(verifyButton());
        await tester.pumpAndSettle();
        await expandAdvanced(tester);
        expect(tester.takeException(), isNull);

        await tapVisible(tester, find.text('gpt-3.5-turbo'));
        expect(find.byType(ModelPickerScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('icon buttons have tooltips', (tester) async {
      await pumpSettings(tester);
      for (final button in tester.widgetList<IconButton>(
        find.byType(IconButton),
      )) {
        expect(button.tooltip, isNotNull, reason: '$button');
      }
    });
  });
}
