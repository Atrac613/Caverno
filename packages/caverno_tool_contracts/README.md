# Caverno Tool Contracts

`caverno_tool_contracts` contains Caverno's shared, pure-Dart contracts for tool
approval and capability classification. Security, chat, settings, tests, and
tooling use the same types without depending on application settings or UI.

This is an internal workspace package. It is not published independently and
does not grant permission to execute a tool.

## Responsibilities

- Define the persisted tool approval modes.
- Represent approval gate outcomes and denial escalation metadata.
- Classify tools by capability class, risk tier, and command effect.
- Report whether a classified action mutates state or crosses a network
  boundary.
- Apply deterministic command classification without performing the command.

The package does not own approval prompts, LLM auto-review, taint policy, audit
logging, routine policy, tool dispatch, or platform-specific enforcement.

## Public API

Import only the public library:

```dart
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
```

The supported API includes:

- Approval: `ToolApprovalMode`, `ToolApprovalGateOutcome`, and
  `ToolApprovalGateDecision`
- Capability: `ToolCapabilityClass`, `ToolRiskTier`, `ToolCommandEffect`, and
  `ToolCapability`
- Classification: `ToolCapabilityClassifier`

Do not import files below `lib/src`.

## Example

```dart
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

const classifier = ToolCapabilityClassifier();
final capability = classifier.classify(
  'local_execute_command',
  arguments: {'command': 'dart test'},
);

assert(capability.capabilityClass == ToolCapabilityClass.shellExecution);
assert(capability.commandEffect == ToolCommandEffect.verification);

final decision = ToolApprovalGateDecision.fromAutoReviewDenial(
  'The command needs confirmation.',
  hasUntrustedInfluence: false,
);
assert(decision.needsManual);
```

Classification is context for application policy, not authorization. A caller
must still apply the relevant approval, taint, audit, and execution rules.

## Compatibility And Security

The persisted `ToolApprovalMode` names are `defaultPermissions`, `autoReview`,
and `fullAccess`. Do not rename or reorder them without an explicit data
migration.

Classification changes can alter approval or audit behavior downstream. Add or
update direct tests for every tool family and command pattern before changing a
capability class, risk tier, command effect, mutation flag, or network flag.

## Development

Resolve the shared workspace from the repository root:

```bash
fvm flutter pub get
fvm dart pub workspace list
```

Run this package's checks:

```bash
cd packages/caverno_tool_contracts
fvm dart analyze
fvm dart test
```

Run the repository boundary gate after changing dependencies or public API:

```bash
cd ../..
tool/codex_verify.sh --test test/quality/package_boundary_test.dart
```
