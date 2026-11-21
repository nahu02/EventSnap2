import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_provider.dart';
import '../models/settings.dart';

/// Abstract interface for settings management
///
/// Defines the contract for storing and retrieving application settings
/// with secure handling for sensitive data like API keys.
abstract class SettingsService {
  /// Gets the current settings (defaults when nothing is stored).
  Future<Settings> getSettings();

  /// Persists [settings].
  ///
  /// Any settings with valid numeric ranges are accepted (blank keys/models
  /// are allowed so that e.g. the theme can be changed before a key is
  /// entered; use [Settings.isConfigured] / [Settings.validate] for
  /// readiness). Throws [ArgumentError] if [Settings.validateRanges] fails.
  Future<void> updateSettings(Settings settings);

  /// Clears all stored settings
  Future<void> clearSettings();

  /// Gets a specific raw setting value by storage key
  Future<String?> getSetting(String key);

  /// Updates a specific raw setting value by storage key
  Future<void> setSetting(String key, String value);

  /// Returns true if settings have been stored before
  Future<bool> hasSettings();
}

/// [SettingsService] using flutter_secure_storage (API keys) and
/// shared_preferences (everything else).
///
/// Storage format v2 (`settings_version = 2`):
/// - secure: `openai_api_key`, `opper_api_key`
/// - prefs: `ai_provider`, `openai_model`, `opper_model`, `max_retries`,
///   `timeout_seconds`, `theme_mode`, `auto_process_shared`,
///   `structured_output_mode`, `debug_mode`, `settings_version`
///
/// v1 (app 2.x) data is migrated on first load: keys keep their names, and
/// `debug_mode == true` (which used to force the dark theme) becomes
/// `theme_mode = dark`, `debug_mode = false`.
class SecureSettingsService implements SettingsService {
  SecureSettingsService({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferences,
  }) : _secureStorage = secureStorage ?? defaultSecureStorage,
       _preferences = preferences ?? SharedPreferences.getInstance;

  /// Android options for the secure store.
  ///
  /// App 2.x wrote the OpenAI key with flutter_secure_storage 9 and
  /// `AndroidOptions(encryptedSharedPreferences: true)`. flutter_secure_storage
  /// 10.x (used here) finds that Jetpack EncryptedSharedPreferences data on
  /// first access and, with `migrateOnAlgorithmChange: true`, re-encrypts it
  /// with its own AES-GCM/RSA-OAEP ciphers under the same file name and key
  /// prefix (falling back to reading the old store if migration fails).
  /// Version 11 removed that backend, so it must not be used until users have
  /// run a 10.x-based release once.
  static const AndroidOptions androidOptions = AndroidOptions(
    migrateOnAlgorithmChange: true,
  );

  /// iOS options (unchanged from 2.x so keychain items stay reachable).
  static const IOSOptions iosOptions = IOSOptions(
    groupId: 'group.com.eventsnap.app',
  );

  static const FlutterSecureStorage defaultSecureStorage = FlutterSecureStorage(
    aOptions: androidOptions,
    iOptions: iosOptions,
  );

  // Secure storage keys (sensitive data)
  static const String openAiApiKeyKey = 'openai_api_key';
  static const String opperApiKeyKey = 'opper_api_key';

  // Shared preferences keys (non-sensitive data)
  static const String providerKey = 'ai_provider';
  static const String openAiModelKey = 'openai_model';
  static const String opperModelKey = 'opper_model';
  static const String maxRetriesKey = 'max_retries';
  static const String timeoutSecondsKey = 'timeout_seconds';
  static const String themeModeKey = 'theme_mode';
  static const String autoProcessSharedKey = 'auto_process_shared';
  static const String structuredOutputModeKey = 'structured_output_mode';
  static const String debugModeKey = 'debug_mode';
  static const String settingsVersionKey = 'settings_version';

  /// Current storage format version.
  static const int currentSettingsVersion = 2;

  static const Set<String> _secureKeys = {openAiApiKeyKey, opperApiKeyKey};
  static const Set<String> _intKeys = {
    maxRetriesKey,
    timeoutSecondsKey,
    settingsVersionKey,
  };
  static const Set<String> _boolKeys = {debugModeKey, autoProcessSharedKey};
  static const List<String> _prefsKeys = [
    providerKey,
    openAiModelKey,
    opperModelKey,
    maxRetriesKey,
    timeoutSecondsKey,
    themeModeKey,
    autoProcessSharedKey,
    structuredOutputModeKey,
    debugModeKey,
    settingsVersionKey,
  ];
  static const List<String> _v1PrefsKeys = [
    openAiModelKey,
    maxRetriesKey,
    timeoutSecondsKey,
    debugModeKey,
  ];

