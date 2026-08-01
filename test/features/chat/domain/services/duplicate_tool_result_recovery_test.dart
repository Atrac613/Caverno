import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/duplicate_tool_result_recovery.dart';
import 'package:test/test.dart';

const _recovery = DuplicateToolResultRecovery();

ToolCallInfo _call({
  required String id,
  String name = 'read_file',
  required String path,
  String? reason,
}) {
  return ToolCallInfo(
    id: id,
    name: name,
    arguments: {'path': path, 'reason': ?reason},
  );
}

ToolResultInfo _result({
  required String id,
  String name = 'read_file',
  required String path,
  required String result,
  String? reason,
}) {
  return ToolResultInfo(
    id: id,
    name: name,
    arguments: {'path': path, 'reason': ?reason},
    result: result,
  );
}

DuplicateToolResultRecoveryInput _input({
  List<ToolCallInfo> currentToolCalls = const <ToolCallInfo>[],
  List<ToolResultInfo> executedToolResults = const <ToolResultInfo>[],
  List<ToolResultInfo> fallbackToolResults = const <ToolResultInfo>[],
  String? projectRoot,
}) {
  return DuplicateToolResultRecoveryInput(
    currentToolCalls: currentToolCalls,
    executedToolResults: executedToolResults,
    fallbackToolResults: fallbackToolResults,
    projectRoot: projectRoot,
  );
}

