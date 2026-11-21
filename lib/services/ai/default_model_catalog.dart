import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../models/ai_model_info.dart';
import '../../models/ai_provider.dart';
import 'ai_exceptions.dart';
import 'model_catalog.dart';
import 'model_profile.dart';
import 'openai_compatible_client.dart';
import 'provider_config.dart';

/// Resolves the request profile (capabilities + accepted parameters) of a
/// model. Never throws: falls back to [ModelHeuristics.guessProfile].
abstract class ModelProfileResolver {
  Future<ModelProfile> resolveProfile(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  });
}

/// Persistent string storage for the model catalogue cache.
abstract class CatalogCacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Stores the catalogue cache as JSON files in the app's cache directory.
///
/// A file (not shared_preferences) because the Opper catalogue is a few
/// hundred KB and shared_preferences loads every value into memory at start.
/// All failures are swallowed (the cache is an optimisation only).
class FileCatalogCacheStore implements CatalogCacheStore {
  FileCatalogCacheStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationCacheDirectory;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file(String key) async {
    final directory = await _directoryProvider();
    return File('${directory.path}/eventsnap_model_catalog_$key.json');
  }

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final file = await _file(key);
      await file.parent.create(recursive: true);
      await file.writeAsString(value, flush: true);
    } catch (_) {
      // Ignore: the cache is optional.
    }
  }
}

/// In-memory [CatalogCacheStore] (tests, platforms without a file system).
class InMemoryCatalogCacheStore implements CatalogCacheStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A model in the catalogue together with its request profile.
class CatalogEntry {
  const CatalogEntry(this.info, this.profile);

  final AiModelInfo info;
  final ModelProfile profile;

  Map<String, dynamic> toJson() {
    final json = info.toJson()
      ..removeWhere((k, v) => v == null || (k == 'recommended' && v == false));
    return json..addAll(profile.toJson());
  }

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    final info = AiModelInfo.fromJson(json);
    return CatalogEntry(
      info,
      ModelProfile.fromCache(
        info.id,
        json,
        supportsStructuredOutput: info.supportsStructuredOutput,
        supportsVision: info.supportsVision,
      ),
    );
  }
}

/// [ModelCatalog] for OpenAI and Opper.
///
/// * **Opper**: `GET /v3/models?type=llm&limit=0` (public, no key). Capabilities
///   come from each model's `capabilities`; request quirks from `params`
///   (`reasoning.supported`, `temperature`). Batch-only routes are left out.
///   Recommended: the provider default plus Opper's *featured* first-party
///   models with structured output and vision (one route per model).
/// * **OpenAI**: `GET /v1/models` (key required, ids only) filtered to chat
///   models; capabilities from [ModelHeuristics]; a short recommended list.
///
/// Lists are cached in memory and persisted ([CatalogCacheStore]) for
/// [cacheTtl]. When a refresh fails for a transient reason a stale cache is
/// returned instead (unless `forceRefresh`).
class DefaultModelCatalog implements ModelCatalog, ModelProfileResolver {
  DefaultModelCatalog({
    http.Client? httpClient,
    CatalogCacheStore? cacheStore,
    DateTime Function()? clock,
    Duration cacheTtl = const Duration(hours: 24),
    DelayFunction? delay,
  }) : this._(
         httpClient ?? http.Client(),
         cacheStore ?? FileCatalogCacheStore(),
         clock ?? DateTime.now,
         cacheTtl,
         delay,
       );

  DefaultModelCatalog._(
    http.Client httpClient,
    this._cacheStore,
    this._clock,
    this.cacheTtl,
    DelayFunction? delay,
  ) : _listClient = OpenAiCompatibleClient(
        httpClient: httpClient,
        timeout: const Duration(seconds: 30),
        maxRetries: 1,
        delay: delay,
      ),
      _probeClient = OpenAiCompatibleClient(
        httpClient: httpClient,
        timeout: const Duration(seconds: 8),
        maxRetries: 0,
        delay: delay,
      );

  /// OpenAI models shown first in pickers (when the account has them).
  static const List<String> recommendedOpenAiModels = [
    'gpt-5-mini',
    'gpt-5-nano',
    'gpt-5',
    'gpt-4.1-mini',
    'gpt-4.1',
    'gpt-6-luna',
  ];

  static const int _cacheVersion = 1;

