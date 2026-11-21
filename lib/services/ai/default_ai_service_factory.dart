import 'dart:math';

import 'package:http/http.dart' as http;

import '../../models/settings.dart';
import 'ai_service_factory.dart';
import 'calendar_event_interpreter.dart';
import 'default_model_catalog.dart';
import 'openai_compatible_client.dart';
import 'openai_compatible_interpreter.dart';

/// The production [AiServiceFactory]: OpenAI and Opper over one shared
/// `http.Client`, the [DefaultModelCatalog] and a session-wide
/// [AiSessionState] (remembered structured-output downgrades).
///
/// Register once in `main.dart`: `DefaultAiServiceFactory()`.
class DefaultAiServiceFactory implements AiServiceFactory {
  DefaultAiServiceFactory({
    http.Client? httpClient,
    DefaultModelCatalog? modelCatalog,
    AiSessionState? sessionState,
    DateTime Function()? clock,
    ImageBytesReader? imageReader,
    DelayFunction? delay,
    Random? random,
    List<String> reasoningEffortPreference =
        OpenAiCompatibleInterpreter.defaultReasoningEffortPreference,
  }) : this._(
         httpClient ?? http.Client(),
         modelCatalog,
         sessionState ?? AiSessionState(),
         clock,
         imageReader,
         delay,
         random,
         reasoningEffortPreference,
       );

  DefaultAiServiceFactory._(
    this._httpClient,
    DefaultModelCatalog? modelCatalog,
    this.sessionState,
    this._clock,
    this._imageReader,
    this._delay,
    this._random,
    this.reasoningEffortPreference,
  ) : modelCatalog =
          modelCatalog ??
          DefaultModelCatalog(httpClient: _httpClient, clock: _clock);

  final http.Client _httpClient;
  final DateTime Function()? _clock;
  final ImageBytesReader? _imageReader;
  final DelayFunction? _delay;
  final Random? _random;

  @override
  final DefaultModelCatalog modelCatalog;

  /// Shared by every interpreter this factory creates.
  final AiSessionState sessionState;

  /// `reasoning_effort` values in order of preference.
  final List<String> reasoningEffortPreference;

  @override
  CalendarEventInterpreter createInterpreter(Settings settings) {
    return OpenAiCompatibleInterpreter(
      settings: settings,
      client: OpenAiCompatibleClient(
        httpClient: _httpClient,
        timeout: settings.timeoutDuration,
        maxRetries: settings.maxRetries,
        delay: _delay,
        random: _random,
      ),
      profileResolver: modelCatalog,
      sessionState: sessionState,
      clock: _clock,
      imageReader: _imageReader,
      reasoningEffortPreference: reasoningEffortPreference,
    );
  }
}
