import '../../../settings/domain/entities/app_settings.dart';

/// What one `AppSettings` change means for the model route and the data source.
///
/// Split from the policy that computes it because the two grow for different
/// reasons: the policy gains a line per setting that can invalidate a route,
/// while this stays the shape of an answer.
final class ModelSwitchSettingsComparison {
  const ModelSwitchSettingsComparison({
    required this.previousRouteId,
    required this.nextRouteId,
    required this.routeChanged,
    required this.previousPrimaryModelForPreparation,
    required this.shouldRebuildDataSource,
  });

  /// Route identity before and after the change, as
  /// [ModelCapabilityProfile.buildId] derives it.
  final String previousRouteId;
  final String nextRouteId;
  final bool routeChanged;

  /// The model to prepare in the background, or `null` when the change is not
  /// a same-endpoint model switch.
  final String? previousPrimaryModelForPreparation;

  final bool shouldRebuildDataSource;
}
