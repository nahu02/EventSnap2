import 'package:material_ui/material_ui.dart';

/// "Provider · model" chip on the home screen; tapping it opens settings.
class ModelStatusChip extends StatelessWidget {
  const ModelStatusChip({
    super.key,
    required this.providerName,
    required this.model,
    this.onPressed,
  });

  final String providerName;
  final String model;

  /// Disabled when null.
  final VoidCallback? onPressed;

  /// The chip's text for [providerName] and [model].
  static String labelFor(String providerName, String model) =>
      '$providerName · $model';

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.auto_awesome),
      label: Text(
        labelFor(providerName, model),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: 'Change AI provider or model',
      onPressed: onPressed,
    );
  }
}
