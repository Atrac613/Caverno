# Caverno Content Protocol

`caverno_content_protocol` is Caverno's pure-Dart parser contract for LLM
response content and model-emitted tool-call markup. Chat, routines, settings
diagnostics, and presentation code use the same parser so streaming and
non-streaming responses receive consistent treatment.

This is an internal workspace package. It is not published independently and
does not define a third-party plugin protocol.

## Responsibilities

- Split response content into text, thinking, tool-call, and tool-result
  segments.
- Parse the supported JSON, XML-like, function-style, control-token, and legacy
  tool-call formats produced by compatible models.
- Recover complete calls from partially streamed content when safe.
- Remove model-only thinking and tool artifacts from visible or historical
  content.
- Sanitize tool arguments without executing a tool or applying policy.

The package does not own tool dispatch, approval, persistence, UI rendering, or
network transport.

## Public API

Import only the public library:

```dart
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
```

The supported API includes:

- `ContentParser`
- `ContentType`
- `ContentSegment`
- `ParseResult`
- `ToolCallData`

Do not import files below `lib/src`.

## Example

```dart
import 'package:caverno_content_protocol/caverno_content_protocol.dart';

final result = ContentParser.parse(
  'Checking the workspace. '
  '<tool_call>{"name":"read_file","arguments":{"path":"README.md"}}'
  '</tool_call>',
);

for (final segment in result.segments) {
  switch (segment.type) {
    case ContentType.text:
      print(segment.content);
    case ContentType.toolCall:
      print(segment.toolCall?.name);
    case ContentType.thinking:
    case ContentType.toolResult:
      break;
  }
}
```

Use `extractCompletedToolCalls` when only executable calls are needed. Use
`stripModelHistoryArtifacts` before retaining model content that must not carry
thinking or tool markup into later requests.

## Compatibility

Parser behavior is a compatibility surface for local and remote
OpenAI-compatible models. Preserve existing handling of malformed, incomplete,
legacy, and control-token inputs unless a separately reviewed behavior change
updates the package tests.

## Development

Resolve the shared workspace from the repository root:

```bash
fvm flutter pub get
fvm dart pub workspace list
```

Run this package's checks:

```bash
cd packages/caverno_content_protocol
fvm dart analyze
fvm dart test
```

Run the repository boundary gate after changing dependencies or public API:

```bash
cd ../..
tool/codex_verify.sh --test test/quality/package_boundary_test.dart
```