  final CatalogCacheStore _cacheStore;
  final DateTime Function() _clock;
  final OpenAiCompatibleClient _listClient;
  final OpenAiCompatibleClient _probeClient;

  /// How long a fetched list is considered fresh.
  final Duration cacheTtl;

  final Map<AiProvider, _Snapshot> _memory = {};
  final Map<AiProvider, Future<_Snapshot>> _inFlight = {};
  final Map<AiProvider, Future<void>> _persistedLoads = {};
  final Map<String, CatalogEntry?> _singleModels = {};

  @override
  Future<List<AiModelInfo>> listModels(
    AiProvider provider, {
    required String apiKey,
    bool forceRefresh = false,
  }) async {
    final config = ProviderConfig.of(provider);
    final key = apiKey.trim();
    if (config.modelListRequiresKey && key.isEmpty) {
      throw AiException(
        AiErrorKind.notConfigured,
        'A ${provider.displayName} API key is required to list models',
      );
    }
    final fingerprint = config.modelListRequiresKey ? keyFingerprint(key) : '';

    if (!forceRefresh) {
      await _loadPersisted(provider);
      final cached = _memory[provider];
      if (cached != null &&
          cached.fingerprint == fingerprint &&
          _isFresh(cached)) {
        return cached.infos;
      }
    }

    try {
      final snapshot = await _fetchDeduplicated(provider, key, fingerprint);
      return snapshot.infos;
    } on AiException catch (e) {
      final stale = _memory[provider];
      if (!forceRefresh &&
          stale != null &&
          stale.fingerprint == fingerprint &&
          OpenAiCompatibleClient.isRetryable(e.kind)) {
        return stale.infos;
      }
      rethrow;
    }
  }

  @override
  Future<AiModelInfo?> findModel(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) async {
    final id = modelId.trim();
    if (id.isEmpty) return null;
    final models = await listModels(provider, apiKey: apiKey);
    final match = _match(models, id, (m) => m.id);
    if (match != null) return match;
    if (ProviderConfig.of(provider).capabilityStrategy ==
        CapabilityStrategy.liveCatalog) {
      return (await _fetchSingle(provider, id, throwOnError: true))?.info;
    }
    return null;
  }

