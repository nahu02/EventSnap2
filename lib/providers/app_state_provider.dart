import 'package:material_ui/material_ui.dart';

import '../models/settings.dart';
import '../services/settings_service.dart';

/// Global app state: the persisted [Settings] and derived values.
class AppStateProvider extends ChangeNotifier {
  AppStateProvider({required this._settingsService});

  final SettingsService _settingsService;

  Settings _settings = Settings.defaults();
  bool _isInitialized = false;
  String? _errorMessage;
  bool _apiKeyLostNoticeDismissed = false;

  /// Current settings ([Settings.defaults] until [initialize] completes).
  Settings get settings => _settings;

  /// True once [initialize] has finished (successfully or not).
  bool get isInitialized => _isInitialized;

  /// Whether the active provider has an API key and a model.
  bool get isConfigured => _settings.isConfigured;

  /// Last error from loading/saving settings, if any.
  String? get errorMessage => _errorMessage;

  /// Whether to tell the user their saved API key was lost in the secure
  /// storage upgrade. The service reports the loss on one launch only, so the
  /// notice does not return on later launches; dismissing lasts the session.
  bool get showApiKeyLostNotice =>
      _isInitialized &&
      _settingsService.apiKeysLostInUpgrade &&
      !_apiKeyLostNoticeDismissed;

  void dismissApiKeyLostNotice() {
    if (_apiKeyLostNoticeDismissed) return;
    _apiKeyLostNoticeDismissed = true;
    notifyListeners();
  }

  /// Flutter theme mode mapped from [Settings.themeMode].
  ThemeMode get themeMode => switch (_settings.themeMode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// Loads settings from storage. Safe to call again to reload.
  Future<void> initialize() async {
    _errorMessage = null;
    try {
      _settings = await _settingsService.getSettings();
    } catch (e) {
      _errorMessage = 'Failed to load settings: $e';
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Persists [newSettings] and applies them.
  ///
  /// On failure the previous settings stay active, [errorMessage] is set and
  /// the error is rethrown so callers can show it.
  Future<void> updateSettings(Settings newSettings) async {
    try {
      await _settingsService.updateSettings(newSettings);
      _settings = newSettings;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to save settings: $e';
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}
