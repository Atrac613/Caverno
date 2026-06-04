import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File(
    'tool/run_browser_save_live_canary.sh',
  ).readAsStringSync();
  final canary = File(
    'tool/canaries/browser_save_live_llm_canary_test.dart',
  ).readAsStringSync();
  final searchFixture = File(
    'tool/fixtures/browser_save_live_canary/search.html',
  ).readAsStringSync();
  final wikipediaFixture = File(
    'tool/fixtures/browser_save_live_canary/wikipedia.html',
  ).readAsStringSync();

  test('browser save live canary runner is optional and report-backed', () {
    expect(script, contains('CAVERNO_BROWSER_SAVE_LIVE_CANARY=1'));
    expect(script, contains('CAVERNO_LLM_BASE_URL'));
    expect(script, contains(r'browser_save_live_canary_$(date +%s)'));
    expect(
      script,
      contains('tool/canaries/browser_save_live_llm_canary_test.dart'),
    );
    expect(script, contains('--canary-name browser_save_live_canary'));
    expect(script, contains('--surface browser'));
  });

  test('browser save canary uses local fixture pages', () {
    expect(searchFixture, contains('Local Search Results'));
    expect(searchFixture, contains('アジサイ - Wikipedia'));
    expect(searchFixture, contains('wikipedia.html'));
    expect(wikipediaFixture, contains('<h1>アジサイ</h1>'));
    expect(wikipediaFixture, contains('Hydrangea macrophylla'));
    expect(canary, contains('tool/fixtures/browser_save_live_canary'));
    expect(canary, contains('fixture.searchUrl'));
  });

  test('browser save canary guards app-storage destination policy', () {
    expect(canary, contains('browser_save_data'));
    expect(canary, contains('Destination: Caverno application storage'));
    expect(canary, contains('unsafeSaveDestinationAttempts'));
    expect(canary, contains('downloads'));
    expect(canary, contains('documents'));
    expect(canary, contains('BROWSER_SAVE_LIVE_OK'));
  });
}
