import 'package:caverno/features/settings/presentation/pages/qr_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Both strings are supplied so the page never reaches `.tr()`, which would
/// pull EasyLocalization and SharedPreferences into a test about one icon.
Future<void> _pumpScanner(WidgetTester tester, {required bool allow}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: QrScannerPage(
        title: 'Scan Pairing Code',
        hint: 'Point your camera at the desktop pairing QR',
        allowManualEntry: allow,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('offers no typed alternative when unasked', (tester) async {
    // Constructed the way settings import constructs it — without the
    // parameter at all — because the default is what protects that call site.
    // Passing `false` explicitly would pass just as well against a default of
    // true, which is the mutation this exists to catch. SA-02 is about what an
    // imported configuration can do, and a scanner that always accepted typed
    // input would be a second way to hand it one.
    await tester.pumpWidget(
      const MaterialApp(
        home: QrScannerPage(title: 'Import Settings', hint: 'Scan the QR'),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.content_paste), findsNothing);
  });

  testWidgets('offers none when a call site opts out', (tester) async {
    await _pumpScanner(tester, allow: false);

    expect(find.byIcon(Icons.content_paste), findsNothing);
  });

  testWidgets('offers one when the call site opts in', (tester) async {
    await _pumpScanner(tester, allow: true);

    expect(find.byIcon(Icons.content_paste), findsOneWidget);
  });
}
