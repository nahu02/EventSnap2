import 'package:material_ui/material_ui.dart';

import '../../models/ai_model_info.dart';
import 'capability_badges.dart';
import 'model_display.dart';

/// Settings row showing the selected model and its capabilities; tapping it
/// opens the model picker.
class SelectedModelTile extends StatelessWidget {
  const SelectedModelTile({
    super.key,
    required this.modelId,
    required this.onTap,
    this.info,
    this.loading = false,
    this.lookupFailed = false,
  });

  /// The model id stored in the settings.
  final String modelId;

  /// Catalog metadata for [modelId]; `null` when unknown.
  final AiModelInfo? info;

  /// True while [info] is being looked up.
  final bool loading;

  /// The catalog lookup failed, so "not in list" can't be claimed.
  final bool lookupFailed;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = modelId.trim();
    final model = info;
    final notInList =
        id.isNotEmpty && model == null && !loading && !lookupFailed;
    final title = id.isEmpty
        ? 'Choose a model'
        : (model?.displayName ??
              (notInList ? ModelLabels.friendlyName(id) : id));
    final details = model != null
        ? ModelLabels.details(model)
        : (notInList ? '$id · ${ModelLabels.notInList}' : '');

    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (details.isNotEmpty) Text(details),
          if (id.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (loading)
              Text(
                'Checking capabilities…',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              CapabilityBadges.forModel(model),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