  @override
  Future<void> verifyApiKey(AiProvider provider, String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw AiException(
        AiErrorKind.notConfigured,
        'No ${provider.displayName} API key entered',
      );
    }
    final config = ProviderConfig.of(provider);
    final decoded = await _listClient.getJson(
      config.keyVerificationUrl,
      apiKey: key,
    );
    if (provider == AiProvider.openai) {
      // Same request as the model list: keep the result.
      try {
        final snapshot = _Snapshot(
          fetchedAt: _clock(),
          fingerprint: keyFingerprint(key),
          entries: parseOpenAiModels(decoded),
        );
        _memory[provider] = snapshot;
        await _writePersisted(provider, snapshot);
      } on AiException {
        // The key works; the list format is someone else's problem.
      }
    }
  }

  @override
  Future<ModelProfile> resolveProfile(
    AiProvider provider,
    String modelId, {
    required String apiKey,
  }) async {
    final id = modelId.trim();
    try {
      if (ProviderConfig.of(provider).capabilityStrategy ==
          CapabilityStrategy.idHeuristics) {
        return ModelHeuristics.guessProfile(provider, id);
      }
      await _loadPersisted(provider);
      final snapshot = _memory[provider];
      final cached = snapshot == null
          ? null
          : _match(snapshot.entries, id, (e) => e.info.id);
      if (cached != null) return cached.profile;
      final single = await _fetchSingle(provider, id, throwOnError: false);
      if (single != null) return single.profile;
    } catch (_) {
      // Fall through to heuristics.
    }
    return ModelHeuristics.guessProfile(provider, id);
  }

  // ---------------------------------------------------------------------------

  bool _isFresh(_Snapshot snapshot) {
    final age = _clock().difference(snapshot.fetchedAt);
    // A timestamp from the future (clock change) counts as stale.
    return !age.isNegative && age < cacheTtl;
  }

  static T? _match<T>(Iterable<T> items, String id, String Function(T) idOf) {
    T? caseInsensitive;
    final lower = id.toLowerCase();
    for (final item in items) {
      final itemId = idOf(item);
      if (itemId == id) return item;
      if (caseInsensitive == null && itemId.toLowerCase() == lower) {
        caseInsensitive = item;
      }
    }
    return caseInsensitive;
  }

  Future<_Snapshot> _fetchDeduplicated(
    AiProvider provider,
    String key,
    String fingerprint,
  ) {
    final running = _inFlight[provider];
    if (running != null) return running;
    final future = _fetch(provider, key, fingerprint).whenComplete(() {
      _inFlight.remove(provider);
    });
    _inFlight[provider] = future;
    return future;
  }

  Future<_Snapshot> _fetch(
    AiProvider provider,
    String key,
    String fingerprint,
  ) async {
    final config = ProviderConfig.of(provider);
    final decoded = await _listClient.getJson(
      config.modelsUrl,
      apiKey: config.modelListRequiresKey ? key : null,
    );
    final entries = switch (provider) {
      AiProvider.openai => parseOpenAiModels(decoded),
      AiProvider.opper => parseOpperModels(decoded),
    };
    final snapshot = _Snapshot(
      fetchedAt: _clock(),
      fingerprint: fingerprint,
      entries: entries,
    );
    _memory[provider] = snapshot;
    await _writePersisted(provider, snapshot);
    return snapshot;
  }

  Future<CatalogEntry?> _fetchSingle(
    AiProvider provider,
    String id, {
    required bool throwOnError,
  }) async {
    final cacheKey = '${provider.id}|$id';
    if (_singleModels.containsKey(cacheKey)) return _singleModels[cacheKey];
    final url = ProviderConfig.of(provider).singleModelUrl(id);
    if (url == null) return null;
    try {
      final decoded = await _probeClient.getJson(url);
      final data = decoded is Map && decoded['data'] is Map
          ? decoded['data']
          : decoded;
      final row = data is Map
          ? _OpperRow.fromJson(Map<String, dynamic>.from(data))
          : null;
      final entry = row?.toEntry(
        recommended: row.id == AiProvider.opper.defaultModel,
      );
      _singleModels[cacheKey] = entry;
      return entry;
    } on AiException catch (e) {
      if (e.kind == AiErrorKind.modelNotFound) {
        _singleModels[cacheKey] = null;
        return null;
      }
      if (throwOnError) rethrow;
      return null;
    }
  }

  /// Loads the persisted list into memory once per session.
  Future<void> _loadPersisted(AiProvider provider) =>
      _persistedLoads[provider] ??= _readPersisted(provider);

  Future<void> _readPersisted(AiProvider provider) async {
    if (_memory[provider] != null) return;
    final raw = await _cacheStore.read(provider.id);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['version'] != _cacheVersion) return;
      final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
      final models = json['models'];
      if (fetchedAt == null || models is! List) return;
      final entries = <CatalogEntry>[];
      for (final model in models) {
        if (model is Map) {
          try {
            entries.add(
              CatalogEntry.fromJson(Map<String, dynamic>.from(model)),
            );
          } catch (_) {
            // Skip a corrupt entry.
          }
        }
      }
      // Do not overwrite a list fetched while the file was being read.
      _memory[provider] ??= _Snapshot(
        fetchedAt: fetchedAt,
        fingerprint: json['key'] as String? ?? '',
        entries: entries,
      );
    } catch (_) {
      // Corrupt cache: ignore.
    }
  }

  Future<void> _writePersisted(AiProvider provider, _Snapshot snapshot) async {
    try {
      await _cacheStore.write(
        provider.id,
        jsonEncode({
          'version': _cacheVersion,
          'fetchedAt': snapshot.fetchedAt.toIso8601String(),
          'key': snapshot.fingerprint,
          'models': [for (final e in snapshot.entries) e.toJson()],
        }),
      );
    } catch (_) {
      // Ignore: the cache is optional.
    }
  }

  // ---------------------------------------------------------------------------
  // Mapping (public for tests)

  /// Maps an Opper `GET /v3/models` response to sorted catalogue entries.
  static List<CatalogEntry> parseOpperModels(Object? decoded) {
    final List<Object?> items = switch (decoded) {
      {'models': final List<Object?> models} => models,
      {'data': final List<Object?> data} => data,
      final List<Object?> list => list,
      _ => throw const AiException(
        AiErrorKind.invalidResponse,
        'Unexpected Opper model list format',
      ),
    };
    final rows = <_OpperRow>[];
    final seen = <String>{};
    for (final item in items) {
      if (item is! Map) continue;
      final row = _OpperRow.fromJson(Map<String, dynamic>.from(item));
      if (row == null || row.serviceTier == 'batch') continue;
      if (seen.add(row.id)) rows.add(row);
    }

    // Featured first-party routes with structured output + vision, one route
    // per underlying model (shortest id wins), plus the provider default.
    final recommendedByModel = <String, _OpperRow>{};
    for (final row in rows.where((r) => r.isRecommendationCandidate)) {
      final current = recommendedByModel[row.modelKey];
      if (current == null || row.id.length < current.id.length) {
        recommendedByModel[row.modelKey] = row;
      }
    }
    final recommendedIds = {
      for (final row in recommendedByModel.values) row.id,
      AiProvider.opper.defaultModel,
    };
    final entries = [
      for (final row in rows)
        row.toEntry(recommended: recommendedIds.contains(row.id)),
    ];
    return sortEntries(entries, AiProvider.opper);
  }

  /// Maps an OpenAI `GET /v1/models` response to sorted catalogue entries.
  static List<CatalogEntry> parseOpenAiModels(Object? decoded) {
    final data = decoded is Map ? decoded['data'] : decoded;
    if (data is! List) {
      throw const AiException(
        AiErrorKind.invalidResponse,
        'Unexpected OpenAI model list format',
      );
    }
    final seen = <String>{};
    final entries = <CatalogEntry>[];
    for (final item in data) {
      final id = item is Map ? item['id'] : null;
      if (id is! String || id.trim().isEmpty) continue;
      if (!ModelHeuristics.isOpenAiChatModel(id) || !seen.add(id)) continue;
      final profile = ModelHeuristics.openAiProfile(id);
      entries.add(
        CatalogEntry(
          AiModelInfo(
            id: id,
            provider: AiProvider.openai,
            vendor: 'OpenAI',
            supportsStructuredOutput: profile.supportsStructuredOutput,
            supportsVision: profile.supportsVision,
            recommended: recommendedOpenAiModels.contains(id),
          ),
          profile,
        ),
      );
    }
    return sortEntries(entries, AiProvider.openai);
  }

  /// Recommended first (the provider default leading), then by vendor and
  /// name.
  static List<CatalogEntry> sortEntries(
    List<CatalogEntry> entries,
    AiProvider provider,
  ) {
    int rank(AiModelInfo m) {
      if (m.id == provider.defaultModel) return 0;
      return m.recommended ? 1 : 2;
    }

    final sorted = [...entries];
    sorted.sort((a, b) {
      final x = a.info, y = b.info;
      final byRank = rank(x).compareTo(rank(y));
      if (byRank != 0) return byRank;
      final byVendor = (x.vendor ?? '').toLowerCase().compareTo(
        (y.vendor ?? '').toLowerCase(),
      );
      if (byVendor != 0) return byVendor;
      final byName = x.displayName.toLowerCase().compareTo(
        y.displayName.toLowerCase(),
      );
      return byName != 0 ? byName : x.id.compareTo(y.id);
    });
    return sorted;
  }

  /// Non-reversible short fingerprint of an API key, used only to invalidate
  /// a cached (per-account) model list when the key changes. The key itself
  /// is never persisted.
  static String keyFingerprint(String key) {
    var a = 7, b = 11;
    for (final unit in key.codeUnits) {
      a = (a * 31 + unit) % 2147483647;
      b = (b * 131 + unit) % 2147483629;
    }
    return '${a.toRadixString(36)}${b.toRadixString(36)}';
  }
}

