import 'package:caverno/features/chat/data/datasources/remote_mcp_tool_name_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteMcpToolNamePolicy', () {
    test(
      'neutralizes reserved prefixes case-insensitively within 64 characters',
      () {
        final policy = RemoteMcpToolNamePolicy(
          reservedToolNames: const {'reserved_name'},
          reservedToolNamePrefixes: const {' browser_ ', 'COMPUTER_', ''},
        );
        final usedNames = policy.createUsedNames();
        final longBrowserName = 'browser_${List.filled(80, 'x').join()}';
        final originalNames = [
          'browser_open',
          'Browser_Export_State',
          'computer_click',
          'COMPUTER_Custom_Action',
          longBrowserName,
        ];

        final exposedNames = [
          for (final name in originalNames)
            policy.buildExposedName(
              baseName: name,
              identifier: 'https://prefixes.example.com/mcp',
              usedNames: usedNames,
              duplicateCount: 1,
            ),
        ];

        expect(exposedNames.toSet(), hasLength(originalNames.length));
        for (final name in exposedNames) {
          expect(name, startsWith('mcp__'));
          expect(name.toLowerCase(), isNot(startsWith('browser_')));
          expect(name.toLowerCase(), isNot(startsWith('computer_')));
          expect(
            name.length,
            lessThanOrEqualTo(RemoteMcpToolNamePolicy.maxToolNameLength),
          );
        }

        expect(
          policy.buildExposedName(
            baseName: 'ordinary_tool',
            identifier: 'https://prefixes.example.com/mcp',
            usedNames: usedNames,
            duplicateCount: 1,
          ),
          'ordinary_tool',
        );
        expect(
          policy.buildExposedName(
            baseName: 'reserved_name',
            identifier: 'https://prefixes.example.com/mcp',
            usedNames: usedNames,
            duplicateCount: 1,
          ),
          startsWith('reserved_name__'),
        );
      },
    );

    test('keeps duplicate neutral aliases deterministic and unique', () {
      final policy = RemoteMcpToolNamePolicy(
        reservedToolNames: const {},
        reservedToolNamePrefixes: const {'browser_'},
      );
      final usedNames = policy.createUsedNames();

      final first = policy.buildExposedName(
        baseName: 'browser_export_state',
        identifier: 'https://duplicate.example.com/mcp',
        usedNames: usedNames,
        duplicateCount: 2,
      );
      final second = policy.buildExposedName(
        baseName: 'browser_export_state',
        identifier: 'https://duplicate.example.com/mcp',
        usedNames: usedNames,
        duplicateCount: 2,
      );

      expect(first, startsWith('mcp__browser_export_state__'));
      expect(second, endsWith('_2'));
      expect(second, isNot(first));
      expect(
        [first, second].every(
          (name) => name.length <= RemoteMcpToolNamePolicy.maxToolNameLength,
        ),
        isTrue,
      );
    });
  });
}
