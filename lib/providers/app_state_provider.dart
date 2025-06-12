import 'package:flutter/material.dart';
import '../models/settings.dart';
import '../models/event_model.dart';
import '../services/settings_service.dart';

/// Main application state provider
///
/// Manages global app state including settings, current event, theme mode,
/// and loading states across the application.
class AppStateProvider extends ChangeNotifier {
  final SettingsService _settingsService;

  // State variables
  Settings? _settings;
  List<EventModel> _currentEvents = []; // New list to hold multiple events
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = false;
  String? _errorMessage;

  // Constructor
  AppStateProvider({required SettingsService settingsService})
    : _settingsService = settingsService;

  // Getters
  Settings? get settings => _settings;
  List<EventModel> get currentEvents =>
      _currentEvents; // Getter for the list of events
  EventModel? get currentEvent => _currentEvents.isNotEmpty
      ? _currentEvents.first
      : null; // Keep for compatibility if needed, or remove if fully refactored
  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasSettings => _settings != null;
  bool get isConfigured =>
      _settings != null && _settings!.openAiApiKey.isNotEmpty;

  /// Initialize the app state
  ///
  /// Loads settings from storage and initializes theme mode.
  /// Should be called during app startup.
  Future<void> initialize() async {
    _setLoading(true);
    _clearError();

    try {
      // Load settings
      _settings = await _settingsService.getSettings();

      // Set theme mode based on settings
      _themeMode = _settings!.debugMode ? ThemeMode.dark : ThemeMode.system;

      notifyListeners();
    } catch (e) {
      _setError('Failed to initialize app: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Update app settings
  ///
  /// Updates both local state and persistent storage.
  Future<void> updateSettings(Settings newSettings) async {
    _setLoading(true);
    _clearError();

    try {
      await _settingsService.updateSettings(newSettings);
      _settings = newSettings;

      // Update theme mode if debug mode changed
      _themeMode = newSettings.debugMode ? ThemeMode.dark : ThemeMode.system;

      notifyListeners();
    } catch (e) {
      _setError('Failed to update settings: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Set the current event being processed
  void setCurrentEvent(EventModel? event) {
    if (event != null) {
      _currentEvents = [event]; // Replace list with the single event
    } else {
      _currentEvents = []; // Clear list if event is null
    }
    _clearError();
    notifyListeners();
  }

  /// Set the current list of events being processed
  void setCurrentEvents(List<EventModel> events) {
    _currentEvents = events;
    _clearError();
    notifyListeners();
  }

  /// Clear the current event
  void clearCurrentEvent() {
    _currentEvents = []; // Clear the list of events
    _clearError();
    notifyListeners();
  }

  /// Clear all current events
  void clearCurrentEvents() {
    _currentEvents = [];
    _clearError();
    notifyListeners();
  }

  /// Set theme mode
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  /// Toggle between light, dark, and system theme
  void toggleTheme() {
    switch (_themeMode) {
      case ThemeMode.system:
        _themeMode = ThemeMode.light;
        break;
      case ThemeMode.light:
        _themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _themeMode = ThemeMode.system;
        break;
    }
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear error message
  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Manually clear error (for UI error handling)
  void clearError() {
    _clearError();
  }

  /// Refresh settings from storage
  Future<void> refreshSettings() async {
    _setLoading(true);
    _clearError();

    try {
      _settings = await _settingsService.getSettings();
      notifyListeners();
    } catch (e) {
      _setError('Failed to refresh settings: $e');
    } finally {
      _setLoading(false);
    }
  }
}
