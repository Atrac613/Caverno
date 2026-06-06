import 'package:integration_test/integration_test.dart';

import '../tool/canaries/chat_live_llm_canary_test.dart' as chat_live_canary;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  chat_live_canary.main();
}
