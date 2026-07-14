import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/structured_coding_execution_deferral_detector.dart';

void main() {
  const detector = StructuredCodingExecutionDeferralDetector();

  test('matches the structured execution deferral from the incident', () {
    const response = '''
## 1. Understanding & Planning

**What I need to verify:**
- The exact content of todo_app.md.
- Whether any Dart files already exist in the project.

## 3. Next Chunk

Read todo_app.md, check the project structure, and verify existing Dart files.
''';

    expect(detector.matches(response), isTrue);
  });

  test('matches a bulleted next implementation step', () {
    const response = '''
## Next Implementation Step

- Inspect lib/main.dart before editing the implementation.
''';

    expect(detector.matches(response), isTrue);
  });

  test('matches the Japanese structured execution plan from the incident', () {
    const response = '''
## \u5b9f\u884c\u8a08\u753b

### 1. todo_app.md \u3092\u8aad\u3080

### 2. Dart\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u3092\u521d\u671f\u5316

### 3. main.dart \u3092\u5b9f\u88c5

\u307e\u305a\u3001todo_app.md\u306e\u5185\u5bb9\u3092\u78ba\u8a8d\u3057\u307e\u3059\u3002
''';

    expect(detector.matches(response), isTrue);
  });

  test('ignores an action without a structured planning marker', () {
    expect(
      detector.matches('Read todo_app.md and inspect the Dart project.'),
      isFalse,
    );
    expect(
      detector.matches(
        'todo_app.md \u3092\u8aad\u3093\u3067Dart\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u3092\u5b9f\u88c5\u3057\u307e\u3059\u3002',
      ),
      isFalse,
    );
  });

  test('ignores non-coding uses of next chunk', () {
    expect(
      detector.matches('The next chunk size is 64 KB for this upload.'),
      isFalse,
    );
  });

  test('ignores questions and blockers', () {
    expect(
      detector.matches('''
## Next Chunk

Should I read todo_app.md before editing the Dart project?
'''),
      isFalse,
    );
    expect(
      detector.matches('''
## Next Chunk

Blocked because I need your project access before reading todo_app.md.
'''),
      isFalse,
    );
    expect(
      detector.matches('''
## \u5b9f\u884c\u8a08\u753b

todo_app.md \u3092\u8aad\u307f\u307e\u3059\u304b\u{ff1f}
'''),
      isFalse,
    );
    expect(
      detector.matches('''
## \u5b9f\u884c\u8a08\u753b

\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u60c5\u5831\u304c\u4e0d\u8db3\u3057\u3066\u3044\u308b\u305f\u3081\u5b9f\u88c5\u3067\u304d\u307e\u305b\u3093\u3002
'''),
      isFalse,
    );
  });
}
