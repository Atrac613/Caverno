import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

void main() {
  final commandOutput = List<String>.generate(
    800,
    (index) => 'verification output line ${index + 1}: synthetic detail',
  ).join('\n');
  final results = List<ToolResultInfo>.generate(
    6,
    (index) => ToolResultInfo(
      id: 'command-$index',
      name: index.isEven ? 'run_tests' : 'local_execute_command',
      arguments: {'command': 'verify fixture $index'},
      result: jsonEncode({
        'command': 'verify fixture $index',
        'exit_code': index == 5 ? 1 : 0,
        'stdout': commandOutput,
        'stderr': index == 5 ? 'one verification failed' : '',
      }),
      outcome: ToolOutcome(
        exitCode: index == 5 ? 1 : 0,
        testPassedCount: index.isEven ? 47 : null,
        testFailedCount: index.isEven ? 0 : null,
        testSkippedCount: index.isEven ? 2 : null,
      ),
    ),
  );

  final rawPrompt = ToolResultPromptBuilder.buildAnswerPrompt(
    ToolResultPromptBuilder.budgetToolResults(results),
  );
  final summaryPrompt = ToolResultPromptBuilder.buildAnswerPrompt(
    ToolResultPromptBuilder.budgetToolResults(results, summaryFirst: true),
  );
  final rawTokens = _estimateTokens(rawPrompt);
  final summaryTokens = _estimateTokens(summaryPrompt);
  final savedTokens = rawTokens - summaryTokens;
  final savedRatio = rawTokens == 0 ? 0.0 : savedTokens / rawTokens;

  stdout.writeln('== LL34 summary-first synthetic measurement ==');
  stdout.writeln('tool results: ${results.length}');
  stdout.writeln('estimated prompt tokens: $rawTokens -> $summaryTokens');
  stdout.writeln(
    'estimated token savings: $savedTokens '
    '(${(savedRatio * 100).toStringAsFixed(1)}%)',
  );
  if (savedTokens <= 0) {
    stderr.writeln('Summary-first rendering did not reduce prompt tokens.');
    exitCode = 1;
  }
}

int _estimateTokens(String text) => (text.length / 4).ceil();
