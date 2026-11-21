import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ai_provider.dart';
import '../models/settings.dart';
import '../providers/app_state_provider.dart';
import '../services/ai/ai_exceptions.dart';
import '../services/ai/ai_service_factory.dart';

/// Settings screen for API key configuration and app preferences
///
/// TEMPORARY v2 layout (OpenAI only) adapted to Settings v2; workstream E
/// replaces it with the multi-provider settings + model picker. Saving keeps
/// all settings fields this screen does not edit.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();

  // State variables
  String _selectedModel = AiProvider.openai.defaultModel;
  int _maxRetries = Settings.defaultMaxRetries;
  int _timeoutSeconds = Settings.defaultTimeoutSeconds;
  bool _debugMode = false;
  bool _obscureApiKey = true;
  bool _isLoading = false;
  bool _isLoadingModels = false;
  String? _errorMessage;
  String? _successMessage;
  String? _modelLoadError;

  // Track the actual API key for show/hide functionality
  String _actualApiKey = '';
  bool _isShowingSavedKey = false;

  // Available OpenAI models (fetched dynamically)
  List<String> _availableModels = [
    'gpt-5-mini',
    'gpt-5',
    'gpt-4.1-mini',
    'gpt-4.1',
  ]; // Default fallback models

  static const int _minTimeoutSlider = 10;
  static const int _maxTimeoutSlider = 180;
  static const int _maxRetriesSlider = 5;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  /// Load current settings from the app state
  void _loadCurrentSettings() {
    final appState = context.read<AppStateProvider>();
    final settings = appState.settings;

    {
      setState(() {
        _actualApiKey = settings.openAiApiKey;
        _isShowingSavedKey = settings.openAiApiKey.isNotEmpty;

        // Show masked version for saved keys, empty for no key
        _apiKeyController.text = settings.openAiApiKey.isNotEmpty
            ? '•' *
                  20 // Show masked version
            : '';
        _selectedModel = settings.openAiModel;
        if (!_availableModels.contains(_selectedModel)) {
          _availableModels = [_selectedModel, ..._availableModels];
        }
        _maxRetries = settings.maxRetries;
        _timeoutSeconds = settings.timeoutSeconds;
        _debugMode = settings.debugMode;
        // Set obscure to false when showing masked version, true when empty
        _obscureApiKey = settings.openAiApiKey.isEmpty;
      });

      // Fetch available models if API key is available
      if (settings.openAiApiKey.isNotEmpty) {
        _fetchAvailableModels();
      }
    }
  }

  /// Toggle API key visibility - handles both saved and new keys
  void _toggleApiKeyVisibility() {
    setState(() {
      if (_isShowingSavedKey) {
        // For saved keys: toggle between masked and actual key
        if (_apiKeyController.text.startsWith('•')) {
          // Currently showing masked, switch to actual key
          _apiKeyController.text = _actualApiKey;
          _obscureApiKey = false;
        } else {
          // Currently showing actual key, switch to masked
          _apiKeyController.text = '•' * 20;
          _obscureApiKey = false;
        }
      } else {
        // For new/empty keys: just toggle obscureText
        _obscureApiKey = !_obscureApiKey;
      }
    });
  }

  /// Clear messages
  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }

  /// Show error message
  void _showError(String message) {
    setState(() {
      _errorMessage = message;
      _successMessage = null;
    });
  }

  /// Show success message
  void _showSuccess(String message) {
    setState(() {
      _successMessage = message;
      _errorMessage = null;
    });
  }

  /// Fetch available OpenAI models dynamically
  Future<void> _fetchAvailableModels() async {
    final appState = context.read<AppStateProvider>();
    final settings = appState.settings;
    final catalog = context.read<AiServiceFactory>().modelCatalog;

    if (settings.openAiApiKey.isEmpty) {
      setState(() {
        _modelLoadError = 'API key required to fetch models';
      });
      return;
    }

    setState(() {
      _isLoadingModels = true;
      _modelLoadError = null;
    });

    try {
      final models = await catalog.listModels(
        AiProvider.openai,
        apiKey: settings.openAiApiKey,
      );
      final gptModels = models.map((m) => m.id).toList();
      if (!mounted) return;

      if (gptModels.isNotEmpty) {
        setState(() {
          _availableModels = gptModels;
          // Update selected model if it's not in the new list
          // Keep the user's current model selectable
          if (!_availableModels.contains(_selectedModel)) {
            _availableModels = [_selectedModel, ..._availableModels];
          }
        });
      } else {
        setState(() {
          _modelLoadError = 'No GPT models found in your OpenAI account';
        });
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _modelLoadError = 'Failed to fetch models: ${e.userMessage}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
      }
    }
  }

  /// Validate API key format
  String? _validateApiKey(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'API key is required';
    }

    // Don't validate if it's the masked version
    if (value.startsWith('•')) {
      return null;
    }

    if (!value.startsWith('sk-')) {
      return 'API key must start with "sk-"';
    }

    if (value.length < 20) {
      return 'API key appears to be too short';
    }

    return null;
  }

  /// Save settings
  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    _clearMessages();
    setState(() {
      _isLoading = true;
    });

    try {
      final appState = context.read<AppStateProvider>();
      final currentSettings = appState.settings;

      // Use existing API key if user didn't change it (masked version)
      String apiKey = _apiKeyController.text;
      if (apiKey.startsWith('•')) {
        apiKey = currentSettings.openAiApiKey;
      }

      // Create new settings (keeps fields this screen does not edit)
      final newSettings = currentSettings.copyWith(
        provider: AiProvider.openai,
        openAiApiKey: apiKey.trim(),
        openAiModel: _selectedModel,
        maxRetries: _maxRetries,
        timeoutSeconds: _timeoutSeconds,
        debugMode: _debugMode,
      );

      // Check if API key changed to refresh models
      final apiKeyChanged =
          !apiKey.startsWith('•') && apiKey != currentSettings.openAiApiKey;

      // Update settings through app state
      await appState.updateSettings(newSettings);

      _showSuccess('Settings saved successfully!');

      // Refresh the masked display
      _loadCurrentSettings();

      // Fetch models if API key was updated
      if (apiKeyChanged && newSettings.openAiApiKey.isNotEmpty) {
        _fetchAvailableModels();
      }
    } catch (e) {
      _showError('Failed to save settings: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Reset settings to defaults
  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all settings to their default values? This will clear your API key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _apiKeyController.text = '';
        _selectedModel = AiProvider.openai.defaultModel;
        _maxRetries = Settings.defaultMaxRetries;
        _timeoutSeconds = Settings.defaultTimeoutSeconds;
        _debugMode = false;
        _obscureApiKey = true;
        _actualApiKey = '';
        _isShowingSavedKey = false;
      });

      _clearMessages();
    }
  }

  /// Open OpenAI API documentation
  Future<void> _openApiDocumentation() async {
    final uri = AiProvider.openai.apiKeyHelpUrl;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError('Error opening documentation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _resetToDefaults, child: const Text('Reset')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Messages section
            if (_errorMessage != null || _successMessage != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16.0),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: _errorMessage != null
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Row(
                  children: [
                    Icon(
                      _errorMessage != null ? Icons.error : Icons.check_circle,
                      color: _errorMessage != null
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        _errorMessage ?? _successMessage ?? '',
                        style: TextStyle(
                          color: _errorMessage != null
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _clearMessages,
                      iconSize: 20.0,
                    ),
                  ],
                ),
              ),

            // Main content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // App info section
                  Consumer<AppStateProvider>(
                    builder: (context, appState, child) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'App Information',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 16),

                              ListTile(
                                leading: Icon(
                                  appState.isConfigured
                                      ? Icons.check_circle
                                      : Icons.warning,
                                  color: appState.isConfigured
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                ),
                                title: Text(
                                  appState.isConfigured
                                      ? 'App Configured'
                                      : 'Setup Required',
                                ),
                                subtitle: Text(
                                  appState.isConfigured
                                      ? 'Ready to process events'
                                      : 'Please configure your OpenAI API key',
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),

                              const Divider(),

                              ListTile(
                                leading: const Icon(Icons.brightness_6),
                                title: const Text('Theme'),
                                subtitle: Text(
                                  _getThemeModeText(appState.themeMode),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.brightness_4),
                                  tooltip: 'Change theme',
                                  onPressed: () => _cycleTheme(appState),
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // OpenAI Configuration section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OpenAI Configuration',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),

                          // API Key field
                          TextFormField(
                            controller: _apiKeyController,
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              hintText: 'sk-...',
                              prefixIcon: const Icon(Icons.key),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _obscureApiKey ||
                                              (_isShowingSavedKey &&
                                                  _apiKeyController.text
                                                      .startsWith('•'))
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed: _toggleApiKeyVisibility,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.help_outline),
                                    onPressed: _openApiDocumentation,
                                  ),
                                ],
                              ),
                              border: const OutlineInputBorder(),
                              helperText:
                                  'Your OpenAI API key (stored securely)',
                            ),
                            obscureText: _obscureApiKey,
                            validator: _validateApiKey,
                            onChanged: (value) {
                              _clearMessages();
                              // If user starts typing and we were showing a saved key, reset state
                              if (_isShowingSavedKey &&
                                  !value.startsWith('•')) {
                                setState(() {
                                  _isShowingSavedKey = false;
                                  _actualApiKey = '';
                                  _obscureApiKey = true;
                                });
                              }
                            },
                          ),

                          const SizedBox(height: 16),

                          // Model selection with loading state
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue:
                                          _availableModels.contains(
                                            _selectedModel,
                                          )
                                          ? _selectedModel
                                          : null,
                                      decoration: InputDecoration(
                                        labelText: 'AI Model',
                                        prefixIcon: _isLoadingModels
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: Padding(
                                                  padding: EdgeInsets.all(8.0),
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              )
                                            : const Icon(Icons.psychology),
                                        border: const OutlineInputBorder(),
                                        helperText: _isLoadingModels
                                            ? 'Loading available models...'
                                            : 'OpenAI model to use for event extraction',
                                      ),
                                      items: _availableModels.map((model) {
                                        return DropdownMenuItem(
                                          value: model,
                                          child: Row(
                                            children: [
                                              Text(
                                                model,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (model ==
                                                  AiProvider
                                                      .openai
                                                      .defaultModel)
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 8.0,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6.0,
                                                        vertical: 2.0,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4.0,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Recommended',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onPrimary,
                                                      fontSize: 10.0,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: _isLoadingModels
                                          ? null
                                          : (value) {
                                              if (value != null) {
                                                setState(() {
                                                  _selectedModel = value;
                                                });
                                                _clearMessages();
                                              }
                                            },
                                    ),
                                  ),
                                ],
                              ),
                              if (_modelLoadError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(8.0),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      borderRadius: BorderRadius.circular(4.0),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.warning,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _modelLoadError!,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onErrorContainer,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Help section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Help & Documentation',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),

                          ListTile(
                            leading: const Icon(Icons.key),
                            title: const Text('How to get an OpenAI API Key'),
                            subtitle: const Text(
                              'Visit OpenAI Platform to create an API key',
                            ),
                            trailing: const Icon(Icons.open_in_new),
                            onTap: _openApiDocumentation,
                            contentPadding: EdgeInsets.zero,
                          ),

                          const Divider(),

                          const ListTile(
                            leading: Icon(Icons.security),
                            title: Text('Security & Privacy'),
                            subtitle: Text(
                              'Your API key is stored securely on your device',
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),

                          const Divider(),

                          const ListTile(
                            leading: Icon(Icons.psychology),
                            title: Text('AI Model Information'),
                            subtitle: Text(
                              'gpt-5-mini provides good accuracy for event extraction',
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Advanced Settings section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Advanced Settings',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),

                          // Max Retries
                          Row(
                            children: [
                              const Icon(Icons.refresh),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Max Retries: $_maxRetries',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge,
                                    ),
                                    const Text(
                                      'Number of retry attempts for failed API calls',
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Slider(
                                  value: _maxRetries
                                      .clamp(0, _maxRetriesSlider)
                                      .toDouble(),
                                  min: 0,
                                  max: _maxRetriesSlider.toDouble(),
                                  divisions: _maxRetriesSlider,
                                  onChanged: (value) {
                                    setState(() {
                                      _maxRetries = value.toInt();
                                    });
                                    _clearMessages();
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Timeout
                          Row(
                            children: [
                              const Icon(Icons.timer),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Timeout: ${_timeoutSeconds}s',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge,
                                    ),
                                    const Text(
                                      'Maximum time to wait for API response',
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Slider(
                                  value: _timeoutSeconds
                                      .clamp(
                                        _minTimeoutSlider,
                                        _maxTimeoutSlider,
                                      )
                                      .toDouble(),
                                  min: _minTimeoutSlider.toDouble(),
                                  max: _maxTimeoutSlider.toDouble(),
                                  divisions:
                                      (_maxTimeoutSlider - _minTimeoutSlider) ~/
                                      10,
                                  onChanged: (value) {
                                    setState(() {
                                      _timeoutSeconds = value.toInt();
                                    });
                                    _clearMessages();
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Debug Mode
                          SwitchListTile(
                            value: _debugMode,
                            onChanged: (value) {
                              setState(() {
                                _debugMode = value;
                              });
                              _clearMessages();
                            },
                            title: const Text('Debug Mode'),
                            subtitle: const Text(
                              'Show the raw AI response when reviewing events',
                            ),
                            secondary: const Icon(Icons.bug_report),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveSettings,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cycles System → Light → Dark and saves immediately.
  Future<void> _cycleTheme(AppStateProvider appState) async {
    final next = switch (appState.settings.themeMode) {
      AppThemeMode.system => AppThemeMode.light,
      AppThemeMode.light => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.system,
    };
    try {
      await appState.updateSettings(
        appState.settings.copyWith(themeMode: next),
      );
    } catch (e) {
      _showError('Failed to change theme: $e');
    }
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }
}
