import 'dart:convert';
import 'dart:math' as math;

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../chat/data/datasources/chat_remote_datasource.dart';
import 'live_llm_chart_probe_image.dart';

/// Pure response scoring for the live LLM diagnostic probes.
///
/// Moved out of `LiveLlmDiagnosticService` unchanged (F5): these functions
/// read a model's reply and return a count, a match, or a first mismatch, and
/// none of them touches the endpoint, settings, or tools. Keeping them apart
/// lets each rule be tested directly instead of through a whole probe run.
abstract final class LiveLlmResponseScoring {
  /// How far a chart reading may miss and still count; see
  /// `LiveLlmDiagnosticService.chartValueTolerance`.
  static const int chartValueTolerance = 2;

  /// Compares only the keys the rung pins, so a model may add its own optional
  /// arguments; it may not get a pinned one wrong.
  static String? firstArgumentMismatch(
    Map<String, dynamic> actual,
    Map<String, Object?> expected,
  ) {
    for (final entry in expected.entries) {
      final value = actual[entry.key];
      if (value == entry.value) continue;
      if ('$value'.trim() == '${entry.value}'.trim()) continue;
      return '${entry.key}=${value ?? 'nothing'} where ${entry.value} was expected';
    }
    return null;
  }

  /// Counts how many of 1..N appear as their own line, in order. Line-scoped on
  /// purpose: a substring search would count the "1" inside "10".
  static int matchedIntegerSequence(String content, {required int length}) {
    var expected = 1;
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (int.tryParse(trimmed) != expected) {
        continue;
      }
      expected += 1;
      if (expected > length) {
        break;
      }
    }
    return expected - 1;
  }

  static String stripSingleCodeFence(String content) {
    final normalized = content.replaceAll('\r\n', '\n').trim();
    final match = RegExp(
      r'^```(?:dart|diff)?\s*\n([\s\S]*?)\n```$',
      caseSensitive: false,
    ).firstMatch(normalized);
    return (match?.group(1) ?? normalized).trim();
  }

  /// Drops the `a/` and `b/` prefixes from a unified diff's file headers.
  ///
  /// The prefixes are a git convention, not part of the format: `diff -u` and
  /// `patch -p0` write and expect the bare path, and Caverno never consumes the
  /// header at all -- the preference only picks a sentence for the system
  /// prompt. Comparing them verbatim scored a model that produced a perfectly
  /// applicable diff as an edit-format failure, and cost it 18 of 55 points on
  /// a spelling difference. Everything below the header is still compared
  /// exactly, including hunk headers and context lines.
  static String normalizeUnifiedDiffFileHeaders(String diff) {
    return diff
        .split('\n')
        .map((line) {
          for (final marker in const ['--- ', '+++ ']) {
            if (!line.startsWith(marker)) continue;
            final path = line.substring(marker.length);
            for (final prefix in const ['a/', 'b/']) {
              if (path.startsWith(prefix)) {
                return '$marker${path.substring(prefix.length)}';
              }
            }
            return line;
          }
          return line;
        })
        .join('\n');
  }

  static String? firstEditFormatMismatch({
    required String expected,
    required String actual,
  }) {
    if (expected == actual) return null;
    final expectedLines = const LineSplitter().convert(expected);
    final actualLines = const LineSplitter().convert(actual);
    final sharedLength = math.min(expectedLines.length, actualLines.length);
    for (var index = 0; index < sharedLength; index += 1) {
      if (expectedLines[index] != actualLines[index]) {
        return 'line ${index + 1}: expected `${expectedLines[index]}`, '
            'received `${actualLines[index]}`';
      }
    }
    if (expectedLines.length > actualLines.length) {
      return 'line ${actualLines.length + 1}: expected '
          '`${expectedLines[actualLines.length]}`, received end of output';
    }
    return 'line ${expectedLines.length + 1}: expected end of output, '
        'received `${actualLines[expectedLines.length]}`';
  }

  /// How many of the chart's readings the model got right, position by
  /// position, graded on the visible answer.
  static int matchedChartAnswers(String content) {
    final expected = LiveLlmChartProbeImage.expectedAnswers;
    final fields = _chartAnswerFields(ContentParser.parse(content).text.trim());
    var matched = 0;
    for (
      var index = 0;
      index < expected.length && index < fields.length;
      index++
    ) {
      if (_chartFieldMatches(fields[index], expected[index])) matched += 1;
    }
    return matched;
  }

  /// The four answers out of whatever the model wrapped them in.
  ///
  /// Read from the last line that carries enough commas, so a model that
  /// prefaces the list with a sentence is still graded on the list.
  static List<String> _chartAnswerFields(String answer) {
    final expectedCount = LiveLlmChartProbeImage.expectedAnswers.length;
    final lines = const LineSplitter()
        .convert(answer)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (final line in lines.reversed) {
      final fields = line.split(',');
      if (fields.length >= expectedCount) {
        return fields.map(_normalizeChartField).toList();
      }
    }
    return answer.split(',').map(_normalizeChartField).toList();
  }

  static String _normalizeChartField(String field) =>
      field.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');

  static bool _chartFieldMatches(String actual, String expected) {
    final expectedValue = num.tryParse(expected);
    if (expectedValue == null) return actual == expected;
    final actualValue = num.tryParse(actual);
    if (actualValue == null) return false;
    return (actualValue - expectedValue).abs() <= chartValueTolerance;
  }

  /// Counts leading quadrant colors named in the expected order. Order matters:
  /// naming the right four colors in the wrong arrangement means the layout was
  /// not actually read.
  ///
  /// Grades the visible answer rather than the raw response, for the reason the
  /// chart probe already does: a reasoning model enumerates candidate colors on
  /// its way to an answer, and scanning that text scores the thinking instead of
  /// the reading. Scoring the raw response made the no-image control arm match
  /// all four colors out of its own think block, which classified a
  /// demonstrably sighted model as `model_ignored_the_image`.
  static int matchedQuadrantColors(
    String content,
    List<String> expectedColors,
  ) {
    final normalized = visibleContent(content).toLowerCase();
    var cursor = 0;
    var matched = 0;
    for (final color in expectedColors) {
      final index = normalized.indexOf(color, cursor);
      if (index < 0) {
        break;
      }
      cursor = index + color.length;
      matched += 1;
    }
    return matched;
  }

  static Map<String, dynamic>? tryDecodeJsonObject(String value) {
    // Reasoning models hand back their chain of thought merged into the
    // content as a <think> block, and that prose routinely contains braces.
    // Slicing the raw text from its first brace would start inside the
    // thought and end at the answer's closing brace, so the decode fails and
    // a schema-perfect reply gets scored as a contract violation. Decode the
    // same visible text a production consumer would parse.
    final trimmed = visibleContent(value);
    final candidates = <String>[trimmed];
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      candidates.add(trimmed.substring(firstBrace, lastBrace + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Scores the same text that production consumers display or parse while
  /// retaining the raw response separately for evidence and physical metrics.
  static String visibleContent(String content) {
    return ContentParser.parse(content).text.trim();
  }

  static bool stringListEquals(Object? actual, List<String> expected) {
    if (actual is! List || actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  /// Tool calls the reply made, native or embedded in the text.
  static List<ToolCallInfo> toolCallsFrom(ChatCompletionResult result) {
    final nativeCalls = result.toolCalls;
    if (nativeCalls != null && nativeCalls.isNotEmpty) {
      return nativeCalls;
    }
    return ContentParser.extractCompletedToolCalls(result.content)
        .map(
          (toolCall) => ToolCallInfo(
            id: toolCall.occurrenceId ?? 'text-${toolCall.name}',
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
        )
        .toList(growable: false);
  }

  /// Whether a four-word window recurs three times: a sampler stuck in a
  /// loop rather than a model answering.
  static bool looksRepetitive(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length < 24) {
      return false;
    }
    final words = normalized
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length < 8) {
      return false;
    }
    final windowCounts = <String, int>{};
    for (var index = 0; index <= words.length - 4; index += 1) {
      final window = words.sublist(index, index + 4).join(' ');
      final count = (windowCounts[window] ?? 0) + 1;
      if (count >= 3) {
        return true;
      }
      windowCounts[window] = count;
    }
    return false;
  }
}
