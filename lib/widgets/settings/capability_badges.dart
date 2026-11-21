import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/ai_model_info.dart';

/// Model capabilities EventSnap cares about.
enum ModelCapability { structuredOutput, vision }

/// Small pills telling whether a model supports structured output and vision.
///
/// Each capability is tri-state: supported, unsupported or unknown (`null`).
/// In [compact] mode (dense lists such as the model picker) only supported
/// capabilities are shown; unsupported and unknown ones are left out to
/// reduce noise.
class CapabilityBadges extends StatelessWidget {
  const CapabilityBadges({
    super.key,
    required this.structuredOutput,
    required this.vision,
    this.compact = false,
  });

  /// Badges for [model]; a `null` model shows both capabilities as unknown.
  CapabilityBadges.forModel(
    AiModelInfo? model, {
    super.key,
    this.compact = false,
  }) : structuredOutput = model?.supportsStructuredOutput,
       vision = model?.supportsVision;

  final bool? structuredOutput;
  final bool? vision;
  final bool compact;

  /// Whether [build] renders at least one badge.
  bool get hasBadges => !compact || structuredOutput == true || vision == true;

  @override
  Widget build(BuildContext context) {
    final badges = [
      for (final (capability, supported) in [
        (ModelCapability.structuredOutput, structuredOutput),
        (ModelCapability.vision, vision),
      ])
        if (!compact || supported == true)
          CapabilityBadge(capability: capability, supported: supported),
    ];
    if (badges.isEmpty) return const SizedBox.shrink();
    return _NoBaseline(
      child: Wrap(spacing: 6, runSpacing: 6, children: badges),
    );
  }
}

/// Reports no baseline, so ancestors that align on baselines (`ListTile`
/// subtitles) never query into the badges. Querying a baseline through a
/// descendant relayout boundary that is still dirty (e.g. an `Icon` whose
/// glyph just changed) trips a framework assertion.
class _NoBaseline extends SingleChildRenderObjectWidget {
  const _NoBaseline({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNoBaseline();
}

class _RenderNoBaseline extends RenderProxyBox {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => null;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => null;
}

/// A single capability pill.
class CapabilityBadge extends StatelessWidget {
  const CapabilityBadge({
    super.key,
    required this.capability,
    required this.supported,
  });

  final ModelCapability capability;

  /// `true` supported, `false` unsupported, `null` unknown.
  final bool? supported;

  /// Visible text.
  String get label => switch ((capability, supported)) {
    (ModelCapability.structuredOutput, true) => 'Structured output',
    (ModelCapability.structuredOutput, false) => 'No structured output',
    (ModelCapability.structuredOutput, null) => 'Structured output unknown',
    (ModelCapability.vision, true) => 'Vision',
    (ModelCapability.vision, false) => 'No vision',
    (ModelCapability.vision, null) => 'Vision unknown',
  };

  /// Text read by screen readers.
  String get semanticLabel => switch ((capability, supported)) {
    (ModelCapability.structuredOutput, true) => 'Supports structured output',
    (ModelCapability.structuredOutput, false) =>
      'Does not support structured output',
    (ModelCapability.structuredOutput, null) =>
      'Structured output support unknown',
    (ModelCapability.vision, true) => 'Supports images',
    (ModelCapability.vision, false) => 'Does not support images',
    (ModelCapability.vision, null) => 'Image support unknown',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color? background, foreground, border, icon) = switch (supported) {
      true => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        BorderSide.none,
        Icons.check,
      ),
      false => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        BorderSide.none,
        Icons.close,
      ),
      null => (
        null,
        scheme.onSurfaceVariant,
        BorderSide(color: scheme.outlineVariant),
        Icons.question_mark,
      ),
    };
    final textStyle = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: foreground);

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: textStyle)),
            ],
          ),
        ),
      ),
    );
  }
}
