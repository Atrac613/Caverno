import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Thread-scope ratchet (docs/multi_thread_architecture_study.md).
///
/// ChatNotifier serves every thread from one object, and ChatState belongs to
/// the *visible* thread. So a method that already knows which turn it is
/// serving — it takes an interaction generation, or the turn's Conversation —
/// but reads visible-thread state anyway is how eleven defects were written on
/// 2026-07-25/26, including two adjacent arguments in the same call.
///
/// This test freezes the known set. Entries may be removed as call sites move
/// onto turn-scoped state; a new one fails. Never add an entry to make this
/// pass — pass the turn its own conversation, project or history instead.
///
/// A read is *not* listed when the method also consults a turn-scoped
/// accessor: those are the deliberate "this generation is the visible thread"
/// branches, which are correct.
const Set<String> _knownAmbientReads = {
  // Reviewed 2026-07-26 and correct: this runs at turn start, before the turn
  // can be anything but the visible thread, and registering the messages the
  // turn begins from is the whole point. Kept listed so the rule stays honest
  // rather than special-cased.
  'chat_notifier.dart::_trackActiveResponse::state.messages',
};

const String _providersDirectory =
    'lib/features/chat/presentation/providers';

const Map<String, String> _ambientReads = {
  'state.messages': r'\bstate\.messages\b',
  'currentConversation': r'\.currentConversation\b',
  'effectiveCodingProject': r'_getEffectiveCodingProject\(\)',
  'activeProjectRootPath': r'_getActiveProjectRootPath\(\)',
};

/// Consulting any of these means the method did ask which thread it serves.
final RegExp _asksWhichThread = RegExp(
  r'_activeResponseMessagesForGeneration|_isActiveResponseDetached'
  r'|_activeResponseConversationIdForGeneration|_conversationForId'
  r'|_codingProjectForTurn|TurnThread|TurnProjectRoot|_threadStates'
  r'|_cacheActiveResponseMessagesForGeneration|ThreadScopedChatState',
);

final RegExp _signature = RegExp(
  r'^  (?! )(?:static\s+)?[\w<>?,\s\[\]]+?\s+(_?[a-zA-Z]\w*)\s*\(',
);

const Set<String> _keywords = {
  'if', 'for', 'while', 'switch', 'return', 'else', 'catch', 'do', 'await',
  'assert', 'yield', 'throw', 'case',
};

final RegExp _turnParameter = RegExp(r'\b(interactionGeneration|generation)\b');
final RegExp _conversationParameter = RegExp(
  r'\bConversation\??\s+\w+|currentConversation:',
);

void main() {
  test('turn-scoped code does not read visible-thread state', () {
    final found = <String>{};

    for (final file in Directory(_providersDirectory)
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return name.startsWith('chat_notifier') && name.endsWith('.dart');
        })) {
      final name = file.uri.pathSegments.last;
      for (final method in _methods(file.readAsLinesSync())) {
        final signature = method.lines.take(6).join('\n');
        final knowsTurn =
            _turnParameter.hasMatch(signature) ||
            _conversationParameter.hasMatch(signature);
        if (!knowsTurn) continue;
        final body = method.lines.join('\n');
        if (_asksWhichThread.hasMatch(body)) continue;
        for (final entry in _ambientReads.entries) {
          if (RegExp(entry.value).hasMatch(body)) {
            found.add('$name::${method.name}::${entry.key}');
          }
        }
      }
    }

    final added = found.difference(_knownAmbientReads);
    expect(
      added,
      isEmpty,
      reason:
          'New turn-scoped code reads visible-thread state:\n'
          '${added.join('\n')}\n\n'
          'This method already knows which turn it serves. Pass the turn its '
          'own conversation, project or history instead of reading the '
          'visible thread. See docs/multi_thread_architecture_study.md.',
    );

    final removed = _knownAmbientReads.difference(found);
    expect(
      removed,
      isEmpty,
      reason:
          'These entries no longer exist, so drop them from the list and let '
          'the ratchet shrink:\n${removed.join('\n')}',
    );
  });
}

class _Method {
  const _Method(this.name, this.lines);

  final String name;
  final List<String> lines;
}

/// Splits a part file into methods by brace counting, so a nested `if` is not
/// mistaken for a declaration.
Iterable<_Method> _methods(List<String> lines) sync* {
  var index = 0;
  while (index < lines.length) {
    final match = _signature.firstMatch(lines[index]);
    final name = match?.group(1);
    if (match == null ||
        name == null ||
        _keywords.contains(name) ||
        lines[index].trimLeft().startsWith('//')) {
      index += 1;
      continue;
    }

    var depth = 0;
    var started = false;
    var end = index;
    for (var cursor = index; cursor < lines.length; cursor += 1) {
      for (final character in lines[cursor].split('')) {
        if (character == '{') {
          depth += 1;
          started = true;
        } else if (character == '}') {
          depth -= 1;
        }
      }
      end = cursor;
      if (started && depth == 0) break;
      if (!started && lines[cursor].trimRight().endsWith(';')) break;
    }
    yield _Method(name, lines.sublist(index, end + 1));
    index = end + 1;
  }
}
