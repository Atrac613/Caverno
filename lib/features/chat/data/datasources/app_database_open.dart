import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// Opens the production drift database backed by a SQLite file in the app
/// support directory. F4 bootstrap calls this once; failures fall back to Hive.
Future<AppDatabase> openAppDatabase({File? databaseFile}) async {
  final file =
      databaseFile ??
      File('${(await resolveCavernoDataRoot()).path}/caverno.sqlite');
  await file.parent.create(recursive: true);
  return AppDatabase(NativeDatabase.createInBackground(file));
}

/// Resolves the shared persistence and execution-lease root for a frontend.
Future<Directory> resolveCavernoDataRoot({
  Directory? explicitDataDirectory,
}) async {
  final directory =
      explicitDataDirectory ?? await getApplicationSupportDirectory();
  return Directory.fromUri(directory.absolute.uri.normalizePath());
}
