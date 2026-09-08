import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/kc1_cutoff_oracle.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('caverno_kc1_oracle_');
  });

  tearDown(() {
    if (scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });

  test('resolve prefers an existing FVM pin over FLUTTER_ROOT', () {
    final project = Directory('${scratch.path}/project')..createSync();
    File('${project.path}/.fvmrc').writeAsStringSync('{"flutter":"3.44.8"}');
    final fvmSdk = _writeMiniSdk(
      Directory('${scratch.path}/home/fvm/versions/3.44.8'),
    );
    final ciSdk = _writeMiniSdk(Directory('${scratch.path}/hosted-flutter'));

    final oracle = CutoffOracle.resolve(
      projectRoot: project.path,
      environment: {'HOME': '${scratch.path}/home', 'FLUTTER_ROOT': ciSdk.path},
    );

    expect(oracle.flutterSdkRoot, fvmSdk.path);
  });

  test('resolve falls back to FLUTTER_ROOT when the FVM pin is absent', () {
    final project = Directory('${scratch.path}/project')..createSync();
    File('${project.path}/.fvmrc').writeAsStringSync('{"flutter":"3.44.8"}');
    final ciSdk = _writeMiniSdk(Directory('${scratch.path}/hosted-flutter'));

    final oracle = CutoffOracle.resolve(
      projectRoot: project.path,
      environment: {
        'HOME': '${scratch.path}/empty-home',
        'FLUTTER_ROOT': ciSdk.path,
      },
    );

    expect(oracle.flutterSdkRoot, ciSdk.path);
    expect(oracle.flutterDeprecation('WillPopScope'), contains('PopScope'));
    expect(oracle.flutterDeprecation('PopScope'), isNull);
  });

  test('resolve uses the project .fvm/flutter_sdk symlink when present', () {
    final project = Directory('${scratch.path}/project')..createSync();
    File('${project.path}/.fvmrc').writeAsStringSync('{"flutter":"3.44.8"}');
    final linkedSdk = _writeMiniSdk(Directory('${scratch.path}/linked-sdk'));
    Link(
      '${project.path}/.fvm/flutter_sdk',
    ).createSync(linkedSdk.path, recursive: true);
    final ciSdk = _writeMiniSdk(Directory('${scratch.path}/hosted-flutter'));

    final oracle = CutoffOracle.resolve(
      projectRoot: project.path,
      environment: {
        'HOME': '${scratch.path}/empty-home',
        'FLUTTER_ROOT': ciSdk.path,
      },
    );

    expect(oracle.flutterSdkRoot, '${project.path}/.fvm/flutter_sdk');
  });
}

Directory _writeMiniSdk(Directory root) {
  final src = Directory('${root.path}/packages/flutter/lib/src/widgets')
    ..createSync(recursive: true);
  File('${src.path}/will_pop_scope.dart').writeAsStringSync('''
@Deprecated('Use PopScope instead. This feature was deprecated after v3.12.0-1.0.pre.')
class WillPopScope {}
''');
  File('${src.path}/pop_scope.dart').writeAsStringSync('''
class PopScope {}
''');
  return root;
}
