import '../../models/ai_provider.dart';

/// Where a provider's model capabilities come from.
enum CapabilityStrategy {
  /// The provider's model list reports capabilities (Opper).
  liveCatalog,

  /// The model list has ids only; capabilities are guessed from the id
  /// (OpenAI). See `ModelHeuristics`.
  idHeuristics,
}

/// Endpoints and behaviour of one [AiProvider]. Both providers speak the
/// OpenAI Chat Completions wire format.
class ProviderConfig {
  const ProviderConfig._({
    required this.provider,
    required this._baseUrl,
    required this._modelsUrl,
    required this._keyVerificationUrl,
    required this.modelListRequiresKey,
    required this.capabilityStrategy,
  });

  final AiProvider provider;
  final String _baseUrl;
  final String _modelsUrl;
  final String _keyVerificationUrl;

  /// Whether listing models needs an API key.
  final bool modelListRequiresKey;

  final CapabilityStrategy capabilityStrategy;

  static const ProviderConfig openai = ProviderConfig._(
    provider: AiProvider.openai,
    baseUrl: 'https://api.openai.com/v1',
    modelsUrl: 'https://api.openai.com/v1/models',
    keyVerificationUrl: 'https://api.openai.com/v1/models',
    modelListRequiresKey: true,
    capabilityStrategy: CapabilityStrategy.idHeuristics,
  );

  static const ProviderConfig opper = ProviderConfig._(
    provider: AiProvider.opper,
    baseUrl: 'https://api.opper.ai/v3/compat',
    // `limit<=0` returns the whole catalogue; no key needed.
    modelsUrl: 'https://api.opper.ai/v3/models?type=llm&limit=0',
    // Free: `include=route` requires a valid key (200) and answers 401
    // otherwise, without running a model.
    keyVerificationUrl: 'https://api.opper.ai/v3/models?include=route&limit=1',
    modelListRequiresKey: false,
    capabilityStrategy: CapabilityStrategy.liveCatalog,
  );

  static ProviderConfig of(AiProvider provider) => switch (provider) {
    AiProvider.openai => openai,
    AiProvider.opper => opper,
  };

  /// Chat Completions base URL, e.g. `https://api.opper.ai/v3/compat`.
  Uri get baseUrl => Uri.parse(_baseUrl);

  /// `POST {baseUrl}/chat/completions`.
  Uri get chatCompletionsUrl => Uri.parse('$_baseUrl/chat/completions');

  /// The full model list.
  Uri get modelsUrl => Uri.parse(_modelsUrl);

  /// A cheap authenticated request used to check an API key.
  Uri get keyVerificationUrl => Uri.parse(_keyVerificationUrl);

  /// Details of one model (Opper only: `GET /v3/models/{id}`; ids contain
  /// slashes and are sent unescaped). `null` for providers without such an
  /// endpoint.
  Uri? singleModelUrl(String modelId) => switch (provider) {
    AiProvider.opper => Uri.https('api.opper.ai', '/v3/models/$modelId'),
    AiProvider.openai => null,
  };
}
