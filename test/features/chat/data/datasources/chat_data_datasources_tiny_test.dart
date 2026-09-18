// One suite for the 10 tiny datasources test files
// this replaces. Each paid a full suite-loading cost to run at most
// 3 tests. Part files keep every case set in its own file without
// adding a suite, which is the split the file-size ratchet asks for.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_diagnostic_bridge.dart';
import 'package:caverno/features/chat/data/datasources/lsp_json_rpc_process_transport.dart';
import 'package:caverno/features/chat/data/datasources/os_log_tools.dart';
import 'package:caverno/features/chat/data/datasources/python_input_staging.dart';
import 'package:caverno/features/chat/data/datasources/python_script_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/datasources/qwen38_request_policy_client.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_generation_dao.dart';
import 'package:caverno/features/chat/data/datasources/rag2_drift_schema.dart';
import 'package:caverno/features/chat/data/datasources/remote_mcp_tool_name_policy.dart';
import 'package:caverno/features/chat/domain/entities/chat_completion_terminal_metadata.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/services/python_script_tool_contract.dart';
import 'package:caverno/features/chat/domain/services/qwen38_request_thinking_policy.dart';
// drift exports an `isNull` column predicate that shadows the matcher the
// other parts in this suite use. No part here needs drift's.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'python_script_runtime_test_support.dart';

part 'chat_completion_terminal_metadata_cases.dart';
part 'llm_session_log_usage_detail_cases.dart';
part 'lsp_json_rpc_process_transport_cases.dart';
part 'os_log_tools_cases.dart';
part 'python_execution_authority_cases.dart';
part 'python_input_staging_cases.dart';
part 'python_input_staging_runtime_adapter_cases.dart';
part 'qwen38_request_policy_client_cases.dart';
part 'rag2_drift_generation_dao_cases.dart';
part 'remote_mcp_tool_name_policy_cases.dart';

void main() {
  _runChatCompletionTerminalMetadata();
  _runLlmSessionLogUsageDetail();
  _runLspJsonRpcProcessTransport();
  _runOsLogTools();
  _runPythonExecutionAuthority();
  _runPythonInputStaging();
  _runPythonInputStagingRuntimeAdapter();
  _runQwen38RequestPolicyClient();
  _runRag2DriftGenerationDao();
  _runRemoteMcpToolNamePolicy();
}
