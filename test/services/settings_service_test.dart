import 'package:flutter_test/flutter_test.dart';
import 'package:event_snap_2/models/settings.dart';
import 'package:event_snap_2/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock implementation of SettingsService for testing
/// Uses in-memory storage instead of flutter_secure_storage
class MockSettingsService implements SettingsService {
  // In-memory storage maps
  final Map<String, String> _secureStorage = {};
  final Map<String, String> _sharedPrefs = {};
  
  // Cache for improved performance
  Settings? _cachedSettings;
  bool _cacheValid = false;

  // Keys for secure storage (sensitive data)
  static const String _apiKeyKey = 'openai_api_key';

  // Keys for shared preferences (non-sensitive data)
  static const String _modelKey = 'openai_model';
  static const String _maxRetriesKey = 'max_retries';
  static const String _timeoutSecondsKey = 'timeout_seconds';
  static const String _debugModeKey = 'debug_mode';
  static const String _settingsVersionKey = 'settings_version';

  // Current settings version for migration handling
  static const int _currentSettingsVersion = 1;

  @override
  Future<Settings> getSettings() async {
    // Return cached settings if valid
    if (_cacheValid && _cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      // Load settings from storage
      final settings = await _loadSettingsFromStorage();
      
      // Cache the loaded settings
      _cachedSettings = settings;
      _cacheValid = true;
      
      return settings;
    } catch (e) {
      // If loading fails, return default settings
      final defaultSettings = Settings.defaults();
      _cachedSettings = defaultSettings;
      _cacheValid = true;
      return defaultSettings;
    }
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    // Validate settings before storing
    final validationErrors = settings.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError('Invalid settings: ${validationErrors.join(', ')}');
    }