class _Snapshot {
  _Snapshot({
    required this.fetchedAt,
    required this.fingerprint,
    required this.entries,
  });

  final DateTime fetchedAt;
  final String fingerprint;
  final List<CatalogEntry> entries;

  late final List<AiModelInfo> infos = List.unmodifiable(
    entries.map((e) => e.info),
  );
}

/// The fields of one Opper catalogue row the app uses.
class _OpperRow {
  _OpperRow({
    required this.id,
    required this.name,
    required this.capabilities,
    required this.inputModalities,
    required this.featured,
    required this.serviceTier,
    required this.providerSlug,
    required this.providerName,
    required this.makerSlug,
    required this.makerName,
    required this.modelKey,
    required this.description,
    required this.speed,
    required this.quality,
    required this.contextWindow,
    required this.reasoningEfforts,
    required this.temperature,
  });

  final String id;
  final String name;
  final Set<String> capabilities;
  final Set<String> inputModalities;
  final bool featured;
  final String? serviceTier;
  final String? providerSlug;
  final String? providerName;
  final String? makerSlug;
  final String? makerName;
  final String modelKey;
  final String? description;
  final String? speed;
  final String? quality;
  final int? contextWindow;
  final List<String> reasoningEfforts;
  final Map<String, dynamic>? temperature;

