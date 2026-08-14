import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_environment.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_report_service.dart';
import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_config_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/idle_maintenance_environment_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_report_service_provider.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
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
  _RecordingStage({this.stageName = 'probe'});

  final String stageName;
  bool ran = false;
  int runCount = 0;
  @override
  String get name => stageName;
  @override
  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context) async {
    ran = true;
    runCount += 1;
    return const MaintenanceStageOutcome.completed('profiled');
  }
}

class _MutableSettingsNotifier extends SettingsNotifier {
  _MutableSettingsNotifier(this.initialSettings);

  final AppSettings initialSettings;

  @override
  AppSettings build() => initialSettings;

  void replace(AppSettings settings) => state = settings;
}

class _EmptyCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _MutableMcpToolService extends McpToolService {
  List<Map<String, dynamic>> definitions = const [];

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => definitions;
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
        maintenanceWarmupRefreshKeyProvider.overrideWithValue(() => 'stable'),
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
        maintenanceWarmupRefreshKeyProvider.overrideWithValue(() => 'stable'),
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

  test('refreshes only LL22 stages when the warm-up key changes', () async {
    final probe = _RecordingStage();
    final precompute = _RecordingStage(stageName: 'precompute');
    final warm = _RecordingStage(stageName: 'warm_cache');
    var refreshKey = 'model-a:catalog-a';
    final container = ProviderContainer(
      overrides: [
        idleMaintenanceConfigProvider.overrideWithValue(enabledConfig),
        idleMaintenanceEnvironmentProvider.overrideWithValue(
          _AllowEnvironment(),
        ),
        maintenanceStagesProvider.overrideWithValue([probe, precompute, warm]),
        maintenanceWarmupRefreshKeyProvider.overrideWithValue(() => refreshKey),
        maintenanceReportServiceProvider.overrideWithValue(
          MaintenanceReportService(sink: (title, body) async {}),
        ),
      ],
    );
    addTearDown(container.dispose);

    final scheduler = container.read(idleMaintenanceSchedulerProvider);
    await scheduler.tick();
    await scheduler.drain();
    expect((probe.runCount, precompute.runCount, warm.runCount), (1, 1, 1));

    refreshKey = 'model-b:catalog-b';
    await scheduler.tick();
    await scheduler.drain();

    expect(probe.runCount, 1);
    expect(precompute.runCount, 2);
    expect(warm.runCount, 2);
  });

  test('refresh key changes with model and mutable tool catalog inputs', () {
    final initialSettings = AppSettings.defaults().copyWith(model: 'model-a');
    late _MutableSettingsNotifier settingsNotifier;
    final toolService = _MutableMcpToolService();
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(() {
          settingsNotifier = _MutableSettingsNotifier(initialSettings);
          return settingsNotifier;
        }),
        codingProjectsNotifierProvider.overrideWith(
          _EmptyCodingProjectsNotifier.new,
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
      ],
    );
    addTearDown(container.dispose);
    final key = container.read(maintenanceWarmupRefreshKeyProvider);

    final initialKey = key();
    settingsNotifier.replace(initialSettings.copyWith(model: 'model-b'));
    final modelKey = key();
    toolService.definitions = const [
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'parameters': {'type': 'object'},
        },
      },
    ];
    final catalogKey = key();

    expect(modelKey, isNot(initialKey));
    expect(catalogKey, isNot(modelKey));
  });
}
