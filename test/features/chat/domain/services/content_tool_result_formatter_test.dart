import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/content_tool_result_formatter.dart';

void main() {
  group('ContentToolResultFormatter.format', () {
    group('entry maps', () {
      test(
        'uses the implicit count and keeps only three normalized details',
        () {
          final longEntry = List.filled(89, 'x').join();
          final expectedTruncatedEntry = '${List.filled(87, 'x').join()}...';
          final result = jsonEncode({
            'path': '/repo',
            'entries': [
              ' lib/a.dart ',
              'line\nwith\tspace',
              longEntry,
              'ignored.dart',
            ],
          });

          expect(
            ContentToolResultFormatter.format('list_files', result),
            _tag(
              '{"name":"list_files","summary":"4 item(s) in /repo",'
              '"details":["lib/a.dart","line with space",'
              '"$expectedTruncatedEntry"]}',
            ),
          );
        },
      );

      test('prefers an explicit count and compacts a non-string path', () {
        expect(
          ContentToolResultFormatter.format(
            'list_files',
            '{"path":["root","src"],"entries":[],"entry_count":12}',
          ),
          _tag(
            '{"name":"list_files",'
            '"summary":"12 item(s) in [\\"root\\",\\"src\\"]"}',
          ),
        );
      });
    });

    group('match maps', () {
      test('summarizes query matches with an explicit count', () {
        expect(
          ContentToolResultFormatter.format(
            'search_files',
            jsonEncode({
              'query': 'ChatNotifier',
              'matches': [' first ', 'second\nline', 'third', 'ignored'],
              'match_count': 9,
            }),
          ),
          _tag(
            '{"name":"search_files",'
            '"summary":"9 match(es) for ChatNotifier",'
            '"details":["first","second line","third"]}',
          ),
        );
      });

      test('summarizes pattern matches with an implicit count', () {
        expect(
          ContentToolResultFormatter.format(
            'find_files',
            '{"pattern":"*.dart","matches":["lib/a.dart","lib/b.dart"]}',
          ),
          _tag(
            '{"name":"find_files","summary":"2 file(s) for *.dart",'
            '"details":["lib/a.dart","lib/b.dart"]}',
          ),
        );
      });

      test('summarizes matches without a query or pattern key', () {
        expect(
          ContentToolResultFormatter.format(
            'scan',
            '{"matches":[],"match_count":5}',
          ),
          _tag('{"name":"scan","summary":"5 match(es)"}'),
        );
      });
    });

    group('content maps', () {
      test('uses the path and keeps two normalized non-empty lines', () {
        expect(
          ContentToolResultFormatter.format(
            'read_file',
            jsonEncode({
              'path': '/repo/readme.md',
              'content': ' first line \r\n\r\n second\t line \n third ignored ',
            }),
          ),
          _tag(
            '{"name":"read_file","summary":"/repo/readme.md",'
            '"details":["first line","second line"]}',
          ),
        );
      });

      test('omits details for empty content', () {
        expect(
          ContentToolResultFormatter.format(
            'read_file',
            '{"path":"/repo/empty.txt","content":" \\n\\r "}',
          ),
          _tag('{"name":"read_file","summary":"/repo/empty.txt"}'),
        );
      });

      test('applies the 96-character content detail limit', () {
        final longLine = List.filled(97, 'c').join();
        final expectedTruncatedLine = '${List.filled(95, 'c').join()}...';

        expect(
          ContentToolResultFormatter.format(
            'read_file',
            jsonEncode({'path': '/repo/long.txt', 'content': longLine}),
          ),
          _tag(
            '{"name":"read_file","summary":"/repo/long.txt",'
            '"details":["$expectedTruncatedLine"]}',
          ),
        );
      });
    });

    group('mutation maps', () {
      test('summarizes written bytes and a newly created file', () {
        expect(
          ContentToolResultFormatter.format(
            'write_file',
            '{"path":"/tmp/out.txt","bytes_written":128,"created":true}',
          ),
          _tag(
            '{"name":"write_file","summary":"/tmp/out.txt",'
            '"details":["bytes: 128","created"]}',
          ),
        );
      });

      test('does not report created when the flag is false', () {
        expect(
          ContentToolResultFormatter.format(
            'write_file',
            '{"path":null,"bytes_written":null,"created":false}',
          ),
          _tag(
            '{"name":"write_file","summary":"unknown",'
            '"details":["bytes: null"]}',
          ),
        );
      });

      test('summarizes replacements and replace-all mode', () {
        expect(
          ContentToolResultFormatter.format(
            'replace_text',
            '{"path":"/tmp/out.txt","replacements":4,"replace_all":true}',
          ),
          _tag(
            '{"name":"replace_text","summary":"/tmp/out.txt",'
            '"details":["replacements: 4","replace all"]}',
          ),
        );
      });

      test('does not report replace-all when the flag is false', () {
        expect(
          ContentToolResultFormatter.format(
            'replace_text',
            '{"path":"/tmp/out.txt","replacements":0,"replace_all":false}',
          ),
          _tag(
            '{"name":"replace_text","summary":"/tmp/out.txt",'
            '"details":["replacements: 0"]}',
          ),
        );
      });
    });

    group('generic maps', () {
      test(
        'filters empty values, compacts JSON, and caps details at three',
        () {
          expect(
            ContentToolResultFormatter.format(
              'inspect',
              jsonEncode({
                'path': '/repo/file.dart',
                'null_value': null,
                'empty_value': '',
                'enabled': true,
                'metadata': {'lines': 2},
                'items': [1, 2],
              }),
            ),
            _tag(
              '{"name":"inspect","summary":"/repo/file.dart",'
              '"details":["path: /repo/file.dart","enabled: true",'
              '"metadata: {\\"lines\\":2}"]}',
            ),
          );
        },
      );

      test('falls back to query for the summary', () {
        expect(
          ContentToolResultFormatter.format(
            'inspect',
            '{"query":"needle","status":"ok"}',
          ),
          _tag(
            '{"name":"inspect","summary":"needle",'
            '"details":["query: needle","status: ok"]}',
          ),
        );
      });

      test('falls back to pattern for the summary', () {
        expect(
          ContentToolResultFormatter.format(
            'inspect',
            '{"pattern":"*.md","status":"ok"}',
          ),
          _tag(
            '{"name":"inspect","summary":"*.md",'
            '"details":["pattern: *.md","status: ok"]}',
          ),
        );
      });

      test('falls back to Completed when no summary key is present', () {
        expect(
          ContentToolResultFormatter.format('inspect', '{"status":"ok"}'),
          _tag(
            '{"name":"inspect","summary":"Completed",'
            '"details":["status: ok"]}',
          ),
        );
        expect(
          ContentToolResultFormatter.format('inspect', '{}'),
          _tag('{"name":"inspect","summary":"Completed"}'),
        );
      });

      test('applies the 72-character generic detail limit', () {
        final longValue = List.filled(73, 'g').join();
        final expectedTruncatedValue = '${List.filled(71, 'g').join()}...';

        expect(
          ContentToolResultFormatter.format(
            'inspect',
            jsonEncode({'value': longValue}),
          ),
          _tag(
            '{"name":"inspect","summary":"Completed",'
            '"details":["value: $expectedTruncatedValue"]}',
          ),
        );
      });
    });

    test('summarizes JSON lists and keeps only three compact values', () {
      expect(
        ContentToolResultFormatter.format(
          'collect',
          jsonEncode([
            ' first ',
            {'id': 1},
            null,
            'ignored',
          ]),
        ),
        _tag(
          '{"name":"collect","summary":"4 item(s)",'
          '"details":[" first ","{\\"id\\":1}","unknown"]}',
        ),
      );
    });

    test('uses Completed for every valid scalar JSON value', () {
      for (final result in ['"done"', '42', 'true', 'null']) {
        expect(
          ContentToolResultFormatter.format('scalar', result),
          _tag('{"name":"scalar","summary":"Completed"}'),
          reason: 'Scalar input: $result',
        );
      }
    });

    group('plain text', () {
      test('normalizes whitespace and keeps only two detail lines', () {
        expect(
          ContentToolResultFormatter.format(
            'shell',
            '  command   completed\t successfully \r\n'
                ' first\t detail \n\n'
                ' second   detail \r'
                ' ignored detail ',
          ),
          _tag(
            '{"name":"shell","summary":"command completed successfully",'
            '"details":["first detail","second detail"]}',
          ),
        );
      });

      test('treats malformed JSON as text', () {
        expect(
          ContentToolResultFormatter.format(
            'decode',
            '{not valid json}\nparser stopped',
          ),
          _tag(
            '{"name":"decode","summary":"{not valid json}",'
            '"details":["parser stopped"]}',
          ),
        );
      });

      test('uses Completed for empty and whitespace-only input', () {
        for (final result in ['', ' \t\r\n ']) {
          expect(
            ContentToolResultFormatter.format('empty', result),
            _tag('{"name":"empty","summary":"Completed"}'),
          );
        }
      });

      test('preserves exactly 72 summary characters', () {
        final boundary = List.filled(72, 's').join();

        expect(
          ContentToolResultFormatter.format('plain', boundary),
          _tag('{"name":"plain","summary":"$boundary"}'),
        );
      });

      test('truncates a 73-character summary after 71 characters', () {
        final overLimit = List.filled(73, 's').join();
        final expected = '${List.filled(71, 's').join()}...';

        expect(
          ContentToolResultFormatter.format('plain', overLimit),
          _tag('{"name":"plain","summary":"$expected"}'),
        );
      });

      test('applies the 96-character plain-text detail limit', () {
        final longDetail = List.filled(97, 'd').join();
        final expected = '${List.filled(95, 'd').join()}...';

        expect(
          ContentToolResultFormatter.format('plain', 'done\n$longDetail'),
          _tag('{"name":"plain","summary":"done","details":["$expected"]}'),
        );
      });
    });

    test('JSON-escapes the tool name, summary, and detail values', () {
      expect(
        ContentToolResultFormatter.format(
          'tool"\\\nname',
          jsonEncode({'path': 'C:\\tmp"file'}),
        ),
        _tag(
          r'{"name":"tool\"\\\nname","summary":"C:\\tmp\"file",'
          r'"details":["path: C:\\tmp\"file"]}',
        ),
      );
    });
  });
}

String _tag(String payload) => '<tool_result>$payload</tool_result>';
