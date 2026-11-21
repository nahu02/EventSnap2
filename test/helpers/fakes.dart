/// Reusable in-memory fakes for the service contracts (docs/v3_plan.md §4.2).
///
/// Import in tests: `import '../helpers/fakes.dart';` (adjust the path).
library;

import 'dart:async';

import 'package:event_snap_2/models/models.dart';
import 'package:event_snap_2/services/ai/ai_cancellation_token.dart';
import 'package:event_snap_2/services/ai/ai_exceptions.dart';
import 'package:event_snap_2/services/ai/ai_service_factory.dart';
import 'package:event_snap_2/services/ai/calendar_event_interpreter.dart';
import 'package:event_snap_2/services/ai/model_catalog.dart';
import 'package:event_snap_2/services/calendar/calendar_creator.dart';
import 'package:event_snap_2/services/calendar/ical_serializer.dart';
import 'package:event_snap_2/services/platform/image_input_service.dart';
import 'package:event_snap_2/services/platform/shared_content_source.dart';
import 'package:event_snap_2/services/settings_service.dart';

/// [SettingsService] keeping [Settings] in memory.
class InMemorySettingsService implements SettingsService {
  InMemorySettingsService([
    Settings? initial,
    this.apiKeysLostInUpgrade = false,
  ]) : settings = initial ?? Settings.defaults();

  /// Simulates saved API keys lost in the secure-storage upgrade.
  @override
  final bool apiKeysLostInUpgrade;

  /// Currently stored settings.
  Settings settings;

  /// Raw key/value pairs written via [setSetting].
  final Map<String, String> raw = {};

  /// When set, the next [updateSettings] call throws this and clears it.
  Object? failNextUpdate;

  int getCalls = 0;
  final List<Settings> updates = [];
  bool _hasSettings = false;

  @override
  Future<Settings> getSettings() async {
    getCalls++;
    return settings;
  }

  @override
  Future<void> updateSettings(Settings newSettings) async {
    final failure = failNextUpdate;
    if (failure != null) {
      failNextUpdate = null;
      throw failure;
    }
    final errors = newSettings.validateRanges();
    if (errors.isNotEmpty) {
      throw ArgumentError('Invalid settings: ${errors.join(', ')}');
    }
    updates.add(newSettings);
    settings = newSettings;
    _hasSettings = true;
  }

  @override
  Future<void> clearSettings() async {
    settings = Settings.defaults();
    raw.clear();
    _hasSettings = false;
  }

  @override
  Future<String?> getSetting(String key) async => raw[key];

  @override
  Future<void> setSetting(String key, String value) async {
    raw[key] = value;
    _hasSettings = true;
  }

  @override
  Future<bool> hasSettings() async => _hasSettings;
}

/// Signature for scripting [FakeCalendarEventInterpreter].
typedef ExtractHandler = Future<ExtractionResult> Function(
  ExtractionInput input,
  AiCancellationToken? cancellationToken,
);

/// [CalendarEventInterpreter] returning scripted results.
///
/// By default returns [result] (or an empty result). Set [handler] for full
/// control, or [error] to throw an [AiException].
class FakeCalendarEventInterpreter implements CalendarEventInterpreter {
  FakeCalendarEventInterpreter({this.result, this.error, this.handler});

  ExtractionResult? result;
  AiException? error;
  ExtractHandler? handler;

  /// Inputs received, in order.
  final List<ExtractionInput> calls = [];
  final List<AiCancellationToken?> tokens = [];

  @override
  Future<ExtractionResult> extractEvents(
    ExtractionInput input, {
    AiCancellationToken? cancellationToken,
  }) async {
    calls.add(input);
    tokens.add(cancellationToken);
    final h = handler;
    if (h != null) return h(input, cancellationToken);
    final e = error;
    if (e != null) throw e;
    return result ??
        ExtractionResult(
          events: const [],
          input: input,
          provider: AiProvider.openai,
          model: AiProvider.openai.defaultModel,
        );
  }
}

/// [ModelCatalog] backed by a fixed list per provider.
class FakeModelCatalog implements ModelCatalog {
  FakeModelCatalog({Map<AiProvider, List<AiModelInfo>>? models, this.error})
    : models = models ?? defaultModels();

  Map<AiProvider, List<AiModelInfo>> models;

  /// Thrown by [listModels] / [findModel] when set.
  AiException? error;

  /// Thrown by [verifyApiKey] when set.
  AiException? verifyError;

  int listCalls = 0;
  final List<(AiProvider, String)> verifyCalls = [];

  static Map<AiProvider, List<AiModelInfo>> defaultModels() => {
    AiProvider.openai: const [
      AiModelInfo(
        id: 'gpt-5-mini',
        provider: AiProvider.openai,
        vendor: 'OpenAI',
        supportsStructuredOutput: true,
        supportsVision: true,
        recommended: true,
      ),
      AiModelInfo(
        id: 'gpt-3.5-turbo',
        provider: AiProvider.openai,
        vendor: 'OpenAI',
        supportsStructuredOutput: false,
        supportsVision: false,
      ),
    ],
    AiProvider.opper: const [
      AiModelInfo(
        id: 'openai/gpt-5-mini',
        displayName: 'GPT-5 mini',
        provider: AiProvider.opper,
        vendor: 'OpenAI',
        supportsStructuredOutput: true,
        supportsVision: true,
        speed: 'fast',
        quality: 'great',
        recommended: true,
      ),
      AiModelInfo(
        id: 'anthropic/claude-sonnet-5-5',
        displayName: 'Claude Sonnet 5.5',
        provider: AiProvider.opper,
        vendor: 'Anthropic',
        supportsStructuredOutput: true,
        supportsVision: true,
      ),
    ],
  };

