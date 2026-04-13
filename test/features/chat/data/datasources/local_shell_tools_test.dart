import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks simple inspection commands as read-only', () {
    expect(LocalShellTools.isReadOnly('pwd'), isTrue);
    expect(LocalShellTools.isReadOnly('ls -la'), isTrue);
    expect(LocalShellTools.isReadOnly('rg ChatPage lib'), isTrue);
    expect(LocalShellTools.isReadOnly('git status --short'), isTrue);
  });

  test('marks mutating or shell-heavy commands as requiring approval', () {
    expect(LocalShellTools.isReadOnly('flutter test'), isFalse);
    expect(LocalShellTools.isReadOnly('rm -rf build'), isFalse);
    expect(LocalShellTools.isReadOnly('rg ChatPage lib | head'), isFalse);
    expect(LocalShellTools.isReadOnly('sed -i s/foo/bar/g file.txt'), isFalse);
  });
}
