import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dart_openai/dart_openai.dart';
import '../providers/app_state_provider.dart';
import '../navigation/app_router.dart';
import '../models/settings.dart';

/// Settings screen for API key configuration and app preferences
///
/// Provides secure input for OpenAI API key, model selection,
/// and other application settings. Uses SettingsService for
/// secure storage and persistence.
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
  String _selectedModel = 'gpt-4.1';
  int _maxRetries = 3;
  int _timeoutSeconds = 30;
  bool _debugMode = false;
  bool _obscureApiKey = true;
  bool _isLoading = false;
  bool _isLoadingModels = false;
  String? _errorMessage;
  String? _successMessage;
  String? _modelLoadError;

  // Available OpenAI models (fetched dynamically)
  List<String> _availableModels = [
    'gpt-4.1',
    'gpt-4.1-mini',
    'gpt-4.1-nano',
    'gpt-4o',
  ]; // Default fallback models

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

    if (settings != null) {
      setState(() {
        // Mask the API key for security
        _apiKeyController.text = settings.openAiApiKey.isNotEmpty
            ? '•' *
                  20 // Show masked version
            : '';
        _selectedModel = settings.openAiModel;
        _maxRetries = settings.maxRetries;
        _timeoutSeconds = settings.timeoutSeconds;
        _debugMode = settings.debugMode;
      });

      // Fetch available models if API key is available
      if (settings.hasApiKey) {
        _fetchAvailableModels();
      }
    }
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

    if (settings == null || !settings.hasApiKey) {
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
      // Set the API key for OpenAI
      OpenAI.apiKey = settings.openAiApiKey;

      // Fetch models from OpenAI API
      final models = await OpenAI.instance.model.list();

      // Filter for GPT models only
      final gptModels = models
          .where((model) => model.id.toLowerCase().contains('gpt'))
          .where((model) {
            final modelId = model.id.toLowerCase();
            final excludeKeywords = [
              'preview',
              'audio',
              'vision',
              'image',
              'realtime',
              'embedding',
              'tts',
              'transcribe',
              'instruct',
            ];
            return !excludeKeywords.any((keyword) => modelId.contains(keyword));
          })
          .map((model) => model.id)
          .toList();

      // Sort models to prioritize common ones
      gptModels.sort((a, b) {
        // Prioritize GPT-4 models, then GPT-3.5, then others
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();

        if (aLower.contains('gpt-4') && !bLower.contains('gpt-4')) return -1;
        if (!aLower.contains('gpt-4') && bLower.contains('gpt-4')) return 1;
        if (aLower.contains('gpt-3.5') && !bLower.contains('gpt-3.5')) {
          return -1;
        }
        if (!aLower.contains('gpt-3.5') && bLower.contains('gpt-3.5')) return 1;

        return a.compareTo(b);
      });

      if (gptModels.isNotEmpty) {
        setState(() {
          _availableModels = gptModels;
          // Update selected model if it's not in the new list
          if (!_availableModels.contains(_selectedModel)) {
            _selectedModel = _availableModels.first;
          }
        });
      } else {
        setState(() {
          _modelLoadError = 'No GPT models found in your OpenAI account';
        });
      }
    } catch (e) {
      setState(() {
        _modelLoadError = 'Failed to fetch models: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoadingModels = false;
      });
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
      final currentSettings = appState.settings ?? Settings.defaults();

      // Use existing API key if user didn't change it (masked version)
      String apiKey = _apiKeyController.text;
      if (apiKey.startsWith('•')) {
        apiKey = currentSettings.openAiApiKey;
      }

      // Create new settings
      final newSettings = Settings(
        openAiApiKey: apiKey.trim(),
        openAiModel: _availableModels.contains(_selectedModel)
            ? _selectedModel
            : _availableModels.first,
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
      if (apiKeyChanged && newSettings.hasApiKey) {
        _fetchAvailableModels();
      }
    } catch (e) {
      _showError('Failed to save settings: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
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
        _selectedModel = 'gpt-4.1';
        _maxRetries = 3;
        _timeoutSeconds = 30;
        _debugMode = false;
        _obscureApiKey = true;
      });

      _clearMessages();
    }
  }

  /// Open OpenAI API documentation
  Future<void> _openApiDocumentation() async {
    const url = 'https://platform.openai.com/api-keys';
    final uri = Uri.parse(url);

    try {
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showError('Could not open documentation. Please visit: $url');
      }
    } catch (e) {
      _showError('Error opening documentation: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => AppRouter.goBack(context),
        ),
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
                      ? Colors.red.withAlpha(25)
                      : Colors.green.withAlpha(25),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: _errorMessage != null ? Colors.red : Colors.green,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _errorMessage != null ? Icons.error : Icons.check_circle,
                      color: _errorMessage != null ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Text(
                        _errorMessage ?? _successMessage ?? '',
                        style: TextStyle(
                          color: _errorMessage != null
                              ? Colors.red
                              : Colors.green,
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
                                      ? Colors.green
                                      : Colors.orange,
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
                                  onPressed: () => appState.toggleTheme(),
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
                                      _obscureApiKey
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureApiKey = !_obscureApiKey;
                                      });
                                    },
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
                            onChanged: (_) => _clearMessages(),
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
                                      value:
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
                                              if (model == 'gpt-4.1')
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
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4.0,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Recommended',
                                                    style: TextStyle(
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.onPrimary,
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(4.0),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.warning,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onErrorContainer,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _modelLoadError!,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onErrorContainer,
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
                              'gpt-4.1 provides the best accuracy for event extraction',
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
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
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
                                  value: _maxRetries.toDouble(),
                                  min: 0,
                                  max: 5,
                                  divisions: 5,
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
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
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
                                  value: _timeoutSeconds.toDouble(),
                                  min: 10,
                                  max: 60,
                                  divisions: 10,
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
                              'Show detailed debug information',
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
                      onPressed: () => AppRouter.goBack(context),
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
