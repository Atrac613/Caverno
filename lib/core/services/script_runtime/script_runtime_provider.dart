import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'python_script_runtime.dart';
import 'script_runtime.dart';

/// App-lifetime registry of on-device script runtimes.
///
/// Holds the long-lived Python worker so it survives [McpToolService] rebuilds
/// (which happen on settings changes); the worker is started lazily on first
/// use and torn down when the provider is disposed.
final scriptRuntimeRegistryProvider = Provider<ScriptRuntimeRegistry>((ref) {
  final registry = ScriptRuntimeRegistry([PythonScriptRuntime()]);
  ref.onDispose(registry.dispose);
  return registry;
});
