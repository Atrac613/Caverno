import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Caverno CLI roadmap', () {
    late String roadmap;
    late String terminalContract;

    setUpAll(() {
      roadmap = File('docs/roadmap.md').readAsStringSync();
      terminalContract = File(
        'docs/caverno_cli_terminal_contract.md',
      ).readAsStringSync();
    });

    test('registers the CLI track and phased milestones', () {
      expect(roadmap, contains('Use `CLI<number>`'));
      expect(roadmap, contains('| Caverno CLI | CLI2 | done |'));
      expect(roadmap, contains('| Caverno CLI | CLI3 | done |'));
      expect(roadmap, contains('| Caverno CLI | CLI4 | later |'));
      expect(roadmap, contains('## Caverno CLI Track'));
      expect(
        roadmap,
        contains('### CLI0: Headless Production-Path Baseline And Contract'),
      );
      expect(
        roadmap,
        contains('### CLI1: Shared Application Execution Runtime'),
      );
      expect(roadmap, contains('### CLI2: Interactive Terminal MVP'));
      expect(
        roadmap,
        contains('### CLI3: Persistence, Resume, And Concurrent Ownership'),
      );
      expect(
        roadmap,
        contains('### CLI4: Packaging, Automation, And Release Gate'),
      );
      expect(roadmap, contains('direct_file_locking_sufficient'));
    });

    test('keeps headless and application canary responsibilities separate', () {
      expect(roadmap, contains('must not launch a desktop application window'));
      expect(
        roadmap,
        contains('macOS application lane remains a separate release'),
      );
      expect(
        roadmap,
        contains('same scenario contract, short prompt, saved workflow'),
      );
    });

    test('preserves fail-closed approval and Computer Use boundaries', () {
      expect(roadmap, contains('Non-interactive execution fails closed'));
      expect(roadmap, contains('absence of a GUI must never become approval'));
      expect(
        roadmap,
        contains('Computer Use remains unavailable from a headless CLI'),
      );
      expect(roadmap, contains('Treat SIGINT as cancellation'));
    });

    test('requires one runtime instead of a test-runner product wrapper', () {
      expect(roadmap, contains('must reuse Caverno\'s execution behavior'));
      expect(roadmap, contains('than wrapping a test command'));
      expect(
        roadmap,
        contains('Keep one prompt builder, tool dispatcher, tool-loop policy'),
      );
      expect(
        roadmap,
        contains('Release artifacts run without a Flutter test runner'),
      );
    });

    test('freezes the terminal input and output contract', () {
      expect(terminalContract, contains('caverno chat [input options]'));
      expect(terminalContract, contains('caverno coding --project <path>'));
      expect(terminalContract, contains('caverno plan --project <path>'));
      expect(terminalContract, contains('caverno conversations list'));
      expect(terminalContract, contains('caverno conversations show'));
      expect(terminalContract, contains('caverno doctor'));
      expect(terminalContract, contains('Configuration Precedence'));
      expect(terminalContract, contains('`schema`: `caverno_cli_event`'));
      expect(terminalContract, contains('`schemaVersion`: `1`'));
      expect(terminalContract, contains('| `130` |'));
      expect(terminalContract, contains('`conversation_list`'));
      expect(terminalContract, contains('`conversation_detail`'));
      expect(
        terminalContract,
        contains('do not initialize the LLM runtime, MCP clients, tools'),
      );
      expect(
        terminalContract,
        contains('caverno_cli_doctor_report'),
      );
      expect(
        terminalContract,
        allOf(
          contains('Linux and'),
          contains('Windows remain unsupported'),
        ),
      );
    });

    test('freezes fail-closed non-TTY and cancellation behavior', () {
      expect(
        terminalContract,
        contains('Non-TTY mode fails closed when an action requires approval'),
      );
      expect(
        terminalContract,
        allOf(
          contains('the absence of a GUI'),
          contains('never grants approval'),
        ),
      );
      expect(
        terminalContract,
        contains('Computer Use is unavailable from the headless CLI'),
      );
      expect(terminalContract, contains('SIGINT stops new LLM and tool work'));
    });
  });
}
