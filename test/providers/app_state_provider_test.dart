import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/providers/app_state_provider.dart';
import 'package:event_snap_2/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fakes.dart';

class _ThrowingSettingsService extends InMemorySettingsService {
  @override
  Future<Settings> getSettings() async => throw Exception('storage broken');
}

void main() {
  group('AppStateProvider', () {
    test('starts with defaults and not initialized', () {
      final state = AppStateProvider(
        settingsService: InMemorySettingsService(),
      );
      expect(state.isInitialized, isFalse);
      expect(state.settings, Settings.defaults());
      expect(state.isConfigured, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.themeMode, ThemeMode.system);
    });

    test('initialize loads settings and notifies', () async {
      const stored = Settings(
        openAiApiKey: 'sk-123456789',
        themeMode: AppThemeMode.dark,
      );
      final state = AppStateProvider(
        settingsService: InMemorySettingsService(stored),
      );
      var notified = 0;
      state.addListener(() => notified++);
      await state.initialize();
      expect(state.isInitialized, isTrue);
      expect(state.settings, stored);
      expect(state.isConfigured, isTrue);
      expect(state.themeMode, ThemeMode.dark);
      expect(notified, greaterThan(0));
    });

    test('initialize failure sets an error but still initializes', () async {
      final state = AppStateProvider(
        settingsService: _ThrowingSettingsService(),
      );
      await state.initialize();
      expect(state.isInitialized, isTrue);
      expect(state.errorMessage, contains('storage broken'));
      expect(state.settings, Settings.defaults());
      state.clearError();
      expect(state.errorMessage, isNull);
    });

    test('themeMode maps every AppThemeMode', () async {
      final service = InMemorySettingsService();
      final state = AppStateProvider(settingsService: service);
      final expected = {
        AppThemeMode.system: ThemeMode.system,
        AppThemeMode.light: ThemeMode.light,
        AppThemeMode.dark: ThemeMode.dark,
      };
      for (final entry in expected.entries) {
        await state.updateSettings(
          Settings.defaults().copyWith(themeMode: entry.key),
        );
        expect(state.themeMode, entry.value);
      }
    });

    test('updateSettings persists and applies', () async {
      final service = InMemorySettingsService();
      final state = AppStateProvider(settingsService: service);
      await state.initialize();
      const updated = Settings(openAiApiKey: 'sk-abcdefghijk');
      await state.updateSettings(updated);
      expect(state.settings, updated);
      expect(service.settings, updated);
      expect(state.isConfigured, isTrue);
    });

    test('updateSettings failure keeps old settings and rethrows', () async {
      final service = InMemorySettingsService()
        ..failNextUpdate = Exception('disk full');
      final state = AppStateProvider(settingsService: service);
      await state.initialize();
      await expectLater(
        state.updateSettings(const Settings(openAiApiKey: 'sk-abcdefghijk')),
        throwsException,
      );
      expect(state.settings, Settings.defaults());
      expect(state.errorMessage, contains('disk full'));
    });

    test('accepts any SettingsService implementation', () {
      SettingsService service = InMemorySettingsService();
      expect(AppStateProvider(settingsService: service), isA<ChangeNotifier>());
    });

    test(
      'api key lost notice shows after initialize and can be dismissed',
      () async {
        final state = AppStateProvider(
          settingsService: InMemorySettingsService(null, true),
        );
        expect(state.showApiKeyLostNotice, isFalse);
        await state.initialize();
        expect(state.showApiKeyLostNotice, isTrue);
        var notified = 0;
        state.addListener(() => notified++);
        state.dismissApiKeyLostNotice();
        expect(state.showApiKeyLostNotice, isFalse);
        expect(notified, 1);
      },
    );

    test('no notice when nothing was lost', () async {
      final state = AppStateProvider(
        settingsService: InMemorySettingsService(),
      );
      await state.initialize();
      expect(state.showApiKeyLostNotice, isFalse);
    });
  });
}
