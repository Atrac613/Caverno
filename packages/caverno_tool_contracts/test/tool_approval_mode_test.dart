import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('preserves persisted approval mode names and order', () {
    expect(ToolApprovalMode.values.map((mode) => mode.name).toList(), [
      'defaultPermissions',
      'autoReview',
      'fullAccess',
    ]);
  });
}
