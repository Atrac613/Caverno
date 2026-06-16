import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_environment.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_report_service.dart';
import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_config_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_environment_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_report_service_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _AllowEnvironment implements IdleMaintenanceEnvironment {
  @override
  DateTime now() => DateTime(2026, 6, 16, 3);
  @override
  Duration idleFor() => const Duration(hours: 1);
  @override
  bool? onAcPower() => true;
}

class _RecordingStage implements MaintenanceStage {
  bool ran = false;
  @override
  String get name => 'probe';
  @override
  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context) async {
    ran = true;
    return const MaintenanceStageOutcome.completed('profiled');
  }
}

void main() {
  // All-day window so the gate allows regardless of wall-clock time.
  const enabledConfig = IdleMaintenanceConfig(
    enabled: true,
    windowStartMinutes: 0,
    windowEndMinutes: 0,
    minIdle: Duration(minutes: 1),
    requireAcPower: false,
  );

  test('wires gate -> pipeline -> report on an open gate', () async {
    final stage = _RecordingStage();
    final delivered = <String>[];

    final container = ProviderContainer(
      overrides: [
        idleMaintenanceConfigProvider.overrideWithValue(enabledConfig),
        idleMaintenanceEnvironmentProvider.overrideWithValue(
          _AllowEnvironment(),
        ),
        maintenanceStagesProvider.overrideWithValue([stage]),
        maintenanceReportServiceProvider.overrideWithValue(
          MaintenanceReportService(
            sink: (title, body) async => delivered.add(title),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final scheduler = container.read(idleMaintenanceSchedulerProvider);
    await scheduler.tick(); // rising edge -> run
    await scheduler.drain();

    expect(stage.ran, isTrue);
    expect(delivered, ['Idle maintenance: 1 done']);
  });

  test('does not deliver a report when nothing executed', () async {
    final delivered = <String>[];
    final container = ProviderContainer(
      overrides: [
        idleMaintenanceConfigProvider.overrideWithValue(enabledConfig),
        idleMaintenanceEnvironmentProvider.overrideWithValue(
          _AllowEnvironment(),
        ),
        // No stages configured -> empty report -> no notification.
        maintenanceStagesProvider.overrideWithValue(const []),
        maintenanceReportServiceProvider.overrideWithValue(
          MaintenanceReportService(
            sink: (title, body) async => delivered.add(title),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final scheduler = container.read(idleMaintenanceSchedulerProvider);
    await scheduler.tick();
    await scheduler.drain();

    expect(delivered, isEmpty);
  });

  test('a closed gate never runs the pipeline', () async {
    final stage = _RecordingStage();
    final container = ProviderContainer(
      overrides: [
        idleMaintenanceConfigProvider.overrideWithValue(
          enabledConfig.copyWith(enabled: false),
        ),
        idleMaintenanceEnvironmentProvider.overrideWithValue(
          _AllowEnvironment(),
        ),
        maintenanceStagesProvider.overrideWithValue([stage]),
        maintenanceReportServiceProvider.overrideWithValue(
          MaintenanceReportService(sink: (title, body) async {}),
        ),
      ],
    );
    addTearDown(container.dispose);

    final scheduler = container.read(idleMaintenanceSchedulerProvider);
    await scheduler.tick();
    await scheduler.drain();

    expect(stage.ran, isFalse);
  });
}