  final FlutterSecureStorage _secureStorage;
  final Future<SharedPreferences> Function() _preferences;

  // Cache for improved performance
  Settings? _cachedSettings;
  bool _cacheValid = false;

  /// Last secret value successfully read from (or written to) secure storage.
  final Map<String, String> _loadedSecrets = {};

  /// Secret keys whose last read failed (never delete/overwrite blindly).
  final Set<String> _failedSecretReads = {};

  /// Gets the current settings from storage.
  ///
  /// Returns cached settings if available, migrates v1 data, and falls back
  /// to defaults if storage cannot be read.
  @override
  Future<Settings> getSettings() async {
    if (_cacheValid && _cachedSettings != null) {
      return _cachedSettings!;
    }

    Settings settings;
    try {
      final prefs = await _preferences();
      await _performMigrationIfNeeded(prefs);
      settings = await _loadSettings(prefs);
    } catch (e) {
      debugPrint('SecureSettingsService: failed to load settings: $e');
      settings = Settings.defaults();
    }
    _cachedSettings = settings;
    // A failed secure read must not be cached, so a later call retries.
    _cacheValid = _failedSecretReads.isEmpty;
    return settings;
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    final rangeErrors = settings.validateRanges();
    if (rangeErrors.isNotEmpty) {
      throw ArgumentError('Invalid settings: ${rangeErrors.join(', ')}');
    }

    try {
      await _persistSecret(openAiApiKeyKey, settings.openAiApiKey);
      await _persistSecret(opperApiKeyKey, settings.opperApiKey);

      final prefs = await _preferences();
      await prefs.setString(providerKey, settings.provider.id);
      await prefs.setString(openAiModelKey, settings.openAiModel);
      await prefs.setString(opperModelKey, settings.opperModel);
      await prefs.setInt(maxRetriesKey, settings.maxRetries);
      await prefs.setInt(timeoutSecondsKey, settings.timeoutSeconds);
      await prefs.setString(themeModeKey, settings.themeMode.name);
      await prefs.setBool(autoProcessSharedKey, settings.autoProcessShared);
      await prefs.setString(
        structuredOutputModeKey,
        settings.structuredOutputMode.name,
      );
      await prefs.setBool(debugModeKey, settings.debugMode);
      await prefs.setInt(settingsVersionKey, currentSettingsVersion);

      _cachedSettings = settings;
      _cacheValid = _failedSecretReads.isEmpty;
    } catch (e) {
      _cacheValid = false;
      throw Exception('Failed to update settings: $e');
    }
  }

  @override
  Future<void> clearSettings() async {
    try {
      for (final key in _secureKeys) {
        await _secureStorage.delete(key: key);
      }
      final prefs = await _preferences();
      for (final key in _prefsKeys) {
        await prefs.remove(key);
      }
      invalidateCache();
    } catch (e) {
      throw Exception('Failed to clear settings: $e');
    }
  }

  /// Raw value by storage key (bypasses the cache). Non-string preference
  /// values are returned via `toString()`.
  @override
  Future<String?> getSetting(String key) async {
    try {
      if (_secureKeys.contains(key)) {
        return await _secureStorage.read(key: key);
      }
      final prefs = await _preferences();
      return prefs.get(key)?.toString();
    } catch (e) {
      return null;
    }
  }

  /// Writes a raw value by storage key. Known int/bool keys are stored with
  /// their native type when [value] parses. Invalidates the cache.
  @override
  Future<void> setSetting(String key, String value) async {
    try {
      if (_secureKeys.contains(key)) {
        await _secureStorage.write(key: key, value: value);
        _loadedSecrets[key] = value;
        _failedSecretReads.remove(key);
      } else {
        final prefs = await _preferences();
        final asInt = _intKeys.contains(key) ? int.tryParse(value) : null;
        final asBool = _boolKeys.contains(key) ? _parseBool(value) : null;
        if (asInt != null) {
          await prefs.setInt(key, asInt);
        } else if (asBool != null) {
          await prefs.setBool(key, asBool);
        } else {
          await prefs.setString(key, value);
        }
      }
      _cacheValid = false;
    } catch (e) {
      throw Exception('Failed to set setting $key: $e');
    }
  }