  @override
  Future<List<AiModelInfo>> listModels(
    AiProvider provider, {
    required String apiKey,
    bool forceRefresh = false,
  }) async {
    listCalls++;
    final e = error;
    if (e != null) throw e;
    return models[provider] ?? const [];
  }

  @override
  Future<AiModelInfo?> findModel(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) async {
    final list = await listModels(provider, apiKey: apiKey);
    for (final model in list) {
      if (model.id == modelId) return model;
    }
    return null;
  }

  @override
  Future<void> verifyApiKey(AiProvider provider, String apiKey) async {
    verifyCalls.add((provider, apiKey));
    final e = verifyError;
    if (e != null) throw e;
  }
}

/// [AiServiceFactory] handing out a shared [interpreter] and [modelCatalog].
class FakeAiServiceFactory implements AiServiceFactory {
  FakeAiServiceFactory({
    FakeCalendarEventInterpreter? interpreter,
    FakeModelCatalog? modelCatalog,
  }) : interpreter = interpreter ?? FakeCalendarEventInterpreter(),
       modelCatalog = modelCatalog ?? FakeModelCatalog();

  final FakeCalendarEventInterpreter interpreter;

  @override
  final FakeModelCatalog modelCatalog;

  /// Settings passed to [createInterpreter], in order.
  final List<Settings> createdWith = [];

  @override
  CalendarEventInterpreter createInterpreter(Settings settings) {
    createdWith.add(settings);
    return interpreter;
  }
}

/// [SharedContentSource] driven by the test: set [initial], call [emit].
class FakeSharedContentSource implements SharedContentSource {
  FakeSharedContentSource({this.initial});

  SharedContent? initial;
  final StreamController<SharedContent> _controller =
      StreamController<SharedContent>.broadcast();
  int initialCalls = 0;
  bool disposed = false;

  void emit(SharedContent content) => _controller.add(content);

  @override
  Future<SharedContent?> takeInitialSharedContent() async {
    initialCalls++;
    final content = initial;
    initial = null;
    return content;
  }

  @override
  Stream<SharedContent> get sharedContentStream => _controller.stream;

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }
}

/// [ImageInputService] returning scripted images.
class FakeImageInputService implements ImageInputService {
  FakeImageInputService({
    this.galleryResult,
    this.cameraResult,
    this.cameraSupported = true,
  });

  InputImage? galleryResult;
  InputImage? cameraResult;
  bool cameraSupported;
  int galleryCalls = 0;
  int cameraCalls = 0;

  @override
  bool get isCameraSupported => cameraSupported;

  @override
  Future<InputImage?> pickFromGallery() async {
    galleryCalls++;
    return galleryResult;
  }

  @override
  Future<InputImage?> captureWithCamera() async {
    cameraCalls++;
    return cameraResult;
  }
}

/// [CalendarCreator] that records exports instead of touching files.
class FakeCalendarCreator implements CalendarCreator {
  FakeCalendarCreator({this.openResult = true, this.createError});

  /// Result of [openInCalendarApp].
  bool openResult;

  /// Thrown by [createIcsFile] when set.
  Object? createError;

  /// Events passed to [createIcsFile], per call.
  final List<List<EventModel>> created = [];

  /// Paths passed to [openInCalendarApp].
  final List<String> opened = [];

  @override
  String buildIcs(List<EventModel> events) =>
      ICalSerializer.serialize(events, timestamp: DateTime.utc(2025, 1, 1));

  @override
  Future<String> createIcsFile(List<EventModel> events) async {
    final e = createError;
    if (e != null) throw e;
    buildIcs(events); // validates like the real implementation
    created.add(List.of(events));
    return '/fake/events_${created.length}.ics';
  }

  @override
  Future<bool> openInCalendarApp(String filePath) async {
    opened.add(filePath);
    return openResult;
  }
}

// ----------------------------------------------------------------------------
// Sample data

/// A valid timed event (2025-05-25 10:00–11:00 local by default).
EventModel sampleEvent({
  String title = 'Team meeting',
  String? description,
  String? location,
  DateTime? start,
  Duration duration = const Duration(hours: 1),
  bool isAllDay = false,
  Map<EventField, FieldEvidence> evidence = const {},
}) {
  final s = start ?? DateTime(2025, 5, 25, 10);
  return EventModel(
    title: title,
    description: description,
    location: location,
    startDateTime: s,
    endDateTime: s.add(duration),
    isAllDay: isAllDay,
    evidence: evidence,
  );
}

/// An [ExtractionResult] for [events] (one [sampleEvent] by default).
ExtractionResult sampleResult({
  List<EventModel>? events,
  String text = 'Team meeting on May 25 at 10',
  List<InputImage> images = const [],
  AiProvider provider = AiProvider.openai,
  String? model,
  bool usedStructuredOutput = true,
  List<String> warnings = const [],
  String? rawResponse,
}) {
  return ExtractionResult(
    events: events ?? [sampleEvent()],
    input: ExtractionInput(text: text, images: images),
    provider: provider,
    model: model ?? provider.defaultModel,
    usedStructuredOutput: usedStructuredOutput,
    warnings: warnings,
    rawResponse: rawResponse,
  );
}
