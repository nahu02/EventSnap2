/// Represents application settings and configuration
/// Includes OpenAI API configuration and other app preferences
class Settings {
  /// OpenAI API key for accessing the AI service
  /// This should be stored securely using flutter_secure_storage
  String openAiApiKey;

  /// OpenAI model to use for event interpretation
  /// Default is "gpt-4.1" as specified in the design document
  String openAiModel;

  /// Maximum number of retries for API calls
  int maxRetries;

  /// Timeout duration for API calls in seconds
  int timeoutSeconds;

  /// Whether to show debug information in the UI
  bool debugMode;

  /// Creates a Settings instance
  ///
  /// [openAiApiKey] is required (can be empty for defaults)
  /// [openAiModel] defaults to "gpt-4.1"
  /// [maxRetries] defaults to 3
  /// [timeoutSeconds] defaults to 30
  /// [debugMode] defaults to false
  /// [validateOnCreation] defaults to true, set to false for defaults
  Settings({
    required this.openAiApiKey,
    this.openAiModel = 'gpt-4.1',
    this.maxRetries = 3,
    this.timeoutSeconds = 30,
    this.debugMode = false,
    bool validateOnCreation = true,
  }) {
    if (validateOnCreation) {
      // Validate API key is not empty
      if (openAiApiKey.trim().isEmpty) {
        throw ArgumentError('OpenAI API key cannot be empty');
      }

      // Validate model name is not empty
      if (openAiModel.trim().isEmpty) {
        throw ArgumentError('OpenAI model cannot be empty');
      }

      // Validate reasonable retry count
      if (maxRetries < 0 || maxRetries > 10) {
        throw ArgumentError('Max retries must be between 0 and 10');
      }

      // Validate reasonable timeout
      if (timeoutSeconds < 5 || timeoutSeconds > 300) {
        throw ArgumentError('Timeout must be between 5 and 300 seconds');
      }
    }
  }

  /// Creates Settings from JSON data
  ///
  /// Expected JSON format:
  /// ```json
  /// {
  ///   "openAiApiKey": "sk-...",
  ///   "openAiModel": "gpt-4.1",
  ///   "maxRetries": 3,
  ///   "timeoutSeconds": 30,
  ///   "debugMode": false
  /// }
  /// ```
  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      openAiApiKey: json['openAiApiKey'] as String,
      openAiModel: json['openAiModel'] as String? ?? 'gpt-4.1',
      maxRetries: json['maxRetries'] as int? ?? 3,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 30,
      debugMode: json['debugMode'] as bool? ?? false,
    );
  }

  /// Converts Settings to JSON format
  ///
  /// Returns a Map＜String, dynamic＞ suitable for JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'openAiApiKey': openAiApiKey,
      'openAiModel': openAiModel,
      'maxRetries': maxRetries,
      'timeoutSeconds': timeoutSeconds,
      'debugMode': debugMode,
    };
  }

  /// Creates default settings with an empty API key
  ///
  /// Useful for first-time app setup
  factory Settings.defaults() {
    return Settings(
      openAiApiKey: '', // Will need to be set by user
      openAiModel: 'gpt-4.1',
      maxRetries: 3,
      timeoutSeconds: 30,
      debugMode: false,
      validateOnCreation: false, // Don't validate empty API key on defaults
    );
  }

  /// Creates a copy of this Settings with optional field updates
  ///
  /// Useful for updating settings without modifying the original
  Settings copyWith({
    String? openAiApiKey,
    String? openAiModel,
    int? maxRetries,
    int? timeoutSeconds,
    bool? debugMode,
    bool validateOnCreation = true,
  }) {
    return Settings(
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      openAiModel: openAiModel ?? this.openAiModel,
      maxRetries: maxRetries ?? this.maxRetries,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      debugMode: debugMode ?? this.debugMode,
      validateOnCreation: validateOnCreation,
    );
  }

  /// Validates the settings and returns a list of validation errors
  ///
  /// Returns an empty list if the settings are valid
  List<String> validate() {
    List<String> errors = [];

    if (openAiApiKey.trim().isEmpty) {
      errors.add('OpenAI API key is required');
    } else if (!openAiApiKey.startsWith('sk-')) {
      errors.add('OpenAI API key should start with "sk-"');
    }

    if (openAiModel.trim().isEmpty) {
      errors.add('OpenAI model cannot be empty');
    }

    if (maxRetries < 0 || maxRetries > 10) {
      errors.add('Max retries must be between 0 and 10');
    }

    if (timeoutSeconds < 5 || timeoutSeconds > 300) {
      errors.add('Timeout must be between 5 and 300 seconds');
    }

    return errors;
  }

  /// Returns true if the settings are valid
  bool get isValid => validate().isEmpty;

  /// Returns true if the API key is configured
  bool get hasApiKey => openAiApiKey.isNotEmpty;

  /// Returns true if the settings are ready for use
  bool get isReadyForUse => isValid && hasApiKey;

  /// Gets the timeout duration as a Duration object
  Duration get timeoutDuration => Duration(seconds: timeoutSeconds);

  /// Returns a safe version of the API key for display (masked)
  String get maskedApiKey {
    if (openAiApiKey.length <= 8) {
      return '*' * openAiApiKey.length;
    }
    final prefix = openAiApiKey.substring(0, 3);
    final suffix = openAiApiKey.substring(openAiApiKey.length - 4);
    // Use a fixed number of asterisks (9) for consistent display
    const masked = '*********';
    return '$prefix$masked$suffix';
  }

  @override
  String toString() {
    return 'Settings(openAiModel: $openAiModel, maxRetries: $maxRetries, timeoutSeconds: $timeoutSeconds, debugMode: $debugMode, hasApiKey: $hasApiKey)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Settings &&
        other.openAiApiKey == openAiApiKey &&
        other.openAiModel == openAiModel &&
        other.maxRetries == maxRetries &&
        other.timeoutSeconds == timeoutSeconds &&
        other.debugMode == debugMode;
  }

  @override
  int get hashCode {
    return openAiApiKey.hashCode ^
        openAiModel.hashCode ^
        maxRetries.hashCode ^
        timeoutSeconds.hashCode ^
        debugMode.hashCode;
  }
}
