import 'maintenance_pipeline.dart';

/// A [MaintenanceStage] defined inline by a name and an async body, so a stage
/// can wrap an existing service call (probe, eval, ...) without a dedicated
/// class. The body returns an outcome or throws to fail.
class CallbackMaintenanceStage implements MaintenanceStage {
  const CallbackMaintenanceStage({
    required this.name,
    required Future<MaintenanceStageOutcome> Function(MaintenanceStageContext)
    body,
  }) : _body = body;

  @override
  final String name;

  final Future<MaintenanceStageOutcome> Function(MaintenanceStageContext) _body;

  @override
  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context) =>
      _body(context);
}
