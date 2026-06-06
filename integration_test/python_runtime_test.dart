// On-device verification of the embedded Python runtime.
//
// Unlike the headless `flutter test` suite, this exercises the REAL
// serious_python interpreter, so it must run on a device/simulator:
//
//     flutter test integration_test/python_runtime_test.dart -d <device-id>
//
// It proves the full native path works: serious_python starts the bundled
// worker, the Dart loopback client drives it, and the vendored piexif parses
// EXIF from a staged image — no LLM required.

import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/script_runtime/python_script_runtime.dart';
import 'package:caverno/core/services/script_runtime/script_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// A minimal valid 1x1 JPEG (no EXIF); the piexif test inserts EXIF into it.
const _tinyJpegBase64 =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
    'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
    'AAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q==';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final runtime = PythonScriptRuntime();
  tearDownAll(() => runtime.dispose());

  testWidgets(
    'embedded interpreter runs and captures stdout',
    (tester) async {
      final result = await runtime.run(
        const ScriptRunRequest(code: "print('hello-from-python')"),
      );
      expect(result.error, isNull);
      expect(result.timedOut, isFalse);
      expect(result.stdout.trim(), 'hello-from-python');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'structured set_output round-trips back to Dart',
    (tester) async {
      final result = await runtime.run(
        const ScriptRunRequest(code: "caverno.set_output({'ok': True, 'n': 7})"),
      );
      expect(result.error, isNull);
      expect(result.result, {'ok': true, 'n': 7});
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'vendored piexif reads EXIF from a staged image',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('caverno_it_');
      final image = File('${dir.path}/img.jpg');
      await image.writeAsBytes(base64Decode(_tinyJpegBase64));

      final result = await runtime.run(
        ScriptRunRequest(
          code: '''
import piexif, caverno
src = caverno.inputs[0].path
piexif.insert(piexif.dump({"0th": {piexif.ImageIFD.Make: b"TestCam"}}), src)
print(piexif.load(src)["0th"][piexif.ImageIFD.Make].decode())
''',
          inputs: [
            ScriptInput(name: 'img.jpg', path: image.path, mime: 'image/jpeg'),
          ],
          workingDirectory: dir.path,
        ),
      );

      expect(result.error, isNull, reason: result.traceback ?? '');
      expect(result.stdout.trim(), 'TestCam');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
