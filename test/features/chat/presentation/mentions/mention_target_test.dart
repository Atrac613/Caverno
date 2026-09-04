import 'package:caverno/features/chat/presentation/mentions/mention_target.dart';
import 'package:test/test.dart';

const _targets = [
  anabasisMentionTarget,
  MentionTarget(
    handle: 'reviewer',
    displayName: 'Reviewer',
    descriptionKey: 'chat.mention_reviewer_desc',
  ),
];

void main() {
  test('an empty @ offers everyone', () {
    expect(filterMentionSuggestions('@', _targets), _targets);
  });

  test('a prefix narrows by handle or display name', () {
    expect(filterMentionSuggestions('@ana', _targets), [anabasisMentionTarget]);
    expect(filterMentionSuggestions('@Rev', _targets), [_targets.last]);
    expect(filterMentionSuggestions('@zzz', _targets), isEmpty);
  });

  test('only at the start, because only there does it route', () {
    expect(
      filterMentionSuggestions('ask @ana about it', _targets),
      isEmpty,
      reason:
          'AnabasisAddress treats @anabasis as an address only in first '
          'position, so completing one mid-sentence would hand the user a '
          'mention that looks live and does nothing.',
    );
  });

  test('once the handle has a space after it the list gets out of the way', () {
    expect(filterMentionSuggestions('@anabasis plan it', _targets), isEmpty);
    expect(
      filterMentionSuggestions('@anabasis ', _targets),
      isEmpty,
      reason: 'The address is settled; what follows is the request.',
    );
  });

  test('the insertion leaves the caret where the request goes', () {
    expect(anabasisMentionTarget.insertion, '@anabasis ');
  });
}
