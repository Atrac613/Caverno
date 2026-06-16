import 'package:caverno/features/maintenance/domain/services/callback_maintenance_stage.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MaintenanceStageContext context() => MaintenanceStageContext(
    handle: IdleMaintenanceRunHandle(),
    shared: <String, Object?>{},
  );

  test('delegates to the body and returns its outcome', () async {
    var called = false;
    final stage = CallbackMaintenanceStage(
      name: 'probe',
      body: (_) async {
        called = true;
        return const MaintenanceStageOutcome.completed('done');
      },
    );

    expect(stage.name, 'probe');
    final outcome = await stage.run(context());
    expect(called, isTrue);
    expect(outcome.status, MaintenanceStageStatus.completed);
    expect(outcome.detail, 'done');
  });

  test('propagates a thrown error to the pipeline', () async {
    final stage = CallbackMaintenanceStage(
      name: 'eval',
      body: (_) async => throw StateError('boom'),
    );
    await expectLater(stage.run(context()), throwsStateError);
  });
}
