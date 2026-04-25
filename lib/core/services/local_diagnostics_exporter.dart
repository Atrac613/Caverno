import 'local_diagnostics_exporter_stub.dart'
    if (dart.library.io) 'local_diagnostics_exporter_io.dart';

Future<String> exportLocalDiagnostics({
  required String filePrefix,
  required String contents,
  DateTime? generatedAt,
}) {
  final timestamp = (generatedAt ?? DateTime.now())
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  return writeLocalDiagnosticsFile('$filePrefix-$timestamp.json', contents);
}