  static _OpperRow? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final type = json['type'];
    if (type is String && type != 'llm') return null;

    Set<String> strings(Object? value) =>
        value is List ? value.whereType<String>().toSet() : <String>{};
    String? nonBlank(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    String? nested(String key, String field) {
      final value = json[key];
      return value is Map ? nonBlank(value[field]) : null;
    }

    final params = json['params'] is Map
        ? Map<String, dynamic>.from(json['params'] as Map)
        : const <String, dynamic>{};
    final reasoning = params['reasoning'];
    final temperature = params['temperature'];

    return _OpperRow(
      id: id.trim(),
      name: nonBlank(json['name']) ?? id.trim(),
      capabilities: strings(json['capabilities']),
      inputModalities: strings(json['input_modalities']),
      featured: json['featured'] == true,
      serviceTier: nonBlank(json['service_tier']),
      providerSlug: nested('provider', 'slug'),
      providerName: nested('provider', 'display_name'),
      makerSlug: nested('maker', 'slug'),
      makerName: nested('maker', 'display_name'),
      modelKey: nonBlank(json['model']) ?? id.trim(),
      description: nonBlank(json['description']),
      speed: nonBlank(json['speed']),
      quality: nonBlank(json['quality']),
      contextWindow: (json['context_window'] as num?)?.toInt(),
      reasoningEfforts: reasoning is Map
          ? strings(reasoning['supported']).toList()
          : const [],
      temperature: temperature is Map
          ? Map<String, dynamic>.from(temperature)
          : null,
    );
  }

  String get routePrefix =>
      id.contains('/') ? id.substring(0, id.indexOf('/')) : '';

  bool get supportsStructuredOutput =>
      capabilities.contains('structured_output');

  bool get supportsVision =>
      capabilities.contains('vision') || inputModalities.contains('image');

  /// Featured, standard tier, served by the model maker itself through a
  /// plain route (no region/tier qualifier), usable with photos and schemas.
  bool get isRecommendationCandidate =>
      featured &&
      serviceTier == null &&
      supportsStructuredOutput &&
      supportsVision &&
      providerSlug != null &&
      providerSlug == makerSlug &&
      !routePrefix.contains(':') &&
      !routePrefix.contains('-');

  /// Name plus the host (when not the maker) and route qualifiers, so the
  /// many routes of one model can be told apart: `GLM-5.3 (DeepInfra, flex)`.
  String get displayName {
    final extras = <String>[
      if (providerName != null && providerSlug != makerSlug) providerName!,
      for (final qualifier in routePrefix.split(':').skip(1))
        qualifier.length <= 2 ? qualifier.toUpperCase() : qualifier,
    ];
    return extras.isEmpty ? name : '$name (${extras.join(', ')})';
  }

  static const List<String> _effortOrder = [
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];

  CatalogEntry toEntry({required bool recommended}) {
    final efforts = [...reasoningEfforts]
      ..sort((a, b) {
        int index(String e) {
          final i = _effortOrder.indexOf(e);
          return i < 0 ? _effortOrder.length : i;
        }

        return index(a).compareTo(index(b));
      });
    final info = AiModelInfo(
      id: id,
      displayName: displayName,
      provider: AiProvider.opper,
      supportsStructuredOutput: supportsStructuredOutput,
      supportsVision: supportsVision,
      description: description,
      vendor: makerName ?? providerName,
      speed: speed,
      quality: quality,
      contextWindow: contextWindow,
      recommended: recommended,
    );
    final temperature = this.temperature;
    return CatalogEntry(
      info,
      ModelProfile(
        modelId: id,
        supportsStructuredOutput: supportsStructuredOutput,
        supportsVision: supportsVision,
        reasoningEfforts: efforts,
        acceptsTemperature: temperature != null,
        minTemperature: (temperature?['min'] as num?)?.toDouble(),
        maxTemperature: (temperature?['max'] as num?)?.toDouble(),
      ),
    );
  }
}
