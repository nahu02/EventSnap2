import '../../models/ai_model_info.dart';
import '../../models/ai_provider.dart';

/// Lists the models a provider offers and verifies API keys.
///
/// All methods throw [AiException] on failure.
abstract class ModelCatalog {
  Future<List<AiModelInfo>> listModels(
    AiProvider provider, {
    required String apiKey,
    bool forceRefresh = false,
  });

  Future<AiModelInfo?> findModel(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  });

  /// Throws `AiException(kind: auth|network|…)` when the key cannot be used.
  Future<void> verifyApiKey(AiProvider provider, String apiKey);
}