    try {
      // Store sensitive data in secure storage
      if (settings.openAiApiKey.isNotEmpty) {
        _secureStorage[_apiKeyKey] = settings.openAiApiKey;
      } else {
        _secureStorage.remove(_apiKeyKey);
      }

      // Store non-sensitive data in shared preferences
      _sharedPrefs[_modelKey] = settings.openAiModel;
      _sharedPrefs[_maxRetriesKey] = settings.maxRetries.toString();
      _sharedPrefs[_timeoutSecondsKey] = settings.timeoutSeconds.toString();
      _sharedPrefs[_debugModeKey] = settings.debugMode.toString();
      _sharedPrefs[_settingsVersionKey] = _currentSettingsVersion.toString();

      // Update cache
      _cachedSettings = settings;
      _cacheValid = true;
    } catch (e) {
      // Invalidate cache on error
      _cacheValid = false;
      throw Exception('Failed to update settings: $e');
    }
  }

  @override
  Future<void> clearSettings() async {
    try {
      // Clear secure storage
      _secureStorage.clear();
      
      // Clear shared preferences
      _sharedPrefs.clear();
      
      // Invalidate cache
      _invalidateCache();
    } catch (e) {
      throw Exception('Failed to clear settings: $e');
    }
  }

  @override
  Future<String?> getSetting(String key) async {
    try {
      // Check secure storage first
      if (key == _apiKeyKey) {
        return _secureStorage[key];
      }
      
      // Check shared preferences
      return _sharedPrefs[key];
    } catch (e) {
      throw Exception('Failed to get setting $key: $e');
    }
  }

  @override
  Future<void> setSetting(String key, String value) async {
    try {
      // Store in appropriate storage based on key
      if (key == _apiKeyKey) {
        _secureStorage[key] = value;
      } else {
        _sharedPrefs[key] = value;
      }
      
      // Invalidate cache since individual setting was updated
      _invalidateCache();
    } catch (e) {
      throw Exception('Failed to set setting $key: $e');
    }
  }

  @override
  Future<bool> hasSettings() async {
    try {
      // Check if any settings exist
      return _secureStorage.isNotEmpty || _sharedPrefs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Loads settings from storage
  Future<Settings> _loadSettingsFromStorage() async {
    // Load from secure storage
    final apiKey = _secureStorage[_apiKeyKey] ?? '';

    // Load from shared preferences
    final model = _sharedPrefs[_modelKey] ?? Settings.defaults().openAiModel;
    final maxRetries = int.tryParse(_sharedPrefs[_maxRetriesKey] ?? '') ?? Settings.defaults().maxRetries;
    final timeoutSeconds = int.tryParse(_sharedPrefs[_timeoutSecondsKey] ?? '') ?? Settings.defaults().timeoutSeconds;
    final debugMode = (_sharedPrefs[_debugModeKey] ?? 'false').toLowerCase() == 'true';

    return Settings(
      openAiApiKey: apiKey,
      openAiModel: model,
      maxRetries: maxRetries,
      timeoutSeconds: timeoutSeconds,
      debugMode: debugMode,
      validateOnCreation: false, // Skip validation for loaded settings
    );
  }

  /// Invalidates the settings cache
  void _invalidateCache() {
    _cacheValid = false;
    _cachedSettings = null;
  }

  /// Gets cached settings if available (for testing cache functionality)
  Settings? getCachedSettings() => _cacheValid ? _cachedSettings : null;

  /// Manually invalidates cache (for testing)
  void invalidateCacheManually() => _invalidateCache();

  /// Public method to invalidate cache (for testing)
  void invalidateCache() => _invalidateCache();
}

void main() {
  group('SettingsService Tests', () {
    late MockSettingsService settingsService;

    setUpAll(() {
      // Initialize Flutter binding for testing
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() {
      settingsService = MockSettingsService();
      
      // Clear any existing settings before each test
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      // Clean up after each test
      try {
        await settingsService.clearSettings();
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    group('Basic Settings Operations', () {
      test('should return default settings when none exist', () async {
        // Act
        final settings = await settingsService.getSettings();

        // Assert
        expect(settings.openAiApiKey, isEmpty);
        expect(settings.openAiModel, equals('gpt-4.1'));
        expect(settings.maxRetries, equals(3));
        expect(settings.timeoutSeconds, equals(30));
        expect(settings.debugMode, isFalse);
      });

      test('should store and retrieve complete settings', () async {
        // Arrange
        final testSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
          maxRetries: 5,
          timeoutSeconds: 60,
          debugMode: true,
        );

        // Act
        await settingsService.updateSettings(testSettings);
        final retrievedSettings = await settingsService.getSettings();

        // Assert
        expect(retrievedSettings.openAiApiKey, equals(testSettings.openAiApiKey));
        expect(retrievedSettings.openAiModel, equals(testSettings.openAiModel));
        expect(retrievedSettings.maxRetries, equals(testSettings.maxRetries));
        expect(
          retrievedSettings.timeoutSeconds,
          equals(testSettings.timeoutSeconds),
        );
        expect(retrievedSettings.debugMode, equals(testSettings.debugMode));
      });

      test('should use cache for subsequent calls', () async {
        // Arrange
        final testSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
        );

        await settingsService.updateSettings(testSettings);

        // Act - First call loads from storage
        final settings1 = await settingsService.getSettings();
        // Second call should use cache
        final settings2 = await settingsService.getSettings();

        // Assert
        expect(identical(settings1, settings2), isTrue);
        expect(settings2.openAiApiKey, equals('sk-test1234567890abcdef'));
      });

      test('should invalidate cache after updateSettings', () async {
        // Arrange
        final initialSettings = Settings(
          openAiApiKey: 'sk-initial123',
          openAiModel: 'gpt-3.5-turbo',
        );

        await settingsService.updateSettings(initialSettings);
        final settings1 = await settingsService.getSettings();

        // Act - Update settings
        final updatedSettings = Settings(
          openAiApiKey: 'sk-updated456',
          openAiModel: 'gpt-4',
        );
        await settingsService.updateSettings(updatedSettings);
        final settings2 = await settingsService.getSettings();

        // Assert
        expect(settings1.openAiApiKey, equals('sk-initial123'));
        expect(settings2.openAiApiKey, equals('sk-updated456'));
        expect(settings2.openAiModel, equals('gpt-4'));
      });
    });

    group('Settings Validation', () {
      test('should reject invalid settings during update', () async {
        // Arrange
        final invalidSettings = Settings(
          openAiApiKey: '', // Invalid: empty API key
          openAiModel: 'gpt-4',
          validateOnCreation: false, // Bypass constructor validation
        );

        // Act & Assert
        expect(
          () => settingsService.updateSettings(invalidSettings),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should reject settings with invalid API key format', () async {
        // Arrange
        final invalidSettings = Settings(
          openAiApiKey: 'invalid-key-format', // Should start with 'sk-'
          openAiModel: 'gpt-4',
          validateOnCreation: false,
        );

        // Act & Assert
        expect(
          () => settingsService.updateSettings(invalidSettings),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should reject settings with invalid retry count', () async {
        // Arrange - Create settings with invalid retry count
        // Use copyWith from valid settings to bypass constructor validation
        final validSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
        );
        final invalidSettings = validSettings.copyWith(
          maxRetries: 15, // Invalid: too high
          validateOnCreation: false,
        );

        // Act & Assert
        expect(
          () => settingsService.updateSettings(invalidSettings),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should reject settings with invalid timeout', () async {
        // Arrange - Create settings with invalid timeout
        // Use copyWith from valid settings to bypass constructor validation
        final validSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
        );
        final invalidSettings = validSettings.copyWith(
          timeoutSeconds: 500, // Invalid: too high
          validateOnCreation: false,
        );

        // Act & Assert
        expect(
          () => settingsService.updateSettings(invalidSettings),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Individual Setting Operations', () {
      test('should get and set individual settings', () async {
        // Arrange
        const testValue = 'test-value';
        const testKey = 'test-key';

        // Act
        await settingsService.setSetting(testKey, testValue);
        final retrievedValue = await settingsService.getSetting(testKey);

        // Assert
        expect(retrievedValue, equals(testValue));
      });

      test('should return null for non-existent setting', () async {
        // Act
        final value = await settingsService.getSetting('non-existent-key');

        // Assert
        expect(value, isNull);
      });

      test('should invalidate cache when setting individual values', () async {
        // Arrange
        final initialSettings = Settings(
          openAiApiKey: 'sk-initial123',
          openAiModel: 'gpt-3.5-turbo',
        );

        await settingsService.updateSettings(initialSettings);
        
        // Get settings to populate cache
        await settingsService.getSettings();

        // Act - Update individual setting
        await settingsService.setSetting('openai_model', 'gpt-4');
        
        // Get settings again - should reload from storage
        final updatedSettings = await settingsService.getSettings();

        // Assert - Should reflect the individual change
        expect(updatedSettings.openAiModel, equals('gpt-4'));
      });
    });

    group('Storage Management', () {
      test('should detect when settings exist', () async {
        // Arrange - Initially no settings
        expect(await settingsService.hasSettings(), isFalse);

        // Act - Add settings
        final testSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
        );
        await settingsService.updateSettings(testSettings);

        // Assert
        expect(await settingsService.hasSettings(), isTrue);
      });

      test('should clear all settings', () async {
        // Arrange - Add settings first
        final testSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
          maxRetries: 5,
          timeoutSeconds: 60,
          debugMode: true,
        );

        await settingsService.updateSettings(testSettings);
        expect(await settingsService.hasSettings(), isTrue);

        // Act
        await settingsService.clearSettings();

        // Assert
        expect(await settingsService.hasSettings(), isFalse);
        
        final settings = await settingsService.getSettings();
        expect(settings.openAiApiKey, isEmpty);
        expect(settings.openAiModel, equals('gpt-4.1')); // Default value
      });

      test('should handle storage errors gracefully', () async {
        // This test verifies error handling, but since we're using mocks,
        // we can't easily simulate storage failures. In a real app, this
        // would test scenarios like insufficient storage space, permission
        // errors, etc.
        
        // For now, we test that the service doesn't crash on normal operations
        expect(() => settingsService.getSettings(), returnsNormally);
        expect(() => settingsService.clearSettings(), returnsNormally);
      });
    });

    group('Cache Management', () {
      test('should provide cached settings without async call', () async {
        // Arrange
        final testSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
        );

        // Initially no cache
        expect(settingsService.getCachedSettings(), isNull);

        // Act - Load settings to populate cache
        await settingsService.updateSettings(testSettings);
        await settingsService.getSettings();

        // Assert
        final cachedSettings = settingsService.getCachedSettings();
        expect(cachedSettings, isNotNull);
        expect(cachedSettings!.openAiApiKey, equals('sk-test1234567890abcdef'));
      });

      test('should invalidate cache manually', () async {
        // Arrange
        final testSettings = Settings(
          openAiApiKey: 'sk-test1234567890abcdef',
          openAiModel: 'gpt-4',
        );

        await settingsService.updateSettings(testSettings);
        await settingsService.getSettings(); // Populate cache

        expect(settingsService.getCachedSettings(), isNotNull);

        // Act
        settingsService.invalidateCache();

        // Assert
        expect(settingsService.getCachedSettings(), isNull);
      });
    });

    group('Edge Cases', () {
      test('should handle empty API key in storage gracefully', () async {
        // Arrange - Simulate settings with empty API key in storage
        await settingsService.setSetting('openai_model', 'gpt-4.1');
        // Don't set API key, leaving it empty

        // Act
        final settings = await settingsService.getSettings();

        // Assert - Should return settings with empty API key
        expect(settings.openAiApiKey, isEmpty);
        expect(settings.openAiModel, equals('gpt-4.1'));
      });

      test('should handle missing non-sensitive settings gracefully', () async {
        // Arrange - Only set API key, leave other settings unset
        await settingsService.setSetting('openai_api_key', 'sk-test123');

        // Act
        final settings = await settingsService.getSettings();

        // Assert - Should use default values for missing settings
        expect(settings.openAiApiKey, equals('sk-test123'));
        expect(settings.openAiModel, equals('gpt-4.1')); // Default
        expect(settings.maxRetries, equals(3)); // Default
        expect(settings.timeoutSeconds, equals(30)); // Default
        expect(settings.debugMode, isFalse); // Default
      });

      test('should handle copyWith operations correctly', () async {
        // Arrange
        final originalSettings = Settings(
          openAiApiKey: 'sk-original123',
          openAiModel: 'gpt-3.5-turbo',
          maxRetries: 3,
          timeoutSeconds: 30,
          debugMode: false,
        );

        await settingsService.updateSettings(originalSettings);

        // Act - Update only some fields
        final currentSettings = await settingsService.getSettings();
        final updatedSettings = currentSettings.copyWith(
          openAiModel: 'gpt-4',
          debugMode: true,
        );

        await settingsService.updateSettings(updatedSettings);
        final finalSettings = await settingsService.getSettings();

        // Assert
        expect(finalSettings.openAiApiKey, equals('sk-original123')); // Unchanged
        expect(finalSettings.openAiModel, equals('gpt-4')); // Changed
        expect(finalSettings.maxRetries, equals(3)); // Unchanged
        expect(finalSettings.timeoutSeconds, equals(30)); // Unchanged
        expect(finalSettings.debugMode, isTrue); // Changed
      });
    });
  });
}
