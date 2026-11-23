import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/ai_model_info.dart';
import '../models/ai_provider.dart';
import '../models/settings.dart';
import '../providers/app_state_provider.dart';
import '../services/ai/ai_exceptions.dart';
import '../services/ai/ai_service_factory.dart';
import '../services/ai/model_catalog.dart';
import '../widgets/settings/api_key_field.dart';
import '../widgets/settings/external_links.dart';
import '../widgets/settings/model_display.dart';
import '../widgets/settings/model_picker.dart';
import '../widgets/settings/selected_model_tile.dart';
import '../widgets/settings/settings_section.dart';
import '../widgets/settings/snap_status_tile.dart';

/// App settings: provider, API key, model, sharing, appearance, advanced
/// request options and about.
///
/// Persistence model: **auto-save**. Every change is written immediately via
/// [AppStateProvider.updateSettings]; API key typing is debounced
/// ([keySaveDelay]) and flushed when the field loses focus, before verifying
/// or picking a model, and when the screen is closed, so nothing is lost on
/// back navigation. Saves are serialised and always write the latest state;
/// failures keep the edit and offer a retry.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// How long API key typing must pause before the key is saved.
  static const keySaveDelay = Duration(milliseconds: 700);

  /// Project page shown in the About section.
  static final sourceCodeUrl = Uri.parse(
    'https://github.com/nahu02/EventSnap2',
  );

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _KeyCheckStatus { checking, valid, invalid }

/// Result of verifying [key] (only shown while the field still holds it).
class _KeyCheck {
  const _KeyCheck(this.key, this.status, [this.message]);

  final String key;
  final _KeyCheckStatus status;
  final String? message;
}

typedef _ModelRef = ({AiProvider provider, String id});

/// Catalog lookup of the selected model's capabilities.
class _ModelLookup {
  _ModelLookup({
    required this.apiKey,
    this.loading = true,
    this.info,
    this.failed = false,
  });

  /// Key the lookup ran with (OpenAI model lists depend on it).
  final String apiKey;
  final bool loading;
  final AiModelInfo? info;

  /// The lookup itself failed (as opposed to the model not being listed).
  final bool failed;
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppStateProvider _appState;
  late final ModelCatalog _catalog;
  late final Future<String?> _version;

  /// Local edits not yet confirmed as saved; `null` when in sync.
  Settings? _pending;
  Timer? _keySaveTimer;
  bool _saving = false;
  bool _saveAgain = false;
  Future<void>? _inFlight;
  bool _popping = false;
  bool _disposed = false;

  final Map<AiProvider, _KeyCheck> _keyChecks = {};
  final Map<_ModelRef, _ModelLookup> _lookups = {};

  Settings get _settings => _pending ?? _appState.settings;

