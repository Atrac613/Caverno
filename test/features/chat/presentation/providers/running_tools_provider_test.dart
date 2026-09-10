import 'package:caverno/features/chat/presentation/providers/running_tools_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late RunningToolsNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(runningToolsProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('builds with no dependencies, so any scope can read it', () {
    expect(container.read(runningToolsProvider), isEmpty);
    expect(notifier.forConversation('a'), isEmpty);
  });

  test('scopes running tools to the thread that started them', () {
    notifier.track('thread-a', 'read_file', 'started');
    notifier.track('thread-b', 'grep', 'started');

    expect(notifier.forConversation('thread-a'), ['read_file']);
    expect(notifier.forConversation('thread-b'), ['grep']);
  });

  test('drops the thread entry once its last tool finishes', () {
    notifier.track('thread-a', 'read_file', 'started');
    notifier.track('thread-a', 'read_file', 'completed');

    expect(container.read(runningToolsProvider).containsKey('thread-a'), false);
  });

  test('ignores a tool with no live turn to attribute it to', () {
    notifier.track(null, 'read_file', 'started');

    expect(container.read(runningToolsProvider), isEmpty);
  });

  test('clear drops a turn killed mid-tool', () {
    notifier.track('thread-a', 'read_file', 'started');
    notifier.clear('thread-a');

    expect(notifier.forConversation('thread-a'), isEmpty);
  });

  test('clear on an untracked thread does not notify', () {
    var notifications = 0;
    container.listen(runningToolsProvider, (_, _) => notifications++);

    notifier.clear('thread-none');

    expect(notifications, 0);
  });
}
