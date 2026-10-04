import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_report_service.dart';
import 'package:caverno/features/maintenance/domain/services/power_state_probe.dart';
import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_config_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_environment_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_report_service_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/presentation/providers/roadmap_snapshot_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixturePower implements PowerStateProbe {
  @override
  bool get onAcPower => true;
}

/// Keeps the production provider, lifecycle proxy, Farm stage and report path.
/// Other maintenance stages and the platform notification sink are excluded.
class FarmUnattendedMaintenanceProbe {
  FarmUnattendedMaintenanceProbe(FarmUnattendedRunner farm) {
    lifecycle = AppLifecycleService(
      clock: () => DateTime.now().subtract(const Duration(minutes: 11)),
    );
    stages = ProviderContainer(
      overrides: [farmUnattendedRunnerProvider.overrideWithValue(farm)],
    );
    final farmStage = stages
        .read(maintenanceStagesProvider)
        .singleWhere((stage) => stage.name == 'farm_advance');
    container = ProviderContainer(
      overrides: [
        appLifecycleServiceProvider.overrideWithValue(lifecycle),
        powerStateProbeProvider.overrideWithValue(_FixturePower()),
        idleMaintenanceConfigProvider.overrideWithValue(
          const IdleMaintenanceConfig(
            enabled: true,
            windowStartMinutes: 0,
            windowEndMinutes: 0,
            minIdle: Duration(minutes: 10),
            requireAcPower: true,
          ),
        ),
        maintenanceStagesProvider.overrideWithValue([farmStage]),
        maintenanceWarmupRefreshKeyProvider.overrideWithValue(() => 'fixture'),
        maintenanceReportServiceProvider.overrideWithValue(
          MaintenanceReportService(
            sink: (title, body) async {
              reports.add({'title': title, 'body': body});
              evidence['reports'] = reports;
            },
          ),
        ),
      ],
    );
    scheduler = container.read(idleMaintenanceSchedulerProvider);
  }

  late final AppLifecycleService lifecycle;
  late final ProviderContainer stages;
  late final ProviderContainer container;
  late final IdleMaintenanceScheduler scheduler;
  final reports = <Map<String, String>>[];
  final evidence = <String, Object?>{};

  Future<void> openAfterForegroundCheck() async {
    final environment = container.read(idleMaintenanceEnvironmentProvider);
    expect(environment.idleFor(), Duration.zero);
    await scheduler.tick();
    await scheduler.drain();
    expect(reports, isEmpty);
    evidence['foregroundReportCount'] = reports.length;
    // Synthetic lifecycle callback, not proof of OS event delivery.
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(
      environment.idleFor(),
      greaterThanOrEqualTo(const Duration(minutes: 10)),
    );
    evidence['backgroundIdleSeconds'] = environment.idleFor().inSeconds;
    await scheduler.tick();
    await scheduler.drain();
    expect(reports, hasLength(1));
    expect(reports.single['title'], 'Idle maintenance: 1 done');
    expect(reports.single['body'], contains('| farm_advance | completed |'));
  }

  Future<void> checkNoRepeatAndResume() async {
    await scheduler.tick();
    await scheduler.drain();
    expect(reports, hasLength(1));
    evidence['sameWindowReportCount'] = reports.length;
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final environment = container.read(idleMaintenanceEnvironmentProvider);
    expect(environment.idleFor(), Duration.zero);
    await scheduler.tick();
    await scheduler.drain();
    expect(reports, hasLength(1));
    evidence.addAll({
      'resumedIdleSeconds': environment.idleFor().inSeconds,
      'resumedReportCount': reports.length,
      'reports': reports,
      'stageNames': container
          .read(maintenancePipelineProvider)
          .stages
          .map((s) => s.name)
          .toList(),
    });
  }

  void dispose() {
    scheduler.stop();
    container.dispose();
    stages.dispose();
    lifecycle.dispose();
  }
}
