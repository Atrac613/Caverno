import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/services/anabasis_turn_roles.dart';
import 'package:test/test.dart';

void main() {
  test('an addressed turn bills and runs as the parent', () {
    final roles = AnabasisTurnRoles()
      ..markAddressed(generation: 7, content: '@anabasis plan the migration');

    expect(roles.mainLoopRoleFor(7), ModelUsageRole.anabasisParent);
  });

  test('an unaddressed turn stays on the chat role', () {
    final roles = AnabasisTurnRoles()
      ..markAddressed(generation: 7, content: 'plan the migration');

    expect(roles.mainLoopRoleFor(7), ModelUsageRole.chat);
  });

  test('one thread\'s role does not leak into another turn', () {
    final roles = AnabasisTurnRoles()
      ..markAddressed(generation: 7, content: '@anabasis go')
      ..markAddressed(generation: 8, content: 'keep going');

    expect(roles.mainLoopRoleFor(8), ModelUsageRole.chat);
    expect(
      roles.mainLoopRoleFor(7),
      ModelUsageRole.anabasisParent,
      reason:
          'Generations rather than a single flag, because threads run '
          'concurrently and a flag would carry one thread\'s role into '
          "another's turn.",
    );
  });

  test('a released generation is no longer the parent', () {
    final roles = AnabasisTurnRoles()
      ..markAddressed(generation: 7, content: '@anabasis go')
      ..release(7);

    expect(roles.mainLoopRoleFor(7), ModelUsageRole.chat);
  });

  test('clear drops every turn', () {
    final roles = AnabasisTurnRoles()
      ..markAddressed(generation: 7, content: '@anabasis go')
      ..clear();

    expect(roles.mainLoopRoleFor(7), ModelUsageRole.chat);
  });
}
