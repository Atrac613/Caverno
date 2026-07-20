# Caverno Execution Runtime

`caverno_execution_runtime` is Caverno's frontend-neutral, pure-Dart execution
runtime. It provides one turn lifecycle and one event contract for the Flutter
GUI, headless harnesses, and terminal frontend.

This is an internal workspace package. It is not published independently and
does not own application composition.

## Responsibilities

- Acquire and release execution ownership for a turn.
- Refresh the selected conversation before execution begins.
- Emit ordered runtime events for assistant output, tools, approvals,
  questions, workflow transitions, usage, and terminal outcomes.
- Flush pending persistence before releasing ownership.
- Classify runtime failures into stable error and exit-code categories.
- Prevent duplicate active turn identifiers and reject work after shutdown.

The package does not implement LLM transport, tool execution, approval UI,
storage, Riverpod providers, or frontend navigation. Applications supply those
concerns through ports.

## Public API

Import only the public library:

```dart
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
```

The public API is organized into four groups:

- Runtime: `CavernoExecutionRuntime`, `CavernoRuntimeTurnRequest`, and
  `CavernoRuntimeTurnHandle`
- Composition and ports: `CavernoRuntimeComposition` and the settings,
  repository, ownership, LLM, tool, approval, log, and lifecycle ports
- Events: `CavernoRuntimeEvent` and its typed lifecycle event subclasses
- Failures: `CavernoRuntimeFailureClassifier` and
  `CavernoRuntimeFailureClassification`

Do not import files below `lib/src`.

## Example

Application adapters implement the runtime ports and assemble a composition:

```dart
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';

Future<void> runTurn(CavernoRuntimeComposition composition) async {
  final runtime = CavernoExecutionRuntime(composition: composition);
  final subscription = runtime.events.listen((event) {
    print(event.toJson());
  });

  final turn = await runtime.startTurn(
    const CavernoRuntimeTurnRequest(turnId: 'turn-1'),
  );
  turn.emitAssistantDelta('Hello');
  turn.complete(content: 'Hello');

  await runtime.close();
  await subscription.cancel();
}
```

Every started turn must reach one terminal outcome through `complete`, `fail`,
or runtime shutdown. Consumers should treat the event schema and terminal exit
codes as compatibility surfaces.

## Architecture Boundary

Dependencies point from the Caverno application to this package. The package
must remain independent of Flutter, Riverpod, persistence plugins, platform
plugins, operating-system APIs, and `package:caverno`.

File-backed ownership leases and concrete adapters stay in the root
application. Add a port only when more than one frontend needs the same stable
contract.

## Development

Resolve the shared workspace from the repository root:

```bash
fvm flutter pub get
fvm dart pub workspace list
```

Run this package's checks:

```bash
cd packages/caverno_execution_runtime
fvm dart analyze
fvm dart test
```

Run the repository boundary gate after changing dependencies or public API:

```bash
cd ../..
tool/codex_verify.sh --test test/quality/package_boundary_test.dart
```