  bool get _alive => mounted && !_disposed;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppStateProvider>();
    _catalog = context.read<AiServiceFactory>().modelCatalog;
    _version = _loadVersion();
    _appState.addListener(_onAppStateChanged);
    if (_appState.isInitialized) _ensureModelInfo();
  }

  @override
  void dispose() {
    _disposed = true;
    _appState.removeListener(_onAppStateChanged);
    _keySaveTimer?.cancel();
    if (_pending != null) unawaited(_persist());
    super.dispose();
  }

  static Future<String?> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isEmpty) return null;
      final build = info.buildNumber.trim();
      return (build.isEmpty || build == version)
          ? version
          : '$version ($build)';
    } catch (_) {
      return null;
    }
  }

  void _onAppStateChanged() {
    if (_alive) _ensureModelInfo();
  }

  // --- Persistence -----------------------------------------------------------

  /// Applies [change] locally and (unless [persist] is false) saves it.
  void _apply(
    Settings Function(Settings current) change, {
    bool persist = true,
  }) {
    final before = _settings;
    final next = change(before);
    if (next != before) {
      setState(() => _pending = next);
      if (next.provider != before.provider ||
          next.activeModel != before.activeModel) {
        _ensureModelInfo();
      }
    }
    // Also persists edits applied earlier without saving (slider drags).
    if (persist && _pending != null) unawaited(_persist());
  }

  /// Saves the latest local edits; concurrent calls coalesce.
  ///
  /// The returned future completes when everything pending is saved (also for
  /// calls that coalesce into a running save).
  Future<void> _persist() {
    _keySaveTimer?.cancel();
    if (_saving) {
      _saveAgain = true;
      return _inFlight ?? Future<void>.value();
    }
    return _inFlight = _runPersist();
  }

  Future<void> _runPersist() async {
    _saving = true;
    try {
      do {
        _saveAgain = false;
        final target = _pending;
        if (target == null) break;
        if (target != _appState.settings) {
          try {
            await _appState.updateSettings(target);
          } catch (_) {
            _showSaveError();
            break;
          }
        }
        if (_pending == target) {
          if (_alive) {
            setState(() => _pending = null);
          } else {
            _pending = null;
          }
        }
      } while (_saveAgain);
    } finally {
      _saving = false;
    }
  }

  /// Saves pending edits before the route pops, so screens below (e.g. Home
  /// auto-processing a share) see the new settings.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || _popping) return;
    _popping = true;
    try {
      await _persist();
    } finally {
      _popping = false;
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  /// Saves a debounced API key right away.
  void _flushPendingKey() {
    if (_keySaveTimer?.isActive ?? false) unawaited(_persist());
  }

  void _showSaveError() {
    if (!_alive) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: const Text("Couldn't save your changes"),
          action: SnackBarAction(label: 'Retry', onPressed: _persist),
        ),
      );
  }

  // --- Actions -----------------------------------------------------------------

  void _onApiKeyChanged(String key) {
    _apply((s) => s.copyWithApiKey(s.provider, key), persist: false);
    _keySaveTimer?.cancel();
    _keySaveTimer = Timer(SettingsScreen.keySaveDelay, () {
      unawaited(_persist());
    });
  }

  Future<void> _verifyKey() async {
    final settings = _settings;
    final provider = settings.provider;
    final key = settings.activeApiKey;
    if (key.isEmpty) return;
    _flushPendingKey();
    setState(() {
      _keyChecks[provider] = _KeyCheck(key, _KeyCheckStatus.checking);
    });

    _KeyCheck result;
    try {
      await _catalog.verifyApiKey(provider, key);
      result = _KeyCheck(key, _KeyCheckStatus.valid);
    } on AiException catch (e) {
      result = _KeyCheck(
        key,
        _KeyCheckStatus.invalid,
        _verifyError(provider, e),
      );
    } catch (_) {
      result = _KeyCheck(
        key,
        _KeyCheckStatus.invalid,
        AiException.userMessageFor(AiErrorKind.unknown),
      );
    }
    if (!_alive || _keyChecks[provider]?.key != key) return;
    setState(() => _keyChecks[provider] = result);
  }

  static String _verifyError(AiProvider provider, AiException e) {
    return switch (e.kind) {
      AiErrorKind.auth =>
        '${provider.displayName} rejected this key. Check that you copied '
            'all of it.',
      AiErrorKind.notConfigured => 'Enter an API key first.',
      _ => e.userMessage,
    };
  }

  Future<void> _chooseModel() async {
    final settings = _settings;
    final provider = settings.provider;
    _flushPendingKey();
    final picked = await showModelPicker(
      context,
      catalog: _catalog,
      provider: provider,
      apiKey: settings.activeApiKey,
      selectedModelId: settings.activeModel,
    );
    if (picked == null || !_alive) return;
    // A bare custom id carries no metadata: let the catalog lookup decide
    // whether it is listed (otherwise it would look like a known model).
    final bare =
        picked.displayName == picked.id &&
        picked.vendor == null &&
        picked.supportsStructuredOutput == null &&
        picked.supportsVision == null;
    if (!bare) {
      _lookups[(provider: provider, id: picked.id)] = _ModelLookup(
        apiKey: settings.activeApiKey,
        loading: false,
        info: picked,
      );
    }
    _apply((s) => s.copyWithModel(provider, picked.id));
  }

  // --- Model capabilities ------------------------------------------------------

  /// Looks up the selected model's metadata unless already known. Unknown
  /// results are retried once the API key changes.
  void _ensureModelInfo() {
    final settings = _settings;
    final id = settings.activeModel.trim();
    if (id.isEmpty) return;
    final ref = (provider: settings.provider, id: id);
    final apiKey = settings.activeApiKey;
    final existing = _lookups[ref];
    if (existing != null &&
        (existing.loading ||
            existing.info != null ||
            existing.apiKey == apiKey)) {
      return;
    }
    final lookup = _ModelLookup(apiKey: apiKey);
    _lookups[ref] = lookup;
    unawaited(_runLookup(ref, lookup));
  }

  Future<void> _runLookup(_ModelRef ref, _ModelLookup lookup) async {
    AiModelInfo? info;
    var failed = false;
    try {
      info = await _catalog.findModel(
        ref.provider,
        ref.id,
        apiKey: lookup.apiKey,
      );
    } catch (_) {
      info = null;
      failed = true;
    }
    if (!identical(_lookups[ref], lookup)) return;
    final done = _ModelLookup(
      apiKey: lookup.apiKey,
      loading: false,
      info: info,
      failed: failed,
    );
    if (_alive) {
      setState(() => _lookups[ref] = done);
    } else {
      _lookups[ref] = done;
    }
  }

  // --- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    return PopScope<Object?>(
      canPop: _pending == null,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: !appState.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final gutter = math.max(
                    16.0,
                    (constraints.maxWidth - 640) / 2,
                  );
                  final settings = _settings;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      32 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildProviderSection(context, settings),
                        _buildApiKeySection(context, settings),
                        _buildModelSection(context, settings),
                        _buildSharingSection(settings),
                        _buildAppearanceSection(context, settings),
                        _buildAdvancedSection(context, settings),
                        _buildAboutSection(context, settings),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildProviderSection(BuildContext context, Settings settings) {
    final theme = Theme.of(context);
    return SettingsSection(
      title: 'AI provider',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSegmentedButton<AiProvider>(
                options: [
                  for (final p in AiProvider.values)
                    SettingsOption(p, p.displayName),
                ],
                selected: settings.provider,
                onChanged: (p) => _apply((s) => s.copyWith(provider: p)),
              ),
              const SizedBox(height: 12),
              for (final p in AiProvider.values)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${p.displayName}: ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ModelLabels.providerDescription(p)),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: p == settings.provider
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeySection(BuildContext context, Settings settings) {
    final provider = settings.provider;
    final key = settings.activeApiKey;
    final check = _keyChecks[provider];
    final keyWarnings = settings
        .warnings()
        .where((w) => w.startsWith(provider.displayName))
        .toList();

    return SettingsSection(
      title: 'API key',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ApiKeyField(
                key: ValueKey(provider),
                provider: provider,
                initialValue: key,
                onChanged: _onApiKeyChanged,
                onCommit: _flushPendingKey,
              ),
              for (final warning in keyWarnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SettingsNotice(message: warning),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        key.isEmpty || check?.status == _KeyCheckStatus.checking
                        ? null
                        : _verifyKey,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verify key'),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        ExternalLinks.open(context, provider.apiKeyHelpUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Get a key'),
                  ),
                ],
              ),
              if (check != null && check.key == key)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _KeyCheckView(check: check, provider: provider),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelSection(BuildContext context, Settings settings) {
    final id = settings.activeModel.trim();
    final lookup = _lookups[(provider: settings.provider, id: id)];
    final info = lookup?.info;
    final warnings = [
      if (info?.supportsStructuredOutput == false)
        "This model doesn't support structured output, so results may be "
            'less reliable.',
      if (info?.supportsVision == false)
        "This model can't read images, so photos won't work with it.",
    ];

    return SettingsSection(
      title: 'Model',
      children: [
        SelectedModelTile(
          modelId: id,
          info: info,
          loading: lookup?.loading ?? false,
          lookupFailed: lookup?.failed ?? false,
          onTap: _chooseModel,
        ),
        if (warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, warning) in warnings.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                    child: SettingsNotice(message: warning),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSharingSection(Settings settings) {
    return SettingsSection(
      title: 'Sharing',
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.share_outlined),
          title: const Text('Auto-process shared content'),
          subtitle: const Text(
            'Find events as soon as text or a photo is shared to EventSnap',
          ),
          value: settings.autoProcessShared,
          onChanged: (value) =>
              _apply((s) => s.copyWith(autoProcessShared: value)),
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.screenshot_outlined),
          title: const Text('Auto-process screen snaps'),
          subtitle: Text(
            'The screenshot is then sent to ${settings.provider.displayName} '
            'without confirmation',
          ),
          value: settings.autoProcessSnaps,
          onChanged: (value) =>
              _apply((s) => s.copyWith(autoProcessSnaps: value)),
        ),
        const Divider(height: 1),
        const SnapStatusTile(),
      ],
    );
  }

  Widget _buildAppearanceSection(BuildContext context, Settings settings) {
    final theme = Theme.of(context);
    return SettingsSection(
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Theme', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
              SettingsSegmentedButton<AppThemeMode>(
                options: const [
                  SettingsOption(
                    AppThemeMode.system,
                    'System',
                    icon: Icons.brightness_auto_outlined,
                  ),
                  SettingsOption(
                    AppThemeMode.light,
                    'Light',
                    icon: Icons.light_mode_outlined,
                  ),
                  SettingsOption(
                    AppThemeMode.dark,
                    'Dark',
                    icon: Icons.dark_mode_outlined,
                  ),
                ],
                selected: settings.themeMode,
                onChanged: (mode) => _apply((s) => s.copyWith(themeMode: mode)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSection(BuildContext context, Settings settings) {
    final theme = Theme.of(context);
    final structured = switch (settings.structuredOutputMode) {
      StructuredOutputMode.auto => 'Structured output auto',
      StructuredOutputMode.off => 'Structured output off',
    };
    final summary =
        '$structured · ${_retriesLabel(settings.maxRetries)} · '
        '${settings.timeoutSeconds} s timeout';

    return SettingsSection(
      title: 'Advanced',
      children: [
        ExpansionTile(
          key: const PageStorageKey('settings_advanced'),
          leading: const Icon(Icons.tune),
          title: const Text('Request options and debugging'),
          subtitle: Text(summary),
          shape: const Border(),
          collapsedShape: const Border(),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Structured output', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Auto asks models that support it for schema-checked '
                    'JSON. Turn it off if a model keeps failing.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SettingsSegmentedButton<StructuredOutputMode>(
                    options: const [
                      SettingsOption(StructuredOutputMode.auto, 'Auto'),
                      SettingsOption(StructuredOutputMode.off, 'Off'),
                    ],
                    selected: settings.structuredOutputMode,
                    onChanged: (mode) =>
                        _apply((s) => s.copyWith(structuredOutputMode: mode)),
                  ),
                ],
              ),
            ),
            SettingsSlider(
              key: const Key('settings_max_retries'),
              title: 'Max retries',
              description: 'Extra attempts after network errors or timeouts',
              value: settings.maxRetries,
              min: Settings.minRetries,
              max: Settings.maxRetriesLimit,
              format: (v) => '$v',
              onChanged: (v) =>
                  _apply((s) => s.copyWith(maxRetries: v), persist: false),
              onChangeEnd: (v) => _apply((s) => s.copyWith(maxRetries: v)),
            ),
            SettingsSlider(
              key: const Key('settings_timeout'),
              title: 'Timeout',
              description: 'How long to wait for the AI to answer',
              value: settings.timeoutSeconds,
              min: Settings.minTimeoutSeconds,
              max: Settings.maxTimeoutSeconds,
              step: 5,
              format: (v) => '$v s',
              onChanged: (v) =>
                  _apply((s) => s.copyWith(timeoutSeconds: v), persist: false),
              onChangeEnd: (v) => _apply((s) => s.copyWith(timeoutSeconds: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('Debug mode'),
              subtitle: const Text(
                'Show the raw AI response on the review screen',
              ),
              value: settings.debugMode,
              onChanged: (value) => _apply((s) => s.copyWith(debugMode: value)),
            ),
          ],
        ),
      ],
    );
  }

  static String _retriesLabel(int retries) =>
      retries == 1 ? '1 retry' : '$retries retries';

  Widget _buildAboutSection(BuildContext context, Settings settings) {
    return SettingsSection(
      title: 'About',
      children: [
        FutureBuilder<String?>(
          future: _version,
          builder: (context, snapshot) {
            final version =
                snapshot.data ??
                (snapshot.connectionState == ConnectionState.done
                    ? 'Unknown'
                    : 'Loading…');
            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Version'),
              subtitle: Text(version),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('Source code'),
          subtitle: Text(
            '${SettingsScreen.sourceCodeUrl.host}'
            '${SettingsScreen.sourceCodeUrl.path}',
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () =>
              ExternalLinks.open(context, SettingsScreen.sourceCodeUrl),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy'),
          subtitle: Text(
            'Your text and images are sent to '
            '${settings.provider.displayName} for processing. API keys are '
            'stored securely on this device.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          onTap: () async {
            final version = await _version;
            if (!context.mounted) return;
            showLicensePage(
              context: context,
              applicationName: 'EventSnap',
              applicationVersion: version,
            );
          },
        ),
      ],
    );
  }
}

/// Inline result of an API key check.
class _KeyCheckView extends StatelessWidget {
  const _KeyCheckView({required this.check, required this.provider});

  final _KeyCheck check;
  final AiProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Widget leading, String text, Color color) = switch (check.status) {
      _KeyCheckStatus.checking => (
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        'Checking key…',
        scheme.onSurfaceVariant,
      ),
      _KeyCheckStatus.valid => (
        Icon(Icons.check_circle_outline, size: 20, color: scheme.primary),
        'Key works with ${provider.displayName}',
        scheme.primary,
      ),
      _KeyCheckStatus.invalid => (
        Icon(Icons.error_outline, size: 20, color: scheme.error),
        check.message ?? AiException.userMessageFor(AiErrorKind.unknown),
        scheme.error,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