  @override
  Future<bool> hasSettings() async {
    try {
      final prefs = await _preferences();
      return prefs.containsKey(settingsVersionKey);
    } catch (e) {
      return false;
    }
  }

  /// Forces the next [getSettings] call to reload from storage.
  void invalidateCache() {
    _cacheValid = false;
    _cachedSettings = null;
    _loadedSecrets.clear();
    _failedSecretReads.clear();
  }

  /// Cached settings without touching storage (null if not loaded).
  Settings? getCachedSettings() => _cacheValid ? _cachedSettings : null;

  // ---------------------------------------------------------------------------

  Future<Settings> _loadSettings(SharedPreferences prefs) async {
    const d = Settings();
    return Settings(
      provider: AiProvider.fromId(_getString(prefs, providerKey)),
      openAiApiKey: await _readSecure(openAiApiKeyKey),
      opperApiKey: await _readSecure(opperApiKeyKey),
      openAiModel:
          _nonBlank(_getString(prefs, openAiModelKey)) ?? d.openAiModel,
      opperModel: _nonBlank(_getString(prefs, opperModelKey)) ?? d.opperModel,
      maxRetries: (_getInt(prefs, maxRetriesKey) ?? d.maxRetries).clamp(
        Settings.minRetries,
        Settings.maxRetriesLimit,
      ),
      timeoutSeconds: (_getInt(prefs, timeoutSecondsKey) ?? d.timeoutSeconds)
          .clamp(Settings.minTimeoutSeconds, Settings.maxTimeoutSeconds),
      themeMode: Settings.themeModeFromName(_getString(prefs, themeModeKey)),
      autoProcessShared:
          _getBool(prefs, autoProcessSharedKey) ?? d.autoProcessShared,
      structuredOutputMode: Settings.structuredOutputModeFromName(
        _getString(prefs, structuredOutputModeKey),
      ),
      debugMode: _getBool(prefs, debugModeKey) ?? d.debugMode,
    );
  }

  /// Migrates stored v0/v1 data to v2. Fresh installs (nothing stored) are
  /// left untouched so [hasSettings] stays false until the first save.
  Future<void> _performMigrationIfNeeded(SharedPreferences prefs) async {
    final version = _getInt(prefs, settingsVersionKey);
    if (version != null && version >= currentSettingsVersion) return;

    final hasLegacyData =
        version != null || _v1PrefsKeys.any(prefs.containsKey);
    if (!hasLegacyData) return;

    // v1 had a single "debug mode" switch that also forced the dark theme.
    if (_getBool(prefs, debugModeKey) ?? false) {
      await prefs.setString(themeModeKey, AppThemeMode.dark.name);
      await prefs.setBool(debugModeKey, false);
    }
    // v1 only supported OpenAI.
    if (!prefs.containsKey(providerKey)) {
      await prefs.setString(providerKey, AiProvider.openai.id);
    }
    await prefs.setInt(settingsVersionKey, currentSettingsVersion);
  }

  Future<String> _readSecure(String key) async {
    try {
      final value = await _secureStorage.read(key: key) ?? '';
      _loadedSecrets[key] = value;
      _failedSecretReads.remove(key);
      return value;
    } catch (e) {
      debugPrint('SecureSettingsService: failed to read $key: $e');
      _failedSecretReads.add(key);
      return '';
    }
  }

  /// Writes a secret only when it differs from the last loaded value; an
  /// empty value deletes only when it replaces a loaded non-empty value.
  Future<void> _persistSecret(String key, String value) async {
    final loaded = _loadedSecrets[key];
    if (value.isEmpty) {
      if (loaded == null || loaded.isEmpty) return; // never loaded / nothing
      await _secureStorage.delete(key: key);
    } else {
      if (loaded == value) return;
      await _secureStorage.write(key: key, value: value);
    }
    _loadedSecrets[key] = value;
    _failedSecretReads.remove(key);
  }

  static String? _nonBlank(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;

  static String? _getString(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is String ? value : null;
  }

  static int? _getInt(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _getBool(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    if (value is bool) return value;
    if (value is String) return _parseBool(value);
    return null;
  }

  static bool? _parseBool(String value) => switch (value.trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  };
}