Map<String, dynamic> _payload(ToolResultInfo result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  group('DuplicateToolResultRecoveryInput', () {
    test('freezes all input lists', () {
      final callMetadata = <String, dynamic>{
        'paths': <Object?>['a.txt'],
      };
      final resultMetadata = <String, dynamic>{
        'paths': <Object?>['a.txt'],
      };
      final callArguments = <String, dynamic>{
        'path': 'a.txt',
        'metadata': callMetadata,
      };
      final resultArguments = <String, dynamic>{
        'path': 'a.txt',
        'metadata': resultMetadata,
      };
      final calls = <ToolCallInfo>[
        ToolCallInfo(id: 'call', name: 'read_file', arguments: callArguments),
      ];
      final executed = <ToolResultInfo>[
        ToolResultInfo(
          id: 'executed',
          name: 'read_file',
          arguments: resultArguments,
          result: 'done',
        ),
      ];
      final fallbacks = <ToolResultInfo>[
        _result(id: 'fallback', path: 'b.txt', result: 'context'),
      ];
      final input = _input(
        currentToolCalls: calls,
        executedToolResults: executed,
        fallbackToolResults: fallbacks,
      );

      calls.clear();
      executed.clear();
      fallbacks.clear();
      callArguments['path'] = 'mutated.txt';
      resultArguments['path'] = 'mutated.txt';
      (callMetadata['paths']! as List<Object?>).add('mutated.txt');
      (resultMetadata['paths']! as List<Object?>).add('mutated.txt');

      expect(input.currentToolCalls, hasLength(1));
      expect(input.executedToolResults, hasLength(1));
      expect(input.fallbackToolResults, hasLength(1));
      expect(input.currentToolCalls.single.arguments['path'], 'a.txt');
      expect(input.executedToolResults.single.arguments['path'], 'a.txt');
      expect(
        (input.currentToolCalls.single.arguments['metadata']
            as Map<String, dynamic>)['paths'],
        ['a.txt'],
      );
      expect(
        (input.executedToolResults.single.arguments['metadata']
            as Map<String, dynamic>)['paths'],
        ['a.txt'],
      );
      expect(
        () => input.currentToolCalls.add(_call(id: 'other', path: 'c.txt')),
        throwsUnsupportedError,
      );
      expect(
        () => input.executedToolResults.add(
          _result(id: 'other', path: 'c.txt', result: 'done'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => input.fallbackToolResults.add(
          _result(id: 'other', path: 'c.txt', result: 'done'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => input.currentToolCalls.single.arguments['path'] = 'other.txt',
        throwsUnsupportedError,
      );
      expect(
        () => input.executedToolResults.single.arguments['path'] = 'other.txt',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (input.currentToolCalls.single.arguments['metadata']
                    as Map<String, dynamic>)['other'] =
                true,
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.executedToolResults.single.arguments['metadata']
                        as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('other.txt'),
        throwsUnsupportedError,
      );
    });

    test('deeply freezes generic maps and sets without rewriting keys', () {
      final nestedList = <Object?>['owner-a'];
      final nestedSet = <Object?>{'stable'};
      final metadata = <Object?, Object?>{7: nestedList, 'tags': nestedSet};
      final input = _input(
        currentToolCalls: [
          ToolCallInfo(
            id: 'call',
            name: 'read_file',
            arguments: {'path': 'a.txt', 'metadata': metadata},
          ),
        ],
        executedToolResults: [
          ToolResultInfo(
            id: 'executed',
            name: 'read_file',
            arguments: {'path': 'a.txt', 'metadata': metadata},
            result: 'done',
          ),
        ],
        fallbackToolResults: [
          ToolResultInfo(
            id: 'fallback',
            name: 'read_file',
            arguments: {'path': 'b.txt', 'metadata': metadata},
            result: 'context',
          ),
        ],
      );

      nestedList.add('mutated');
      nestedSet.add('mutated');
      metadata['added'] = true;

      for (final arguments in [
        input.currentToolCalls.single.arguments,
        input.executedToolResults.single.arguments,
        input.fallbackToolResults.single.arguments,
      ]) {
        final frozen = arguments['metadata'] as Map<Object?, Object?>;
        expect(frozen[7], ['owner-a']);
        expect(frozen, isNot(contains('7')));
        expect(frozen['tags'], {'stable'});
        expect(frozen, isNot(contains('added')));
        expect(
          () => (frozen[7] as List<Object?>).add('other'),
          throwsUnsupportedError,
        );
        expect(
          () => (frozen['tags'] as Set<Object?>).add('other'),
          throwsUnsupportedError,
        );
        expect(() => frozen['added'] = true, throwsUnsupportedError);
      }
    });
  });

  group('recover', () {
    test('returns no results for empty inputs', () {
      expect(_recovery.recover(_input()), isEmpty);
    });

    test(
      'uses the latest matching result before unmatched fallback context',
      () {
        final recovered = _recovery.recover(
          _input(
            currentToolCalls: [
              _call(id: 'current-backend', path: 'lib/backend'),
              _call(id: 'current-missing', path: 'lib/missing.dart'),
            ],
            executedToolResults: [
              _result(
                id: 'older-backend',
                path: 'lib/backend',
                result: '{"entries":["old.dart"]}',
              ),
              _result(
                id: 'source-context',
                path: 'lib',
                result: '{"entries":["backend","main.dart"]}',
              ),
              _result(
                id: 'latest-backend',
                path: 'lib/backend',
                result:
                    '{"ok":false,"entries":["latest.dart"],'
                    '"code":"old","execution_reused":false}',
              ),
            ],
            fallbackToolResults: [
              _result(
                id: 'matching-fallback',
                path: 'lib/backend',
                result: '{"entries":["fallback.dart"]}',
              ),
              _result(
                id: 'source-context',
                path: 'lib',
                result: '{"entries":["backend","main.dart"]}',
              ),
            ],
            projectRoot: '/workspace/project',
          ),
        );

        expect(recovered.map((result) => result.id).toList(), [
          'current-backend',
          'source-context',
        ]);
        expect(recovered.first.name, 'read_file');
        expect(recovered.first.arguments, {'path': 'lib/backend'});
        final reused = _payload(recovered.first);
        expect(reused['ok'], isFalse);
        expect(reused['entries'], ['latest.dart']);
        expect(reused['code'], 'duplicate_tool_call_result_reused');
        expect(reused['execution_reused'], isTrue);
        expect(reused['prior_tool_call_id'], 'latest-backend');
        expect(reused['current_tool_call_id'], 'current-backend');
      },
    );

    test('wraps valid non-map and malformed prior results', () {
      final recovered = _recovery.recover(
        _input(
          currentToolCalls: [
            _call(id: 'current-list', path: 'list.txt'),
            _call(id: 'current-malformed', path: 'malformed.txt'),
          ],
          executedToolResults: [
            _result(
              id: 'prior-list',
              path: 'list.txt',
              result: '["one","two"]',
            ),
            _result(
              id: 'prior-malformed',
              path: 'malformed.txt',
              result: '{not-json',
            ),
          ],
        ),
      );

      expect(recovered, hasLength(2));
      expect(_payload(recovered[0]), {
        'ok': true,
        'code': 'duplicate_tool_call_result_reused',
        'execution_reused': true,
        'prior_tool_call_id': 'prior-list',
        'current_tool_call_id': 'current-list',
        'prior_result': '["one","two"]',
      });
      expect(_payload(recovered[1]), {
        'ok': true,
        'code': 'duplicate_tool_call_result_reused',
        'execution_reused': true,
        'prior_tool_call_id': 'prior-malformed',
        'current_tool_call_id': 'current-malformed',
        'prior_result': '{not-json',
      });
    });

    test('deduplicates identical fallbacks while preserving order', () {
      final recovered = _recovery.recover(
        _input(
          fallbackToolResults: [
            _result(id: 'first', path: 'a.txt', result: 'same'),
            _result(id: 'duplicate', path: './a.txt', result: 'same'),
            _result(id: 'different-result', path: 'a.txt', result: 'changed'),
            _result(id: 'second-path', path: 'b.txt', result: 'context'),
          ],
          projectRoot: '/workspace/project',
        ),
      );

      expect(recovered.map((result) => result.id).toList(), [
        'first',
        'different-result',
        'second-path',
      ]);
    });

    test('keeps final fallback deduplication reason-sensitive', () {
      final recovered = _recovery.recover(
        _input(
          fallbackToolResults: [
            _result(
              id: 'first-edit',
              name: 'edit_file',
              path: 'pubspec.yaml',
              reason: 'First reason',
              result: '{"replacements":1}',
            ),
            _result(
              id: 'second-edit',
              name: 'edit_file',
              path: 'pubspec.yaml',
              reason: 'Second reason',
              result: '{"replacements":1}',
            ),
          ],
          projectRoot: '/workspace/project',
        ),
      );

      expect(recovered.map((result) => result.id).toList(), [
        'first-edit',
        'second-edit',
      ]);
    });

    test('matches file mutations despite reworded reasons', () {
      final recovered = _recovery.recover(
        _input(
          currentToolCalls: [
            _call(
              id: 'current-edit',
              name: 'edit_file',
              path: 'pubspec.yaml',
              reason: 'Fix package imports.',
            ),
          ],
          executedToolResults: [
            _result(
              id: 'prior-edit',
              name: 'edit_file',
              path: 'pubspec.yaml',
              reason: 'Align the package name.',
              result: '{"replacements":1}',
            ),
          ],
        ),
      );

      expect(recovered.single.id, 'current-edit');
      expect(_payload(recovered.single)['prior_tool_call_id'], 'prior-edit');
    });

    test('resolves relative identity from either explicit project root', () {
      ToolResultInfo absoluteResult(String root) => _result(
        id: 'absolute-$root',
        path: '$root/lib/main.dart',
        result: '{"content":"main"}',
      );
      final current = [_call(id: 'current', path: 'lib/main.dart')];

      final underFirstRoot = _recovery.recover(
        _input(
          currentToolCalls: current,
          executedToolResults: [absoluteResult('/workspace/first')],
          projectRoot: '/workspace/first',
        ),
      );
      final wrongRoot = _recovery.recover(
        _input(
          currentToolCalls: current,
          executedToolResults: [absoluteResult('/workspace/first')],
          projectRoot: '/workspace/second',
        ),
      );
      final underSecondRoot = _recovery.recover(
        _input(
          currentToolCalls: current,
          executedToolResults: [absoluteResult('/workspace/second')],
          projectRoot: '/workspace/second',
        ),
      );

      expect(underFirstRoot, hasLength(1));
      expect(wrongRoot, isEmpty);
      expect(underSecondRoot, hasLength(1));
    });

    test(
      'matches trimmed, absolute, and URI-resolved paths under the root',
      () {
        final recovered = _recovery.recover(
          _input(
            currentToolCalls: [
              _call(id: 'current-relative', path: '  lib/other/../main.dart  '),
              _call(
                id: 'current-absolute',
                path: '  /workspace/project/pubspec.yaml  ',
              ),
            ],
            executedToolResults: [
              _result(
                id: 'prior-relative',
                path: '/workspace/project/lib/main.dart',
                result: '{"content":"main"}',
              ),
              _result(
                id: 'prior-absolute',
                path: '/workspace/project/pubspec.yaml',
                result: '{"content":"pubspec"}',
              ),
            ],
            projectRoot: '  /workspace/project  ',
          ),
        );

        expect(recovered.map((result) => result.id), [
          'current-relative',
          'current-absolute',
        ]);
      },
    );

    test('keeps a trimmed relative identity when the root is missing', () {
      final trimmedMatch = _recovery.recover(
        _input(
          currentToolCalls: [_call(id: 'current', path: '  relative.txt  ')],
          executedToolResults: [
            _result(id: 'prior', path: 'relative.txt', result: 'content'),
          ],
        ),
      );
      final workingDirectoryMismatch = _recovery.recover(
        _input(
          currentToolCalls: [_call(id: 'current', path: '  relative.txt  ')],
          executedToolResults: [
            _result(
              id: 'prior',
              path: '${Directory.current.absolute.path}/relative.txt',
              result: 'content',
            ),
          ],
          projectRoot: '  ',
        ),
      );

      expect(trimmedMatch, hasLength(1));
      expect(workingDirectoryMismatch, isEmpty);
    });

    test('expands a home-relative path before matching', () {
      if (Platform.isWindows) {
        return;
      }
      final home = Platform.environment['HOME']?.trim() ?? '';
      expect(home, isNotEmpty);
      final expectedPath = File(
        '$home/caverno-duplicate-recovery.txt',
      ).absolute.path;

      final recovered = _recovery.recover(
        _input(
          currentToolCalls: [
            _call(id: 'current', path: '~/caverno-duplicate-recovery.txt'),
          ],
          executedToolResults: [
            _result(id: 'prior', path: expectedPath, result: 'content'),
          ],
          projectRoot: '/ignored/project',
        ),
      );

      expect(recovered, hasLength(1));
    });

    test(
      'keeps absolute paths root-independent and relative paths unresolved',
      () {
        for (final root in ['/workspace/first', '/workspace/second']) {
          final recovered = _recovery.recover(
            _input(
              currentToolCalls: [
                _call(id: 'current-absolute', path: '/shared/data.json'),
              ],
              executedToolResults: [
                _result(
                  id: 'prior-absolute',
                  path: '/shared/data.json',
                  result: '{"size":1}',
                ),
              ],
              projectRoot: root,
            ),
          );
          expect(recovered, hasLength(1), reason: root);
        }

        for (final root in <String?>[null, '  ']) {
          final recovered = _recovery.recover(
            _input(
              currentToolCalls: [_call(id: 'current-relative', path: 'a.txt')],
              executedToolResults: [
                _result(id: 'prior-relative', path: 'a.txt', result: 'content'),
              ],
              projectRoot: root,
            ),
          );
          expect(recovered, hasLength(1), reason: '$root');
        }
      },
    );
  });
}
