import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ai_model_info.dart';
import '../../models/ai_provider.dart';
import '../../services/ai/ai_exceptions.dart';
import '../../services/ai/model_catalog.dart';
import 'capability_badges.dart';
import 'model_display.dart';

/// Opens the [ModelPickerScreen] as a full-screen dialog.
///
/// Completes with the chosen model, or `null` when dismissed. A custom model
/// id that is not in the catalog comes back as an [AiModelInfo] with unknown
/// capabilities.
Future<AiModelInfo?> showModelPicker(
  BuildContext context, {
  required ModelCatalog catalog,
  required AiProvider provider,
  required String apiKey,
  String? selectedModelId,
}) {
  return Navigator.of(context).push<AiModelInfo>(
    MaterialPageRoute<AiModelInfo>(
      fullscreenDialog: true,
      builder: (_) => ModelPickerScreen(
        catalog: catalog,
        provider: provider,
        apiKey: apiKey,
        selectedModelId: selectedModelId,
      ),
    ),
  );
}

/// Searchable, filterable list of a provider's models.
///
/// Recommended models come first. Handles catalogs with well over a thousand
/// entries: rows are built lazily and filtering works on a precomputed index.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({
    super.key,
    required this.catalog,
    required this.provider,
    required this.apiKey,
    this.selectedModelId,
  });

  final ModelCatalog catalog;
  final AiProvider provider;
  final String apiKey;
  final String? selectedModelId;

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  final _searchController = TextEditingController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  List<AiModelInfo>? _models;
  List<String> _searchIndex = const [];
  Object? _error;
  bool _loading = true;
  int _loadGeneration = 0;

  bool _requireStructuredOutput = false;
  bool _requireVision = false;

  List<_Entry> _entries = const [];
  int _matchCount = 0;

  /// The search text looks like a model id that is not in the catalog.
  bool _offerQueryAsId = false;

  String get _query => _searchController.text.trim();
  bool get _hasFilters =>
      _query.isNotEmpty || _requireStructuredOutput || _requireVision;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    if (_models == null && !_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final models = await widget.catalog.listModels(
        widget.provider,
        apiKey: widget.apiKey,
        forceRefresh: forceRefresh,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _models = List.unmodifiable(models);
        _searchIndex = [for (final m in models) _indexText(m)];
        _error = null;
        _loading = false;
        _rebuildEntries();
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      final hadModels = _models != null;
      setState(() {
        _loading = false;
        if (!hadModels) _error = error;
      });
      if (hadModels) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(_errorMessage(error)),
          ),
        );
      }
    }
  }

  void _refresh() {
    final indicator = _refreshKey.currentState;
    if (indicator != null) {
      indicator.show();
    } else {
      _load(forceRefresh: true);
    }
  }

  // --- Filtering -----------------------------------------------------------

  static final _separators = RegExp(r'[\s\-_/.:]+');

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(_separators, ' ');

  static String _indexText(AiModelInfo m) =>
      _normalize('${m.id} ${m.displayName} ${m.vendor ?? ''}');

  void _rebuildEntries() {
    final models = _models ?? const <AiModelInfo>[];
    final tokens = _normalize(_query)
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final recommended = <AiModelInfo>[];
    final others = <AiModelInfo>[];
    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      if (_requireStructuredOutput && model.supportsStructuredOutput != true) {
        continue;
      }
      if (_requireVision && model.supportsVision != true) continue;
      if (tokens.isNotEmpty) {
        final haystack = _searchIndex[i];
        if (!tokens.every(haystack.contains)) continue;
      }
      (model.recommended ? recommended : others).add(model);
    }

    final query = _query;
    final selected = widget.selectedModelId?.trim() ?? '';
    _offerQueryAsId =
        query.isNotEmpty &&
        !query.contains(RegExp(r'\s')) &&
        !models.any((m) => m.id == query);
    final selectedIsCustom =
        selected.isNotEmpty && !models.any((m) => m.id == selected);

    _matchCount = recommended.length + others.length;
    _entries = [
      if (_offerQueryAsId) _CustomEntry(query),
      if (selectedIsCustom && !_hasFilters) ...[
        const _HeaderEntry('Current model'),
        _ModelEntry(
          AiModelInfo(id: selected, provider: widget.provider),
          notInList: true,
        ),
      ],
      if (recommended.isNotEmpty) ...[
        const _HeaderEntry('Recommended'),
        for (final m in recommended) _ModelEntry(m),
      ],
      if (others.isNotEmpty) ...[
        _HeaderEntry(recommended.isEmpty ? 'Models' : 'All models'),
        for (final m in others) _ModelEntry(m),
      ],
      if (_matchCount > 0) const _CustomEntry(null),
    ];
  }

  void _updateFilters(VoidCallback change) {
    setState(() {
      change();
      _rebuildEntries();
    });
  }

  void _clearFilters() {
    _updateFilters(() {
      _searchController.clear();
      _requireStructuredOutput = false;
      _requireVision = false;
    });
  }

  // --- Selection -------------------------------------------------------------

  void _select(AiModelInfo model) => Navigator.of(context).pop(model);

  void _selectId(String id) {
    for (final model in _models ?? const <AiModelInfo>[]) {
      if (model.id == id) return _select(model);
    }
    _select(AiModelInfo(id: id, provider: widget.provider));
  }

  Future<void> _promptCustomId([String initial = '']) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) =>
          _CustomModelDialog(provider: widget.provider, initialValue: initial),
    );
    if (!mounted || id == null || id.trim().isEmpty) return;
    _selectId(id.trim());
  }

  // --- Copy ------------------------------------------------------------------

  String _errorMessage(Object error) {
    if (error is AiException) {
      if (error.kind == AiErrorKind.notConfigured ||
          error.kind == AiErrorKind.auth) {
        return 'Add a valid ${widget.provider.displayName} API key to load '
            'the model list.';
      }
      return error.userMessage;
    }
    return AiException.userMessageFor(AiErrorKind.unknown);
  }

  String _countLabel() {
    final format = NumberFormat.decimalPattern();
    final total = _models?.length ?? 0;
    final noun = total == 1 ? 'model' : 'models';
    if (!_hasFilters) return '${format.format(total)} $noun';
    return '${format.format(_matchCount)} of ${format.format(total)} $noun';
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose model'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh model list',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _buildSearchBar(),
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return SearchBar(
      controller: _searchController,
      hintText: 'Search models',
      elevation: const WidgetStatePropertyAll(0),
      leading: const Icon(Icons.search),
      trailing: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear search',
            onPressed: () => _updateFilters(_searchController.clear),
          ),
      ],
      textInputAction: TextInputAction.search,
      onChanged: (_) => _updateFilters(() {}),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _models == null) {
      return const _StateMessage(
        icon: null,
        title: 'Loading models…',
        showProgress: true,
      );
    }

    final error = _error;
    if (_models == null && error != null) {
      return _refreshable(
        _StateMessage(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't load models",
          message: _errorMessage(error),
          actions: [
            FilledButton.icon(
              onPressed: () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            TextButton(
              onPressed: _promptCustomId,
              child: const Text('Use a custom model id'),
            ),
          ],
        ),
      );
    }

    if ((_models ?? const []).isEmpty) {
      return _refreshable(
        _StateMessage(
          icon: Icons.inventory_2_outlined,
          title: 'No models available',
          message:
              '${widget.provider.displayName} did not return any models. '
              'Try again or enter a model id.',
          actions: [
            FilledButton.icon(
              onPressed: () => _load(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            TextButton(
              onPressed: _promptCustomId,
              child: const Text('Use a custom model id'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      key: _refreshKey,
      onRefresh: () => _load(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildFilters(context)),
          if (_matchCount == 0) ...[
            if (_offerQueryAsId)
              SliverToBoxAdapter(
                child: _buildEntry(context, _CustomEntry(_query)),
              ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: _StateMessage(
                icon: Icons.search_off,
                title: 'No matching models',
                message: 'Try another search or turn off a filter.',
                actions: [
                  OutlinedButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear search and filters'),
                  ),
                  if (!_offerQueryAsId)
                    TextButton(
                      onPressed: () => _promptCustomId(_query),
                      child: const Text('Use a custom model id'),
                    ),
                ],
              ),
            ),
          ] else
            SliverList.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) =>
                  _buildEntry(context, _entries[index]),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  /// Wraps a state message so pull-to-refresh still works.
  Widget _refreshable(Widget child) {
    return RefreshIndicator(
      key: _refreshKey,
      onRefresh: () => _load(forceRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
      ),
    );
  }

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Structured output'),
                selected: _requireStructuredOutput,
                onSelected: (value) =>
                    _updateFilters(() => _requireStructuredOutput = value),
              ),
              FilterChip(
                label: const Text('Vision'),
                selected: _requireVision,
                onSelected: (value) =>
                    _updateFilters(() => _requireVision = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _countLabel(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(BuildContext context, _Entry entry) {
    final theme = Theme.of(context);
    switch (entry) {
      case _HeaderEntry(:final title):
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      case _ModelEntry(:final model, :final notInList):
        return ModelListTile(
          model: model,
          notInList: notInList,
          selected: model.id == widget.selectedModelId,
          onTap: () => _select(model),
        );
      case _CustomEntry(:final id):
        return ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: Text(id == null ? 'Use a custom model id' : 'Use “$id”'),
          subtitle: Text(
            id == null
                ? 'Enter any model id ${widget.provider.displayName} accepts'
                : 'Custom model id',
          ),
          onTap: id == null ? _promptCustomId : () => _selectId(id),
        );
    }
  }
}

/// A model row: name, id/vendor/speed/quality line and capability badges.
class ModelListTile extends StatelessWidget {
  const ModelListTile({
    super.key,
    required this.model,
    required this.onTap,
    this.selected = false,
    this.notInList = false,
  });

  final AiModelInfo model;
  final bool selected;

  /// The model isn't in the catalog: show a friendly name, the raw id and a
  /// "Not in list" hint instead of the bare id.
  final bool notInList;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = notInList
        ? '${model.id} · ${ModelLabels.notInList}'
        : ModelLabels.details(model);
    final badges = CapabilityBadges.forModel(model, compact: true);
    return ListTile(
      title: Text(
        notInList ? ModelLabels.friendlyName(model.id) : model.displayName,
      ),
      subtitle: (details.isEmpty && !badges.hasBadges)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (details.isNotEmpty) Text(details),
                if (badges.hasBadges) ...[const SizedBox(height: 6), badges],
              ],
            ),
      trailing: selected
          ? const Icon(Icons.check, semanticLabel: 'Selected')
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

sealed class _Entry {
  const _Entry();
}

class _HeaderEntry extends _Entry {
  const _HeaderEntry(this.title);
  final String title;
}

class _ModelEntry extends _Entry {
  const _ModelEntry(this.model, {this.notInList = false});
  final AiModelInfo model;
  final bool notInList;
}

/// "Use a custom model id" ([id] null) or "Use “query”" shortcut.
class _CustomEntry extends _Entry {
  const _CustomEntry(this.id);
  final String? id;
}

/// Centered icon/progress, title, message and actions.
class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
    this.showProgress = false,
  });

  final IconData? icon;
  final String title;
  final String? message;
  final List<Widget> actions;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for a model id; pops with the trimmed id.
class _CustomModelDialog extends StatefulWidget {
  const _CustomModelDialog({required this.provider, this.initialValue = ''});

  final AiProvider provider;
  final String initialValue;

  @override
  State<_CustomModelDialog> createState() => _CustomModelDialogState();
}

class _CustomModelDialogState extends State<_CustomModelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _controller.text.trim();
    if (id.isEmpty) return;
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return AlertDialog(
      scrollable: true,
      title: const Text('Custom model id'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Model id',
          hintText: 'e.g. ${provider.defaultModel}',
          helperText: 'Use the exact id from ${provider.displayName}.',
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text('Use model'),
        ),
      ],
    );
  }
}
