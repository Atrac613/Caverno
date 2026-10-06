import 'package:caverno/features/project_farm/domain/project_task_decomposition_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps titled subtasks in order and drops blank ones', () {
    final subtasks = parseProjectTaskDecomposition({
      'subtasks': [
        {
          'title': ' Add parser ',
          'target_files': ['lib/a.dart', ' ', 3],
        },
        {'title': '  ', 'target_files': <String>[]},
        {'title': 'Add tests', 'target_files': <String>[]},
      ],
    });

    expect(subtasks.map((s) => s.title), ['Add parser', 'Add tests']);
    expect(subtasks.first.targetFiles, ['lib/a.dart']);
  });

  test('caps the outline and tolerates malformed responses', () {
    final many = parseProjectTaskDecomposition({
      'subtasks': [
        for (var i = 0; i < 10; i++) {'title': 'Step $i', 'target_files': []},
      ],
    });
    expect(many, hasLength(projectTaskMaxSubtasks));
    expect(parseProjectTaskDecomposition(null), isEmpty);
    expect(parseProjectTaskDecomposition({'subtasks': 'none'}), isEmpty);
  });

  test('the nested subtask schema requires every property', () {
    final item =
        (projectTaskDecompositionSchema['properties']
                as Map)['subtasks']['items']
            as Map;
    expect(
      (item['required'] as List).toSet(),
      (item['properties'] as Map).keys.toSet(),
    );
  });
}
