import 'package:event_snap_2/models/ai_provider.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/settings_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureSettingsService service;

  /// Fresh service over mocked secure storage + shared preferences.
  SecureSettingsService createService({
    Map<String, String> secure = const {},
    Map<String, Object> prefs = const {},
  }) {
    FlutterSecureStorage.setMockInitialValues(Map.of(secure));
    SharedPreferences.setMockInitialValues(Map.of(prefs));
    return SecureSettingsService();
  }

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  setUp(() {
    service = createService();
  });

  group('secure storage configuration', () {
    test('migrates EncryptedSharedPreferences data from app 2.x', () {
      final options = SecureSettingsService.androidOptions.toMap();
      expect(options['migrateOnAlgorithmChange'], 'true');
      // Same file and key prefix as flutter_secure_storage 9 used.
      expect(options['sharedPreferencesName'] ?? '', isEmpty);
      expect(options['preferencesKeyPrefix'] ?? '', isEmpty);
      expect(options['storageNamespace'] ?? '', isEmpty);
    });

    test('keeps the iOS keychain group of app 2.x', () {
      expect(
        SecureSettingsService.iosOptions.toMap()['groupId'],
        'group.com.eventsnap.app',
      );
    });
  });

  group('fresh install', () {
    test('returns defaults and does not mark settings as stored', () async {
      final settings = await service.getSettings();
      expect(settings, Settings.defaults());
      expect(await service.hasSettings(), isFalse);
      expect((await prefs()).getKeys(), isEmpty);
    });
  });

  group('v1 -> v2 migration', () {
    test('keeps the stored OpenAI key, model, retries and timeout', () async {
      service = createService(
        secure: {'openai_api_key': 'sk-legacy-1234567890'},
        prefs: {
          'openai_model': 'gpt-4.1',
          'max_retries': 3,
          'timeout_seconds': 30,
          'debug_mode': false,
          'settings_version': 1,
        },
      );

      final settings = await service.getSettings();

      expect(settings.provider, AiProvider.openai);
      expect(settings.openAiApiKey, 'sk-legacy-1234567890');
      expect(settings.openAiModel, 'gpt-4.1');
      expect(settings.maxRetries, 3);
      expect(settings.timeoutSeconds, 30);
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.debugMode, isFalse);
      expect(settings.opperApiKey, '');
      expect(settings.opperModel, AiProvider.opper.defaultModel);
      expect(settings.autoProcessShared, isTrue);
      expect(settings.structuredOutputMode, StructuredOutputMode.auto);
      expect(settings.isConfigured, isTrue);

      final p = await prefs();
      expect(p.getInt('settings_version'), 2);
      expect(p.getString('ai_provider'), 'openai');
    });

    test('debug_mode=true becomes dark theme with debug off', () async {
      service = createService(
        secure: {'openai_api_key': 'sk-legacy-1234567890'},
        prefs: {
          'openai_model': 'gpt-4.1-mini',
          'max_retries': 3,
          'timeout_seconds': 30,
          'debug_mode': true,
          'settings_version': 1,
        },
      );

      final settings = await service.getSettings();

      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.debugMode, isFalse);
      final p = await prefs();
      expect(p.getString('theme_mode'), 'dark');
      expect(p.getBool('debug_mode'), isFalse);
    });

    test('migrates v1 data written without a version (v0)', () async {
      service = createService(
        prefs: {'openai_model': 'gpt-4o', 'debug_mode': true},
      );
      final settings = await service.getSettings();
      expect(settings.openAiModel, 'gpt-4o');
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.debugMode, isFalse);
      expect(await service.hasSettings(), isTrue);
    });

    test('migration runs only once', () async {
      service = createService(
        prefs: {'debug_mode': true, 'settings_version': 1},
      );
      await service.getSettings();
      // The user now explicitly enables debug mode in v2.
      await service.updateSettings(
        (await service.getSettings()).copyWith(debugMode: true),
      );
      final reloaded = SecureSettingsService();
      final settings = await reloaded.getSettings();
      expect(settings.debugMode, isTrue);
      expect(settings.themeMode, AppThemeMode.dark);
    });

    test('v1 values stored as strings are still read', () async {
      service = createService(
        prefs: {
          'max_retries': '4',
          'timeout_seconds': 'abc',
          'debug_mode': 'false',
          'settings_version': '1',
        },
      );
      final settings = await service.getSettings();
      expect(settings.maxRetries, 4);
      expect(settings.timeoutSeconds, Settings.defaultTimeoutSeconds);
      expect(settings.debugMode, isFalse);
    });

    test('out-of-range stored values are clamped', () async {
      service = createService(
        prefs: {'max_retries': 99, 'timeout_seconds': 1, 'settings_version': 2},
      );
      final settings = await service.getSettings();
      expect(settings.maxRetries, 10);
      expect(settings.timeoutSeconds, 5);
    });
  });

  group('v2 persistence', () {
    const full = Settings(
      provider: AiProvider.opper,
      openAiApiKey: 'sk-test1234567890abcdef',
      opperApiKey: 'op-key-1234567890',
      openAiModel: 'gpt-5',
      opperModel: 'anthropic/claude-sonnet-5-5',
      maxRetries: 4,
      timeoutSeconds: 120,
      themeMode: AppThemeMode.light,
      autoProcessShared: false,
      structuredOutputMode: StructuredOutputMode.off,
      debugMode: true,
    );

    test('round-trips every field through storage', () async {
      await service.updateSettings(full);
      final reloaded = SecureSettingsService();
      expect(await reloaded.getSettings(), full);
    });

    test('writes the documented keys', () async {
      await service.updateSettings(full);
      final p = await prefs();
      expect(p.getString('ai_provider'), 'opper');
      expect(p.getString('openai_model'), 'gpt-5');
      expect(p.getString('opper_model'), 'anthropic/claude-sonnet-5-5');
      expect(p.getInt('max_retries'), 4);
      expect(p.getInt('timeout_seconds'), 120);
      expect(p.getString('theme_mode'), 'light');
      expect(p.getBool('auto_process_shared'), isFalse);
      expect(p.getString('structured_output_mode'), 'off');
      expect(p.getBool('debug_mode'), isTrue);
      expect(p.getInt('settings_version'), 2);
      // API keys never go to shared preferences.
      expect(p.getKeys().any((k) => k.contains('api_key')), isFalse);
      expect(await service.getSetting('openai_api_key'), full.openAiApiKey);
      expect(await service.getSetting('opper_api_key'), full.opperApiKey);
    });

    test('allows saving without API keys (e.g. theme before setup)', () async {
      await service.updateSettings(
        Settings.defaults().copyWith(themeMode: AppThemeMode.dark),
      );
      final reloaded = SecureSettingsService();
      final settings = await reloaded.getSettings();
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.isConfigured, isFalse);
      expect(await service.hasSettings(), isTrue);
    });

    test('empty keys are deleted from secure storage', () async {
      await service.updateSettings(full);
      await service.updateSettings(full.copyWith(opperApiKey: ''));
      expect(await service.getSetting('opper_api_key'), isNull);
      expect(await service.getSetting('openai_api_key'), full.openAiApiKey);
    });

    test('rejects out-of-range values', () async {
      expect(
        () => service.updateSettings(const Settings(maxRetries: 15)),
        throwsArgumentError,
      );
      expect(
        () => service.updateSettings(const Settings(timeoutSeconds: 500)),
        throwsArgumentError,
      );
    });

    test('caches loaded settings', () async {
      await service.updateSettings(full);
      final a = await service.getSettings();
      final b = await service.getSettings();
      expect(identical(a, b), isTrue);
      expect(service.getCachedSettings(), full);
      service.invalidateCache();
      expect(service.getCachedSettings(), isNull);
      expect(await service.getSettings(), full);
    });

    test('clearSettings removes everything', () async {
      await service.updateSettings(full);
      await service.clearSettings();
      expect(await service.hasSettings(), isFalse);
      expect(await service.getSetting('openai_api_key'), isNull);
      expect(await service.getSetting('opper_api_key'), isNull);
      expect((await prefs()).getKeys(), isEmpty);
      expect(await service.getSettings(), Settings.defaults());
    });
  });

  group('individual settings', () {
    test('get/set arbitrary string keys', () async {
      await service.setSetting('test-key', 'test-value');
      expect(await service.getSetting('test-key'), 'test-value');
      expect(await service.getSetting('missing'), isNull);
    });

    test('typed keys keep their native type', () async {
      await service.setSetting('max_retries', '5');
      await service.setSetting('auto_process_shared', 'false');
      final p = await prefs();
      expect(p.getInt('max_retries'), 5);
      expect(p.getBool('auto_process_shared'), isFalse);
      expect(await service.getSetting('max_retries'), '5');
    });

    test('API keys go to secure storage', () async {
      await service.setSetting('opper_api_key', 'op-123');
      expect(await service.getSetting('opper_api_key'), 'op-123');
      expect((await prefs()).containsKey('opper_api_key'), isFalse);
    });

    test('setSetting invalidates the cache', () async {
      await service.updateSettings(
        const Settings(openAiApiKey: 'sk-initial123'),
      );
      await service.getSettings();
      await service.setSetting('openai_model', 'gpt-4.1');
      expect((await service.getSettings()).openAiModel, 'gpt-4.1');
    });
  });
}
