import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/skill_similarity_service.dart';
import 'package:flutter_test/flutter_test.dart';

Skill _skill(
  String name, {
  String description = '',
  String whenToUse = '',
  String id = '',
}) {
  final at = DateTime(2026, 6, 23);
  return Skill(
    id: id.isEmpty ? 'id-$name' : id,
    name: name,
    description: description,
    whenToUse: whenToUse,
    content: '# $name',
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  group('SkillSimilarityService.findSimilar', () {
    test('flags a different-named but token-overlapping skill', () {
      final matches = SkillSimilarityService.findSimilar(
        name: 'iOS macOS Release',
        existing: [_skill('iOS Release')],
      );
      expect(matches, hasLength(1));
      expect(matches.single.skill.normalizedName, 'iOS Release');
      expect(matches.single.score, greaterThanOrEqualTo(0.6));
    });

    test('flags a name contained within an existing name', () {
      final matches = SkillSimilarityService.findSimilar(
        name: 'Release',
        existing: [_skill('iOS Release')],
      );
      expect(matches, hasLength(1));
      expect(matches.single.skill.normalizedName, 'iOS Release');
    });

    test('excludes the exact-name match (handled as an update)', () {
      final matches = SkillSimilarityService.findSimilar(
        name: 'iOS Release',
        existing: [_skill('iOS Release')],
      );
      expect(matches, isEmpty);
    });

    test('does not flag unrelated skills', () {
      final matches = SkillSimilarityService.findSimilar(
        name: 'Database Backup',
        existing: [_skill('iOS Release'), _skill('Send Slack Digest')],
      );
      expect(matches, isEmpty);
    });

    test('description overlap lifts a weak name match over the threshold', () {
      final matches = SkillSimilarityService.findSimilar(
        name: 'Ship Mobile App',
        description: 'archive and upload an ios build to app store connect',
        existing: [
          _skill(
            'iOS Release',
            description: 'archive and upload an ios build to app store connect',
          ),
        ],
      );
      expect(matches, hasLength(1));
    });

    test('matches CJK names via compact containment', () {
      final matches = SkillSimilarityService.findSimilar(
        name: 'iOSリリース手順',
        existing: [_skill('リリース手順')],
      );
      expect(matches, hasLength(1));
    });

    test('returns matches sorted by descending score', () {
      // "Release" is a compact substring of "iOS Release" (containment, high
      // score); "Release for iOS" only overlaps on two of three tokens (lower
      // Jaccard score, no containment).
      final matches = SkillSimilarityService.findSimilar(
        name: 'iOS Release',
        existing: [
          _skill('Release for iOS'),
          _skill('Release'),
        ],
      );
      expect(matches, hasLength(2));
      expect(matches.first.skill.normalizedName, 'Release');
      for (var i = 1; i < matches.length; i++) {
        expect(
          matches[i - 1].score,
          greaterThanOrEqualTo(matches[i].score),
        );
      }
    });

    test('empty existing list yields no matches', () {
      expect(
        SkillSimilarityService.findSimilar(name: 'iOS Release', existing: []),
        isEmpty,
      );
    });
  });
}
