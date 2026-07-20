# Component Packaging Architecture

This document defines how Caverno should split stable code boundaries and
runtime-installable components. The design borrows the useful separation in
[GitHub Spec Kit](https://github.com/github/spec-kit) between a compiled CLI,
internal modules, bundled defaults, declarative extensions, workflows, presets,
and bundles. It adapts that pattern to Flutter's ahead-of-time compilation and
to Caverno's stronger tool-execution security requirements.

The objective is not to maximize the number of packages. The objective is to
make dependency direction, public contracts, runtime capabilities, component
provenance, and update behavior explicit.

## Decisions

1. Caverno remains the application composition root.
2. Stable, reusable code boundaries become compile-time internal Dart packages.
3. Flutter and Riverpod orchestration remains in app-local feature modules until
   it has a stable reusable contract and an acyclic dependency direction.
4. Runtime-installable components are data-only manifests and assets. They do
   not contain executable Dart, JavaScript, shell, SQL, native code, or dynamic
   libraries.
5. External execution crosses an explicit adapter boundary such as MCP, HTTP,
   stdio, or a precompiled platform implementation. Installing a component does
   not grant that adapter any permission.
6. Built-in components use the same manifest validation and registry lookup as
   future installed components, but ship in a trusted, offline core pack.
7. Bundles pin compatible component versions; they do not introduce another
   execution mechanism.
8. Package extraction is behavior-preserving. It must not be used merely to hide
   a large file or move application composition out of sight.

The architectural mapping is intentional:

| Spec Kit concept | Caverno equivalent |
|---|---|
| Compiled CLI distribution | Caverno application composition root |
| Internal CLI modules | Internal Dart packages and app-local modules |
| Bundled `core_pack` | Validated core component pack shipped with the app |
| Extension, workflow, and preset manifests | Data-only component packs |
| Bundle manifest | Pinned component bundle plus lock record |

Caverno deliberately diverges where Flutter AOT compilation and tool security
require precompiled implementations, explicit capabilities, and stricter trust
enforcement.

## Terminology

The word **package** is reserved for a Dart or Flutter package resolved at build
time. The word **component** refers to a declarative unit resolved by Caverno at
runtime. Keeping these terms separate avoids treating a data manifest as if it
were trusted application code.

### Compile-Time Internal Dart Package

A repository-local package under `packages/` that owns a stable public contract
or reusable runtime. It is compiled with the application and is not installed
after release.

Examples include:

- `caverno_execution_runtime`
- the planned `caverno_content_protocol`
- future tool, LLM, or workflow contracts that have multiple consumers

Internal packages use `publish_to: none`, expose an intentional public library,
and never depend on the root `package:caverno` application.

### App-Local Flutter Module

A feature, service, provider, page, or widget that remains below `lib/`. It may
compose Riverpod state, persistence, Flutter navigation, platform services, and
multiple internal packages.

`ChatNotifier`, `ChatPage`, `MessageInput`, `McpToolService`, settings pages, and
debug pages are app-local modules today. Moving them unchanged into packages
would preserve their cyclic dependencies and would not create a useful
boundary.

### Data-Only Component Pack

A versioned manifest plus optional templates, workflows, presets, and static
assets interpreted by a Caverno-owned runtime. A component can only reference
component types, actions, capabilities, and entrypoint identifiers registered
by the installed application.

A component pack cannot define executable behavior. Unknown manifest versions,
component kinds, actions, capabilities, entrypoints, or references fail closed.

### External Adapter

A bridge between a Caverno contract and an external system. An adapter can be:

- a compile-time Dart or Flutter package implementing an internal port;
- an app-local implementation backed by a platform plugin; or
- an explicitly configured MCP, HTTP, or stdio boundary.

Adapters own serialization and protocol details. Domain packages do not import
adapter implementations. Runtime component manifests may request a registered
adapter capability, but they cannot provide an implementation or bypass the
existing approval policy.

### Bundle

A declarative, versioned collection of component references and compatibility
constraints. A bundle makes a tested configuration reproducible, but it neither
contains application code nor expands the permissions of its members.

Resolution produces a lock record with exact component versions and content
digests. Each component is still validated and authorized independently.

## Dependency Direction

The allowed compile-time dependency graph is:

```text
Caverno application composition root
  -> app-local Flutter modules
      -> platform and protocol adapters
          -> pure runtimes
              -> contract packages
  -> built-in registry assembly
      -> registered package APIs
```

Runtime data follows a separate path:

```text
Bundle manifest
  -> component manifests and assets
      -> manifest validator and policy engine
          -> static registry lookup
              -> precompiled runtime or approved external adapter
```

The following dependencies are forbidden:

- an internal package importing `package:caverno`;
- a contract package importing a runtime, adapter, or Flutter UI package;
- a pure runtime importing an application provider, storage implementation, or
  platform implementation;
- one internal package importing another package's `lib/src/` files;
- a component manifest naming a Dart class, source file, native library, shell
  command, or unregistered executable path;
- a bundle overriding a member's capability or permission declaration.

The package graph must remain acyclic. Cross-feature cycles are resolved by
extracting the smallest shared contract toward the bottom of the graph, not by
creating a larger package around both features.

## Package Profiles

Every internal package declares one profile in
`tool/internal_package_catalog.json`. The catalog is the source of truth for
package ownership, purpose, consumers, public libraries, verification routing,
and optional code generation instead of hard-coding rules for individual
packages.

### `pure_dart`

Use for value types, parsers, deterministic policies, state machines, and ports
that do not require operating-system access.

Allowed:

- Dart core libraries such as `dart:async`, `dart:collection`, and
  `dart:convert`
- platform-neutral Dart dependencies
- generators used only during development

Forbidden:

- `dart:io`, `dart:ffi`, `dart:html`, and `dart:ui`
- Flutter, Riverpod, persistence plugins, and platform plugins
- root application imports

### `dart_io`

Use for reusable filesystem, process, socket, or transport implementations that
do not require Flutter.

Allowed:

- `dart:io`
- platform-neutral Dart protocol and storage dependencies approved by policy
- lower-level contract and pure runtime packages

Forbidden:

- Flutter and Riverpod
- Flutter platform plugins
- presentation and root application imports

This profile does not authorize arbitrary process or script execution. Such
behavior still requires an explicit Caverno capability, approval policy, and
audit path.

### `flutter_ui`

Use only for stable, reusable Flutter presentation surfaces with injected
ports. It may depend on Flutter and lower-level contracts or runtimes.

It must not own application navigation, global provider assembly, root storage,
or direct platform-plugin orchestration. A feature page should remain app-local
until those responsibilities are separated.

### `platform_adapter`

Use for a precompiled implementation of a stable port that requires a Flutter
plugin, FFI, or platform channel. It may depend on its contract and the minimum
required platform dependency. It must not contain product workflow policy,
global application state, or presentation composition.

### Common Package Rules

All profiles require:

- `publish_to: none` unless publication is approved separately;
- an explicit SDK constraint compatible with the workspace;
- a public barrel library that exposes only supported API;
- package-owned unit tests;
- no relative import that escapes the package's `lib/` directory;
- no direct import of another package's private `src/` implementation;
- no dependency cycle;
- a documented owner, purpose, profile, and consumers in the package catalog;
- repository verification before root application tests.

The Pub workspace lists members explicitly while the repository SDK constraint
remains below the version that supports workspace package globs.

## Registry And Core Pack

### Static Registry

The application owns a static registry assembled at build time. Each entry maps
a stable identifier to a typed descriptor and a precompiled implementation.
Descriptors include the component kind, input and output schema, required
capabilities, supported platforms, compatibility range, and resource limits.

The registry must not use reflection, source-file paths, class names supplied by
a manifest, or runtime code loading. Duplicate identifiers are build or install
errors rather than silent overrides.

Initial registry families may include:

- Tool screen components and actions
- workflow step types
- prompt and policy preset slots
- external adapter capabilities
- validators and deterministic transforms

### Core Pack

The core pack is the set of Caverno-authored manifests, templates, workflows,
presets, and assets bundled with the application. It provides an offline-safe
baseline and is versioned with the application release.

Built-in content is trusted as a shipped artifact, but it still passes schema
and compatibility validation. This keeps validation behavior representative of
future locally installed or curated content and prevents built-ins from relying
on undocumented exceptions.

The first registry implementation will support only the core pack. The package
foundation does not add a component registry or installable-component runtime.
Possible future sources are project-local, user-local, and curated remote
catalogs. Source priority, identifier conflicts, and trust transitions must be
explicit before any source is enabled. A lower-trust source must never shadow a
core identifier silently.

## Component Manifest Contract

The exact serialization format is deferred to the feature that implements the
registry, but every component manifest must carry equivalent fields:

```yaml
schemaVersion: 1.0.0
id: caverno.example.component
version: 1.0.0
kind: workflow
metadata:
  name: Example Component
  description: Example declarative workflow
compatibility:
  caverno: ">=1.4.0 <2.0.0"
  platforms: [macos, windows, linux]
provides: []
requires: []
capabilities: []
permissions: []
entrypoints: []
assets: []
configurationSchema: {}
provenance:
  source: bundled
  license: internal
  contentDigest: sha256:...
```

Rules:

- `schemaVersion` versions the manifest grammar independently from the
  component's `version`.
- `id` is globally stable and cannot be reassigned to a different publisher or
  purpose.
- compatibility is evaluated before activation, not after execution fails.
- `provides` and `requires` resolve through typed identifiers and compatible
  version ranges.
- capabilities and permissions are requests, never grants.
- entrypoints refer only to registered static identifiers.
- every asset has a normalized relative path, media type, size, and digest.
- provenance is retained through installation, updates, exports, audit events,
  and bundle resolution.

## Installation, Updates, And Rollback

Component lifecycle operations are transactional:

```text
discover -> stage -> validate -> review -> install -> activate
                                      |             |
                                      v             v
                                    reject       rollback
```

An update must:

1. download or copy into a staging area;
2. validate archive paths, size limits, manifest schema, references, content
   digests, compatibility, and declared capabilities;
3. resolve dependencies without changing the active installation;
4. present new permissions or data-egress behavior for review;
5. write the new version atomically;
6. activate it only after all checks pass; and
7. retain the previous known-good version and lock record for rollback.

A failed update leaves the active version unchanged. Rollback restores the
previous component selection and configuration. User data migration is a
separate, explicit operation and must not be hidden inside activation or
rollback. Removing a component must never delete user data without a distinct
user choice.

Bundles resolve to exact component versions and digests. Updating a bundle
creates a new lock record rather than mutating the prior record in place.

## Security And Trust

Spec Kit's packaging concepts are useful, but Caverno cannot adopt a
trust-only extension model because it can access files, processes, networks,
remote systems, and Computer Use surfaces.

The component boundary must enforce these rules:

- data-only manifests and assets; no dynamically loaded executable code;
- fail closed for unknown fields that affect execution, capabilities,
  permissions, entrypoints, or compatibility;
- normalized, root-contained asset paths and archive traversal protection;
- size, count, depth, storage, execution-time, and output limits;
- content digests for every installed artifact and lock record;
- source, author or publisher, license, installation time, and review provenance;
- signatures for any future remote catalog, with unsigned content kept local
  and explicitly untrusted until a signing policy exists;
- capability checks at validation time and again at action execution time;
- existing approval, risk classification, untrusted-influence, data-perimeter,
  and audit policies remain authoritative;
- installing a manifest never creates an approval grant;
- prompts, retrieved text, OCR, and external tool results remain untrusted data
  and cannot redefine policy or registry entries;
- secrets are references to Caverno-owned credential storage, never embedded in
  manifests, bundles, logs, or exported packs.

An MCP or stdio adapter remains governed by its configured trust and approval
policy. A component's provenance does not raise the trust level of an external
server or its results.

## Relationship To Existing Plans

### Tools MVP Roadmap

`docs/tools_mvp_roadmap.md` owns the product behavior and domain schema for
user-created Tools: screens, collections, actions, permissions, records,
provenance, storage, rendering, and confirmation.

This document owns the repository-wide packaging topology, common registry
contract, core-pack lifecycle, dependency rules, and future bundle mechanism.
The Tools runtime should consume that shared infrastructure rather than create a
parallel package manager or capability registry. A Tool manifest remains a
domain-specific document inside a component pack; the generic component
manifest does not replace its Tool schema.

The TOOL0 through TOOL7 order remains unchanged. TOOL1 is the earliest point at
which the generic registry and manifest infrastructure should be integrated.
Remote component distribution remains outside the Tools MVP.

### Local LLM Agent Roadmap

The packaging work advances the existing F5 one-way package-boundary goal. It
does not create another agent loop, workflow state machine, approval model, or
tool execution path. Future workflow and Tool components must delegate to the
existing orchestration and policy services through stable contracts.

### Large-File Refactor Plan

`docs/large_file_refactor_plan.md` remains authoritative for behavior-preserving
source decomposition. Package extraction is one possible result of that work,
not a line-count tactic. The existing `caverno_execution_runtime` package is the
reference implementation for one-way ownership and multi-frontend reuse.

Large Flutter surfaces and composition-heavy services continue to be decomposed
in place until they satisfy the migration criteria below.

## Package Migration Criteria

A candidate may move into an internal package only when all required criteria
are demonstrated:

1. **Stable responsibility:** the candidate has one coherent purpose and a
   public API that can be described without application implementation details.
2. **Real reuse:** it has at least two current consumers or a committed second
   frontend such as GUI and terminal. Speculative reuse is insufficient.
3. **Acyclic direction:** all required dependencies point toward lower-level
   packages; no root application import or callback into application state is
   needed.
4. **Profile fit:** every dependency is allowed by one package profile. If not,
   ports must be extracted before migration.
5. **Independent verification:** behavior can be tested without bootstrapping
   the full Flutter application.
6. **Ownership clarity:** entities, serialization, errors, and lifecycle belong
   to the candidate rather than being copied across root and package.
7. **Migration safety:** existing public behavior, persisted data, session-log
   schemas, tool identifiers, and frontend behavior remain unchanged unless a
   separate migration is approved.
8. **Reviewable size:** the move is one focused slice with direct tests and no
   unrelated cleanup.

A candidate stays app-local when it owns navigation, global Riverpod assembly,
multiple persistence implementations, platform orchestration, or bidirectional
feature dependencies. Ports and contracts should be extracted first.

## Completed Pilot: `caverno_content_protocol`

The first package pilot moved the existing LLM content parsing contract from
`lib/core/utils/content_parser.dart` into
`packages/caverno_content_protocol`.

### Why This Pilot

- It is pure Dart and currently depends only on `dart:convert`.
- It already has consumers in chat, routines, settings diagnostics, and
  presentation rendering.
- It has an extensive direct test suite.
- Its public data types and parser operations form a small coherent API.
- It exercises workspace, boundary-policy, test-ownership, and import-migration
  changes without changing tool execution or persistence.

### Intended Public API

The package exposes one public library:
`package:caverno_content_protocol/caverno_content_protocol.dart`. It contains
the supported parser contract:

- `ContentParser`
- `ContentType`
- `ToolCallData`
- `ContentSegment`
- `ParseResult`

Parser implementation helpers remain private. The package owns the exhaustive
parser unit tests. Root tests may retain only integration assertions that test a
root consumer rather than duplicating parser behavior.

### Pilot Acceptance Criteria

- the package is a `pure_dart` Pub workspace member;
- the root application imports only its public library;
- no compatibility re-export remains unless a measured migration requires one;
- all existing parsing fixtures and edge cases pass unchanged;
- chat, routines, settings diagnostics, and UI rendering compile against the
  package type identities;
- the generic architecture test verifies the package profile and dependency
  direction;
- repository verification resolves, analyzes, and tests the package before the
  root suite;
- GUI behavior, terminal behavior, persisted data, and session-log schemas do
  not change.

After the pilot, the next candidates should be evaluated from the measured
dependency graph rather than pre-approved. Likely candidates are tool contracts,
LLM contracts, and workflow-core policies, in that order, after their root
dependencies are removed.

### Pilot Result (2026-07-20)

- `caverno_content_protocol` is an explicit Pub workspace member and all 12
  direct production consumers use its public library.
- The package passed clean analysis and all 30 parser contract tests without a
  compatibility re-export from the former root path.
- The generic package boundary gate passed all 8 tests, and the focused root
  consumer gate passed all 107 tests.
- The full repository verification gate completed successfully. Its merged
  LCOV report covers 55,547 of 74,181 lines (74.88%), including both internal
  packages.
- The next package candidate was re-measured rather than pre-approved, producing
  the `caverno_tool_contracts` extraction described below.

## Completed Package: `caverno_tool_contracts`

The second extraction moves shared approval and capability contracts out of
application settings and chat implementation paths. It owns the approval mode,
approval gate decisions, capability classes, risk tiers, command effects, and
the pure classifier. Approval UI, auto-review orchestration, audit logging,
taint policy, routines, and platform policy remain application-owned.

Verified result (2026-07-20):

- the package is a dependency-free `pure_dart` workspace member;
- security, chat, settings, tests, and live canaries use its public library;
- persisted approval mode names and generated JSON enum maps are unchanged;
- all 24 direct package tests and 421 focused root compatibility tests passed;
- the full root suite passed all 3,906 tests; and
- merged line coverage is 74.94% (55,743 of 74,383 lines), including 98.76%
  coverage for the new package.

## Delivery Sequence

1. **Completed:** Land the architecture contract.
2. **Completed:** Establish the explicit Pub workspace and machine-readable
   package catalog.
3. **Completed:** Generalize architecture tests, verification routing, optional
   package code generation, and merged coverage.
4. **Completed:** Extract `caverno_content_protocol` without behavior changes.
5. **Completed:** Re-measure package dependencies and extract the approved
   `caverno_tool_contracts` boundary.
6. **Next:** Add the static component registry and bundled core-pack format
   with TOOL1.
7. Consider curated catalogs, bundles, and signed distribution only after the
   local manifest runtime and security gates are proven.

Each step should be independently reviewable and committed separately.

## Non-Goals

- publishing internal packages to pub.dev;
- creating one package per feature, widget, provider, handler, or large file;
- moving `ChatNotifier`, `ChatPage`, `MessageInput`, or `McpToolService`
  wholesale into packages;
- changing content parsing behavior during the pilot;
- redesigning Tool, workflow, approval, or persistence semantics;
- loading downloaded Dart, Flutter, native, JavaScript, SQL, or shell code;
- adding a plugin marketplace or remote catalog in the initial implementation;
- granting permissions through installation or bundle membership;
- replacing MCP, the approval system, the data-perimeter model, or audit logs;
- promising a stable third-party plugin ABI before the internal contracts have
  survived multiple application consumers and migrations.
