import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Guards against regressing to App Store Connect "Missing Compliance" on
  // every iOS upload. The app uses only exempt, standard encryption, so the
  // Info.plist must pre-declare the encryption exemption with
  // ITSAppUsesNonExemptEncryption = false. If the app ever adopts non-exempt
  // (proprietary/non-standard) encryption, update this declaration deliberately.
  test('iOS Info.plist declares the export compliance encryption exemption', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      infoPlist,
      contains('ITSAppUsesNonExemptEncryption'),
      reason: 'Missing the export compliance key; uploads will report '
          '"Missing Compliance" and need a manual answer per build.',
    );
    expect(
      infoPlist,
      matches(
        RegExp(
          r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false\s*/>',
        ),
      ),
      reason: 'Export compliance must declare the exemption (<false/>).',
    );
  });
}
