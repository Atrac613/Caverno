import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/terminal/presentation/caverno_cli_preferences_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  late Directory dataDirectory;
  late SharedPreferencesStorePlatform original;

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('caverno_cli_prefs');
    original = SharedPreferencesStorePlatform.instance;
  });

  tearDown(() {
    SharedPreferencesStorePlatform.instance = original;
    dataDirectory.deleteSync(recursive: true);
  });

  File preferencesFile() =>
      File('${dataDirectory.path}/$cavernoCliPreferencesFileName');

  test('copies the app preferences once, then never writes them', () async {
    // A farm run with --data-dir wrote roadmap snapshots into the app's own
    // preferences, and read its MCP servers and roles from them.
    final app = InMemorySharedPreferencesStore.withData({
      'flutter.app_settings': '{"model":"qwen"}',
      'flutter.window_width': 1200.0,
      'NSWindow Frame Main': 'not ours',
    });
    SharedPreferencesStorePlatform.instance = app;

    await isolateCavernoCliPreferences(dataDirectory);
    final store = SharedPreferencesStorePlatform.instance;
    expect(store, isA<CavernoCliFilePreferencesStore>());
    expect(await store.getAll(), {
      'flutter.app_settings': '{"model":"qwen"}',
      'flutter.window_width': 1200.0,
    });

    await store.setValue('String', 'flutter.project_farm', 'snapshot');
    expect(await app.getAll(), isNot(contains('flutter.project_farm')));
    expect(
      jsonDecode(preferencesFile().readAsStringSync()),
      containsPair('flutter.project_farm', 'snapshot'),
    );
  });

  test('reloads every value type from the file', () async {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
    await isolateCavernoCliPreferences(dataDirectory);
    final store = SharedPreferencesStorePlatform.instance;
    await store.setValue('Bool', 'flutter.b', true);
    await store.setValue('Int', 'flutter.i', 3);
    await store.setValue('Double', 'flutter.d', 0.5);
    await store.setValue('String', 'flutter.s', 'x');
    await store.setValue('StringList', 'flutter.l', ['a', 'b']);
    await store.remove('flutter.s');

    // A later run starts from the file, not from the app's store.
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData({'flutter.s': 'app'});
    await isolateCavernoCliPreferences(dataDirectory);
    expect(await SharedPreferencesStorePlatform.instance.getAll(), {
      'flutter.b': true,
      'flutter.i': 3,
      'flutter.d': 0.5,
      'flutter.l': ['a', 'b'],
    });
  });

  test('SharedPreferences reads the isolated copy', () async {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData({'flutter.k': 'v'});
    await isolateCavernoCliPreferences(dataDirectory);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('k'), 'v');
    if (!Platform.isWindows) {
      final mode = (await preferencesFile().stat()).modeString();
      expect(mode, 'rw-------', reason: 'the copy carries API keys');
    }
  });
}
