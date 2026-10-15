import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// The app's preferences keep the `flutter.` prefix in the platform store.
const _flutterPrefix = 'flutter.';

/// File name of the isolated preferences inside a `--data-dir`.
const cavernoCliPreferencesFileName = 'preferences.json';

/// Routes `SharedPreferences` to a file inside [dataDirectory].
///
/// `--data-dir` isolated Hive and the session logs but not preferences, so a
/// CLI run read the app's endpoints, MCP servers and roles, and wrote farm
/// roadmap snapshots back into the app's own preferences. The first run with
/// a fresh directory copies the app's current preferences, so an isolated run
/// keeps the user's connection and role routing; after that, nothing reads or
/// writes the app's store. The copy includes API keys, so the file is written
/// readable by its owner only.
///
/// Call before the first `SharedPreferences.getInstance()`.
Future<void> isolateCavernoCliPreferences(Directory dataDirectory) async {
  final current = SharedPreferencesStorePlatform.instance;
  if (current is CavernoCliFilePreferencesStore) return;
  final file = File(
    '${dataDirectory.path}${Platform.pathSeparator}'
    '$cavernoCliPreferencesFileName',
  );
  SharedPreferencesStorePlatform.instance =
      await CavernoCliFilePreferencesStore.open(
        file,
        seed: () => current.getAllWithParameters(
          GetAllParameters(filter: PreferencesFilter(prefix: _flutterPrefix)),
        ),
      );
}

/// An in-memory store that writes itself to [file] after every change.
final class CavernoCliFilePreferencesStore
    extends InMemorySharedPreferencesStore {
  CavernoCliFilePreferencesStore._(this.file, Map<String, Object> data)
    : super.withData(data);

  final File file;

  /// Loads [file], or creates it from [seed] when it does not exist yet.
  static Future<CavernoCliFilePreferencesStore> open(
    File file, {
    required Future<Map<String, Object>> Function() seed,
  }) async {
    if (await file.exists()) {
      return CavernoCliFilePreferencesStore._(file, _decode(file));
    }
    final store = CavernoCliFilePreferencesStore._(file, await seed());
    await store._persist();
    return store;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _after(super.setValue(valueType, key, value));

  @override
  Future<bool> remove(String key) => _after(super.remove(key));

  @override
  Future<bool> clear() => _after(super.clear());

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _after(super.clearWithParameters(parameters));

  Future<bool> _after(Future<bool> change) async {
    final changed = await change;
    await _persist();
    return changed;
  }

  Future<void> _persist() async {
    final values = await getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: '')),
    );
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.tmp');
    await staged.writeAsString(jsonEncode(values), flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', staged.path]);
    }
    await staged.rename(file.path);
  }

  static Map<String, Object> _decode(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Not a preferences object: ${file.path}');
    }
    return {
      for (final entry in decoded.entries)
        if (entry.value != null)
          entry.key: entry.value is List
              ? List<String>.from(entry.value as List)
              : entry.value as Object,
    };
  }
}
