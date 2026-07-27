import 'package:integration_test/integration_test.dart';

import '../tool/canaries/multi_thread_plan_live_canary_test.dart'
    as multi_thread_canary;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  multi_thread_canary.main();
}
