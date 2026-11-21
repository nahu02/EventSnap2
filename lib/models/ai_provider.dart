/// AI providers EventSnap can talk to.
///
/// Both speak the OpenAI Chat Completions wire format; see `services/ai/`.
enum AiProvider {
  openai(
    id: 'openai',
    displayName: 'OpenAI',
    defaultModel: 'gpt-5-mini',
    apiKeyHint: 'sk-...',
    apiKeyHelpUrlString: 'https://platform.openai.com/api-keys',
  ),
  opper(
    id: 'opper',
    displayName: 'Opper',
    defaultModel: 'openai/gpt-5-mini',
    apiKeyHint: 'Paste your Opper API key',
    apiKeyHelpUrlString: 'https://platform.opper.ai',
  );

  const AiProvider({
    required this.id,
    required this.displayName,
    required this.defaultModel,
    required this.apiKeyHint,
    required String apiKeyHelpUrlString,
  }) : _apiKeyHelpUrl = apiKeyHelpUrlString;

  /// Storage value: `'openai'` | `'opper'`.
  final String id;

  /// Human readable name: `'OpenAI'` | `'Opper'`.
  final String displayName;

  /// Model used when the user has not picked one.
  final String defaultModel;

  /// Placeholder text for the API key field.
  final String apiKeyHint;

  final String _apiKeyHelpUrl;

  /// Where the user can create an API key.
  Uri get apiKeyHelpUrl => Uri.parse(_apiKeyHelpUrl);

  /// Parses a storage id. Unknown or null ids fall back to [AiProvider.openai].
  static AiProvider fromId(String? id) {
    final normalized = id?.trim().toLowerCase();
    for (final provider in AiProvider.values) {
      if (provider.id == normalized) return provider;
    }
    return AiProvider.openai;
  }
}
