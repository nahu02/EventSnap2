import 'package:material_ui/material_ui.dart';

/// Spacing scale and layout constants shared by all screens
/// (docs/v3_plan.md §6.0).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page padding.
  static const double page = 16;

  /// Maximum width of a screen's content column (centred on tablets).
  static const double maxContentWidth = 640;
}

/// Centres [child] horizontally and limits it to [maxWidth].
///
/// Works inside scroll views (it sizes to its child's height).
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = AppSpacing.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
