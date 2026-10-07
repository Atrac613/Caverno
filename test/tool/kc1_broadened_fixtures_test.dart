import 'package:flutter_test/flutter_test.dart';

import '../../tool/kc1_cutoff_exposure_census.dart';
import '../../tool/kc1_cutoff_oracle.dart';

/// The fixtures added 2026-09-24 so an arm's effect is a rate over many
/// prompts rather than one prompt's flip. Each pattern pair is checked against
/// the answer shapes it must separate, and no task may hand the model the
/// idiom it is scored on.
void main() {
  const samples = <String, (String stale, String current)>{
    'flutter-dialog-background': (
      'ThemeData(dialogBackgroundColor: Colors.grey.shade100)',
      'ThemeData(dialogTheme: DialogThemeData(backgroundColor: c))',
    ),
    'flutter-raw-keyboard': (
      'RawKeyboardListener(onKey: (RawKeyEvent e) {})',
      'HardwareKeyboard.instance.addHandler((KeyEvent e) => false)',
    ),
    'flutter-material-state': (
      'MaterialStateProperty.resolveWith((s) => s.contains(MaterialState.pressed) ? r : b)',
      'WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.pressed) ? r : b)',
    ),
    'flutter-text-scale': (
      'MediaQuery.of(context).textScaleFactor * 14',
      'MediaQuery.textScalerOf(context).scale(14)',
    ),
    'file-picker-static': (
      'await FilePicker.platform.pickFiles(type: FileType.custom)',
      'await FilePicker.pickFiles(type: FileType.custom)',
    ),
    'share-plus-instance': (
      "Share.share('Hello')",
      "SharePlus.instance.share(ShareParams(text: 'Hello'))",
    ),
    'qr-image-view': (
      "QrImage(data: 'https://example.com', size: 200)",
      "QrImageView(data: 'https://example.com', size: 200)",
    ),
    'freezed-pattern-matching': (
      "result.when(ok: (v) => '\$v', error: (m) => m)",
      "switch (result) { Ok(:final value) => '\$value', Err(:final message) => message }",
    ),
    'repo-localization': ("Text('save'.intl(context))", "Text('save'.tr())"),
    'repo-unique-id': (
      'final ts = DateTime.now().millisecondsSinceEpoch;',
      'final id = const Uuid().v4();',
    ),
    'repo-data-class': (
      'bool operator ==(Object other) => other is Bookmark;',
      '@freezed\nabstract class Bookmark with _\$Bookmark {}',
    ),
  };

  CutoffCase caseNamed(String id) =>
      cutoffCases.firstWhere((testCase) => testCase.id == id);

  ClaimRecord score(String id, String response) => scoreCutoffResponse(
    testCase: caseNamed(id),
    arm: CensusArm.bare,
    repeat: 1,
    response: response,
    truthSource: 'test',
    promptSupportsClaim: false,
  );

  test('classes 2 and 4 have enough fixtures to read a rate', () {
    int count(CutoffClass cutoffClass) =>
        cutoffCases.where((c) => c.cutoffClass == cutoffClass).length;
    expect(count(CutoffClass.apiDrift), greaterThanOrEqualTo(10));
    expect(count(CutoffClass.thisRepository), greaterThanOrEqualTo(4));
  });

  for (final entry in samples.entries) {
    test('${entry.key}: the patterns separate the two idioms', () {
      expect(score(entry.key, entry.value.$1).truth, TruthVerdict.stale);
      expect(score(entry.key, entry.value.$2).truth, TruthVerdict.correct);
      expect(score(entry.key, 'Text("x")').truth, TruthVerdict.unscorable);
    });

    test('${entry.key}: the task does not name the idiom it scores', () {
      final testCase = caseNamed(entry.key);
      expect(testCase.stale.hasMatch(testCase.task), isFalse);
      expect(testCase.current.hasMatch(testCase.task), isFalse);
    });
  }

  test('a convention the repository does not hold fails confirmation', () {
    final oracle = CutoffOracle.resolve();
    expect(
      oracle.repoFilesMatching(RegExp(r'\bAppLocalizations\.of\b')),
      0,
      reason: 'the localization fixture depends on this staying true',
    );
    expect(oracle.flutterDeprecatedDeclaration('WidgetStateProperty'), isNull);
    expect(
      oracle.flutterDeprecatedDeclaration('MaterialStateProperty'),
      isNotNull,
    );
  });
}
