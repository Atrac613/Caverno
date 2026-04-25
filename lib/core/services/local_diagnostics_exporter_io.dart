import 'dart:io';

Future<String> writeLocalDiagnosticsFile(
  String fileName,
  String contents,
) async {
  final file = File('${Directory.systemTemp.path}/$fileName');
  await file.writeAsString(contents);
  return file.path;
}
