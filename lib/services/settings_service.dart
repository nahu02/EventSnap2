import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';

/// Abstract interface for settings management
/// 
/// Defines the contract for storing and retrieving application settings
/// with secure handling for sensitive data like API keys.
abstract class SettingsService {
  /// Gets the current settings
  Future<Settings> getSettings();

  /// Updates settings with the provided values
  Future<void> updateSettings(Settings settings);

  /// Clears all stored settings
  Future<void> clearSettings();

  /// Gets a specific setting value by key
  Future<String?> getSetting(String key);

  /// Updates a specific setting value
  Future<void> setSetting(String key, String value);

  /// Returns true if settings have been initialized
  Future<bool> hasSettings();
}

/// Implementation of SettingsService using flutter_secure_storage and shared_preferences
/// 
/// Sensitive data (API keys) are stored using flutter_secure_storage for encryption.
/// Non-sensitive data uses shared_preferences for better performance.
class SecureSettingsService implements SettingsService {
  // Storage instances
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      groupId: 'group.com.eventsnap.app',
    ),
  );

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

  // Cache for improved performance
  Settings? _cachedSettings;
  bool _cacheValid = false;

  /// Gets the current settings from storage
  /// 
  /// Returns cached settings if available and valid, otherwise loads from storage.
  /// If no settings exist, returns default settings.
  @override
  Future<Settings> getSettings() async {
    // Return cached settings if valid
    if (_cacheValid && _cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      // Check if we need to perform migration
      await _performMigrationIfNeeded();

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

  /// Updates settings with the provided values
  /// 
  /// Validates settings before storing and updates both secure and shared storage.
  /// Invalidates cache after successful update.
  @override
  Future<void> updateSettings(Settings settings) async {
    // Validate settings before storing
    final validationErrors = settings.validate();
    if (validationErrors.isNotEmpty) {
      throw ArgumentError('Invalid settings: ${validationErrors.join(', ')}');
    }

    try {
      // Store sensitive data in secure storage
      await _secureStorage.write(key: _apiKeyKey, value: settings.openAiApiKey);

      // Store non-sensitive data in shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelKey, settings.openAiModel);
      await prefs.setInt(_maxRetriesKey, settings.maxRetries);
      await prefs.setInt(_timeoutSecondsKey, settings.timeoutSeconds);
      await prefs.setBool(_debugModeKey, settings.debugMode);
      await prefs.setInt(_settingsVersionKey, _currentSettingsVersion);

      // Update cache
      _cachedSettings = settings;
      _cacheValid = true;
    } catch (e) {
      // Invalidate cache on error
      _cacheValid = false;
      throw Exception('Failed to update settings: $e');
    }
  }

  /// Clears all stored settings
  /// 
  /// Removes all data from both secure storage and shared preferences.
  /// Invalidates cache after clearing.
  @override
  Future<void> clearSettings() async {
    try {
      // Clear secure storage
      await _secureStorage.delete(key: _apiKeyKey);

      // Clear shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_modelKey);
      await prefs.remove(_maxRetriesKey);
      await prefs.remove(_timeoutSecondsKey);
      await prefs.remove(_debugModeKey);
      await prefs.remove(_settingsVersionKey);

      // Invalidate cache
      _cachedSettings = null;
      _cacheValid = false;
    } catch (e) {
      throw Exception('Failed to clear settings: $e');
    }
  }

  /// Gets a specific setting value by key
  /// 
  /// Returns null if the setting doesn't exist.
  /// Note: This method bypasses the cache for real-time values.
  @override
  Future<String?> getSetting(String key) async {
    try {
      switch (key) {
        case _apiKeyKey:
          return await _secureStorage.read(key: key);
        default:
          final prefs = await SharedPreferences.getInstance();
          return prefs.getString(key);
      }
    } catch (e) {
      return null;
    }
  }

  /// Updates a specific setting value
  /// 
  /// Invalidates cache after update to ensure consistency.
  @override
  Future<void> setSetting(String key, String value) async {
    try {
      switch (key) {
        case _apiKeyKey:
          await _secureStorage.write(key: key, value: value);
          break;
        default:
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(key, value);
          break;
      }
      
      // Invalidate cache since individual setting was updated
      _cacheValid = false;
    } catch (e) {
      throw Exception('Failed to set setting $key: $e');
    }
  }

  /// Returns true if settings have been initialized
  /// 
  /// Checks if at least the settings version exists in storage.
  @override
  Future<bool> hasSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_settingsVersionKey);
    } catch (e) {
      return false;
    }
  }

  /// Loads settings from storage
  /// 
  /// Combines data from secure storage and shared preferences to create
  /// a complete Settings object.
  Future<Settings> _loadSettingsFromStorage() async {
    // Load sensitive data from secure storage
    final apiKey = await _secureStorage.read(key: _apiKeyKey) ?? '';

    // Load non-sensitive data from shared preferences
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString(_modelKey) ?? 'gpt-4.1';
    final maxRetries = prefs.getInt(_maxRetriesKey) ?? 3;
    final timeoutSeconds = prefs.getInt(_timeoutSecondsKey) ?? 30;
    final debugMode = prefs.getBool(_debugModeKey) ?? false;

    return Settings(
      openAiApiKey: apiKey,
      openAiModel: model,
      maxRetries: maxRetries,
      timeoutSeconds: timeoutSeconds,
      debugMode: debugMode,
      validateOnCreation: false, // Don't validate during loading
    );
  }

  /// Performs settings migration if needed
  /// 
  /// Checks the current settings version and performs any necessary
  /// data migrations for backwards compatibility.
  Future<void> _performMigrationIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentVersion = prefs.getInt(_settingsVersionKey) ?? 0;

      if (currentVersion < _currentSettingsVersion) {
        await _migrateSettings(currentVersion, _currentSettingsVersion);
        await prefs.setInt(_settingsVersionKey, _currentSettingsVersion);
      }
    } catch (e) {
      // Migration errors are non-fatal, settings will use defaults
      throw Exception('Settings migration failed: $e');
    }
  }

  /// Migrates settings from one version to another
  /// 
  /// Currently handles migration from version 0 (no version) to version 1.
  /// Future versions can add additional migration logic here.
  Future<void> _migrateSettings(int fromVersion, int toVersion) async {
    // Currently no migrations needed, but this is where future
    // migration logic would go
    
    // Example migration logic:
    // if (fromVersion == 0 && toVersion >= 1) {
    //   // Migrate from legacy storage format
    //   await _migrateLegacySettings();
    // }
  }

  /// Invalidates the settings cache
  /// 
  /// Forces the next call to getSettings() to reload from storage.
  /// Useful for testing or when external changes are made to storage.
  void invalidateCache() {
    _cacheValid = false;
    _cachedSettings = null;
  }

  /// Gets cached settings without accessing storage
  /// 
  /// Returns null if cache is invalid or empty.
  /// Useful for performance-critical scenarios where you want to avoid async calls.
  Settings? getCachedSettings() {
    return _cacheValid ? _cachedSettings : null;
  }
}
