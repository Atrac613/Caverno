import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as path;

const String defaultDecompositionManifestPath =
    'tool/chat_notifier_decomposition_manifest.json';

const Set<String> allowedDecompositionStatuses = {
  'remaining',
  'partial',
  'extracted',
  'keep',
  'deferred',
};

const Set<String> activePartStatuses = {
  'remaining',
  'partial',
  'keep',
  'deferred',
};

const Set<String> collaboratorStatuses = {'partial', 'extracted'};

const Set<String> turnIdentityParameterNames = {
  'interactionGeneration',
  'generation',
};

const Set<String> turnScopedAccessorNames = {
  '_activeResponseMessagesForGeneration',
  '_isActiveResponseDetached',
  '_activeResponseConversationIdForGeneration',
  '_conversationForId',
  '_codingProjectForTurn',
  'TurnThread',
  'TurnGeneration',
  'TurnProjectRoot',
  '_threadStates',
  '_cacheActiveResponseMessagesForGeneration',
  'ThreadScopedChatState',
};

const List<String> ambientReadKinds = [
  'state.messages',
  'currentConversation',
  'effectiveCodingProject',
  'activeProjectRootPath',
];

final class AuditException implements Exception {
  const AuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DecompositionCollaborator {
  const DecompositionCollaborator({
    required this.id,
    required this.path,
    required this.sizeBudgetKey,
  });

  final String id;
  final String path;
  final String sizeBudgetKey;

  factory DecompositionCollaborator.fromJson(
    Object? value, {
    required String context,
  }) {
    final map = _requireStringKeyedMap(value, context);
    return DecompositionCollaborator(
      id: _requireNonEmptyString(map['id'], '$context.id'),
      path: _requireNonEmptyString(map['path'], '$context.path'),
      sizeBudgetKey: _requireNonEmptyString(
        map['sizeBudgetKey'],
        '$context.sizeBudgetKey',
      ),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'path': path,
    'sizeBudgetKey': sizeBudgetKey,
  };
}

final class DecompositionPart {
  const DecompositionPart({
    required this.id,
    required this.partPath,
    required this.entrypoints,
    required this.status,
    required this.collaborators,
  });

  final String id;
  final String partPath;
  final List<String> entrypoints;
  final String status;
  final List<DecompositionCollaborator> collaborators;

  factory DecompositionPart.fromJson(Object? value, {required int index}) {
    final context = 'parts[$index]';
    final map = _requireStringKeyedMap(value, context);
    final status = _requireNonEmptyString(map['status'], '$context.status');
    if (!allowedDecompositionStatuses.contains(status)) {
      throw AuditException(
        '$context.status must be one of '
        '${allowedDecompositionStatuses.toList()..sort()}; got "$status"',
      );
    }
    return DecompositionPart(
      id: _requireNonEmptyString(map['id'], '$context.id'),
      partPath: _requireNonEmptyString(map['partPath'], '$context.partPath'),
      entrypoints: _requireUniqueStrings(
        map['entrypoints'],
        '$context.entrypoints',
      ),
      status: status,
      collaborators:
          _requireList(map['collaborators'], '$context.collaborators').indexed
              .map(
                (entry) => DecompositionCollaborator.fromJson(
                  entry.$2,
                  context: '$context.collaborators[${entry.$1}]',
                ),
              )
              .toList(growable: false),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'partPath': partPath,
    'entrypoints': entrypoints,
    'status': status,
    'collaborators': collaborators
        .map((collaborator) => collaborator.toJson())
        .toList(growable: false),
  };
}

final class ChatNotifierDecompositionManifest {
  const ChatNotifierDecompositionManifest({
    required this.schemaName,
    required this.schemaVersion,
    required this.baselineRevision,
    required this.notifierLibraryPath,
    required this.entrypointSemantics,
    required this.parts,
  });

  final String schemaName;
  final int schemaVersion;
  final String baselineRevision;
  final String notifierLibraryPath;
  final String entrypointSemantics;
  final List<DecompositionPart> parts;

  factory ChatNotifierDecompositionManifest.decode(
    String source, {
    int? expectedPartCount,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw AuditException('Manifest is not valid JSON: ${error.message}');
    }
    final map = _requireStringKeyedMap(decoded, 'manifest');
    final schemaName = _requireNonEmptyString(
      map['schemaName'],
      'manifest.schemaName',
    );
    if (schemaName != 'caverno_chat_notifier_decomposition_manifest') {
      throw AuditException('Unsupported manifest schemaName "$schemaName"');
    }
    final schemaVersion = map['schemaVersion'];
    if (schemaVersion != 1) {
      throw AuditException(
        'Unsupported manifest schemaVersion "$schemaVersion"',
      );
    }
    final parts = _requireList(map['parts'], 'manifest.parts').indexed
        .map((entry) => DecompositionPart.fromJson(entry.$2, index: entry.$1))
        .toList(growable: false);
    if (expectedPartCount != null && parts.length != expectedPartCount) {
      throw AuditException(
        'Manifest must contain $expectedPartCount parts; got ${parts.length}',
      );
    }
    _requireUniqueValues(parts.map((part) => part.id), 'part ids');
    _requireUniqueValues(parts.map((part) => part.partPath), 'part paths');
    final collaborators = parts.expand((part) => part.collaborators).toList();
    _requireUniqueValues(
      collaborators.map((collaborator) => collaborator.id),
      'collaborator ids',
    );
    _requireUniqueValues(
      collaborators.map((collaborator) => collaborator.path),
      'collaborator paths',
    );
    for (final part in parts) {
      if (!collaboratorStatuses.contains(part.status) &&
          part.collaborators.isNotEmpty) {
        throw AuditException(
          '${part.partPath} has collaborators while status is ${part.status}',
        );
      }
      if (part.status == 'extracted' && part.collaborators.isEmpty) {
        throw AuditException(
          '${part.partPath} is extracted but has no collaborator',
        );
      }
    }
    return ChatNotifierDecompositionManifest(
      schemaName: schemaName,
      schemaVersion: schemaVersion as int,
      baselineRevision: _requireNonEmptyString(
        map['baselineRevision'],
        'manifest.baselineRevision',
      ),
      notifierLibraryPath: _requireNonEmptyString(
        map['notifierLibraryPath'],
        'manifest.notifierLibraryPath',
      ),
      entrypointSemantics: _requireNonEmptyString(
        map['entrypointSemantics'],
        'manifest.entrypointSemantics',
      ),
      parts: parts,
    );
  }

  factory ChatNotifierDecompositionManifest.load(
    File file, {
    int? expectedPartCount,
  }) {
    if (!file.existsSync()) {
      throw AuditException('Manifest does not exist: ${file.path}');
    }
    return ChatNotifierDecompositionManifest.decode(
      file.readAsStringSync(),
      expectedPartCount: expectedPartCount,
    );
  }

  Map<String, Object> toJson() => {
    'schemaName': schemaName,
    'schemaVersion': schemaVersion,
    'baselineRevision': baselineRevision,
    'notifierLibraryPath': notifierLibraryPath,
    'entrypointSemantics': entrypointSemantics,
    'parts': parts.map((part) => part.toJson()).toList(growable: false),
  };
}

final class HistoricalPartInventory {
  const HistoricalPartInventory({
    required this.partPath,
    required this.entrypoints,
  });

  final String partPath;
  final List<String> entrypoints;

  Map<String, Object> toJson() => {
    'partPath': partPath,
    'entrypoints': entrypoints,
  };
}

typedef OriginSourceLoader =
    String Function(String revision, String sourcePath);

List<HistoricalPartInventory> readHistoricalPartInventory({
  required String revision,
  required String notifierLibraryPath,
  required OriginSourceLoader loadSource,
}) {
  final mainSource = loadSource(revision, notifierLibraryPath);
  final mainUnit = _parseUnit(mainSource, notifierLibraryPath);
  final parent = path.posix.dirname(notifierLibraryPath);
  final inventory = <HistoricalPartInventory>[];
  for (final directive in mainUnit.directives.whereType<PartDirective>()) {
    final partPath = directive.uri.stringValue;
    if (partPath == null || !partPath.startsWith('chat_notifier_')) {
      continue;
    }
    final fullPath = path.posix.join(parent, partPath);
    final partSource = loadSource(revision, fullPath);
    inventory.add(
      HistoricalPartInventory(
        partPath: partPath,
        entrypoints: _chatNotifierExtensionEntrypoints(
          _parseUnit(partSource, fullPath),
        ),
      ),
    );
  }
  return inventory;
}

void verifyManifestAgainstOrigin({
  required ChatNotifierDecompositionManifest manifest,
  required String revision,
  required OriginSourceLoader loadSource,
}) {
  final inventory = readHistoricalPartInventory(
    revision: revision,
    notifierLibraryPath: manifest.notifierLibraryPath,
    loadSource: loadSource,
  );
  final actualPaths = inventory.map((part) => part.partPath).toList();
  final expectedPaths = manifest.parts.map((part) => part.partPath).toList();
  if (!_listEquals(actualPaths, expectedPaths)) {
    throw AuditException(
      'Historical part paths do not match the manifest.\n'
      'origin: ${jsonEncode(actualPaths)}\n'
      'manifest: ${jsonEncode(expectedPaths)}',
    );
  }
  for (var index = 0; index < inventory.length; index += 1) {
    final actual = inventory[index];
    final expected = manifest.parts[index];
    if (!_listEquals(actual.entrypoints, expected.entrypoints)) {
      throw AuditException(
        'Historical entrypoints do not match for ${actual.partPath}.\n'
        'origin: ${jsonEncode(actual.entrypoints)}\n'
        'manifest: ${jsonEncode(expected.entrypoints)}',
      );
    }
  }
}

final class TurnScopeAuditReport {
  const TurnScopeAuditReport(this.data);

  final Map<String, Object> data;

  String encode() => '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}

TurnScopeAuditReport auditChatNotifierTurnScope({
  required Directory root,
  required ChatNotifierDecompositionManifest manifest,
  String manifestPath = defaultDecompositionManifestPath,
}) {
  final notifierFile = File(path.join(root.path, manifest.notifierLibraryPath));
  if (!notifierFile.existsSync()) {
    throw AuditException(
      'Notifier library does not exist: ${manifest.notifierLibraryPath}',
    );
  }
  final notifierSource = notifierFile.readAsStringSync();
  final notifierUnit = _parseUnit(notifierSource, manifest.notifierLibraryPath);
  final declaredParts = notifierUnit.directives
      .whereType<PartDirective>()
      .map((directive) => directive.uri.stringValue)
      .whereType<String>()
      .where((partPath) => partPath.startsWith('chat_notifier_'))
      .toList(growable: false);
  final activeParts = manifest.parts
      .where((part) => activePartStatuses.contains(part.status))
      .toList(growable: false);
  final expectedParts = activeParts
      .map((part) => part.partPath)
      .toList(growable: false);
  if (!_unorderedEquals(declaredParts, expectedParts)) {
    throw AuditException(
      'Current notifier part directives do not match active manifest parts.\n'
      'declared: ${jsonEncode(declaredParts..sort())}\n'
      'expected: ${jsonEncode(expectedParts..sort())}',
    );
  }

  final sourceByPath = <String, String>{
    manifest.notifierLibraryPath: notifierSource,
  };
  final providerDirectory = path.posix.dirname(manifest.notifierLibraryPath);
  for (final part in activeParts) {
    final sourcePath = path.posix.join(providerDirectory, part.partPath);
    sourceByPath[sourcePath] = _readRequiredSource(root, sourcePath);
  }
  final expectedCollaborators = manifest.parts
      .where((part) => collaboratorStatuses.contains(part.status))
      .expand((part) => part.collaborators)
      .toList(growable: false);
  for (final collaborator in expectedCollaborators) {
    final source = _readRequiredSource(root, collaborator.path);
    final marker =
        '// ChatNotifier decomposition collaborator: ${collaborator.id}';
    if (!source.split('\n').any((line) => line.trim() == marker)) {
      throw AuditException(
        'Missing collaborator marker "$marker" in ${collaborator.path}',
      );
    }
    sourceByPath[collaborator.path] = source;
  }

  final manifestEntrypoints = <String, Set<String>>{
    for (final part in activeParts)
      path.posix.join(providerDirectory, part.partPath): part.entrypoints
          .toSet(),
  };
  final methods = <_MethodAudit>[];
  for (final sourcePath in sourceByPath.keys.toList()..sort()) {
    methods.addAll(
      _scanMethods(
        sourcePath: sourcePath,
        source: sourceByPath[sourcePath]!,
        notifierLibraryPath: manifest.notifierLibraryPath,
        manifestEntrypoints: manifestEntrypoints[sourcePath] ?? const {},
      ),
    );
  }
  methods.sort(_compareMethods);
  _classifyReachability(methods);

  final reads = methods.expand((method) => method.reads).toList()
    ..sort(_compareReads);
  final scannedPaths = sourceByPath.keys.toList()..sort();
  final report = <String, Object>{
    'schemaName': 'caverno_chat_notifier_turn_scope_audit',
    'schemaVersion': 1,
    'source': 'working-tree',
    'manifestPath': path.posix.normalize(manifestPath),
    'notifierLibraryPath': manifest.notifierLibraryPath,
    'scannedPaths': scannedPaths,
    'entrypoints': [
      for (final part in activeParts)
        {'partPath': part.partPath, 'declarations': part.entrypoints},
    ],
    'assumptions': {
      'entrypointSemantics': manifest.entrypointSemantics,
      'callGraph':
          'Historical part entrypoints and public ChatNotifier methods are '
          'roots. A method invocation links only when its name identifies one '
          'scanned declaration uniquely.',
      'turnIdentity':
          'A declaration is turn-aware when its complete AST parameter list '
          'contains interactionGeneration, generation, ChatTurnOwner, or a '
          'Conversation type.',
      'ambientReads': {
        'state.messages': 'AST prefixed identifier state.messages',
        'currentConversation':
            'AST property access with name currentConversation',
        'effectiveCodingProject': 'AST invocation _getEffectiveCodingProject()',
        'activeProjectRootPath': 'AST invocation _getActiveProjectRootPath()',
      },
      'turnScopedAccessors': turnScopedAccessorNames.toList()..sort(),
      'occurrenceIdentity':
          'file::declaration::read-kind#one-based-source-order-index; line and '
          'column are diagnostics only',
      'baselineComparison':
          'The baseline comparison ignores diagnostic line and column values '
          'but compares every stable method and read field.',
    },
    'summary': {
      'scannedFiles': scannedPaths.length,
      'methods': methods.length,
      'manifestEntrypoints': methods
          .where((method) => method.entrypoint)
          .length,
      'reachableMethods': methods.where((method) => method.reachable).length,
      'ambientReads': reads.length,
      'methodsWithAmbientReads': methods
          .where((method) => method.reads.isNotEmpty)
          .length,
      'methodTurnIdentityReads': reads
          .where((read) => read.methodHasTurnIdentity)
          .length,
      'turnReachableReads': reads.where((read) => read.turnReachable).length,
      'accessorBearingReads': reads
          .where((read) => read.accessorBearing)
          .length,
    },
    'methods': methods.map((method) => method.toJson()).toList(growable: false),
    'reads': reads.map((read) => read.toJson()).toList(growable: false),
  };
  return TurnScopeAuditReport(report);
}

void checkBaseline(TurnScopeAuditReport report, File baseline) {
  if (!baseline.existsSync()) {
    throw AuditException('Baseline does not exist: ${baseline.path}');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(baseline.readAsStringSync());
  } on FormatException catch (error) {
    throw AuditException('Baseline is not valid JSON: ${error.message}');
  }
  final expected = _stableBaselineProjection(
    _requireStringKeyedMap(decoded, 'baseline'),
  );
  final actual = _stableBaselineProjection(report.data);
  if (jsonEncode(expected) != jsonEncode(actual)) {
    throw AuditException(
      'Turn-scope audit differs from ${baseline.path}. '
      'Review the report, then regenerate explicitly with --write-baseline.',
    );
  }
}

void writeBaseline(TurnScopeAuditReport report, File baseline) {
  baseline.parent.createSync(recursive: true);
  baseline.writeAsStringSync(report.encode());
}

void validateProgramManifest(ChatNotifierDecompositionManifest manifest) {
  if (manifest.parts.length != 43) {
    throw AuditException(
      'Program manifest must contain 43 historical parts; '
      'got ${manifest.parts.length}',
    );
  }
  // `chat_notifier_execution_runtime.dart` left this set on 2026-08-04. It was
  // the one part the destructor slice touched: the turn's eleven owner-scoped
  // releases moved out of `_terminalizeRuntimeTurn` into a `TurnReleaseScope`
  // the turn owns, so the part is partially extracted and `keep` is no longer
  // the true status. Nothing else moved, and the authorization covers one
  // slice; see `docs/chat_notifier_renewal_question_six_review.md`.
  const expectedKeepParts = {
    'chat_notifier_response_finalization.dart',
    'chat_notifier_error_handling.dart',
    'chat_notifier_turn_exit.dart',
    'chat_notifier_cancellation.dart',
  };
  const expectedDeferredParts = {
    'chat_notifier_proposal_parsing.dart',
    'chat_notifier_proposal_option_extraction.dart',
    'chat_notifier_workflow_proposal_parser.dart',
    'chat_notifier_task_proposal_quality.dart',
    'chat_notifier_terminal_tool_response_policy.dart',
    'chat_notifier_task_proposal_parser.dart',
  };
  final keepParts = manifest.parts
      .where((part) => part.status == 'keep')
      .map((part) => part.partPath)
      .toSet();
  final deferredParts = manifest.parts
      .where((part) => part.status == 'deferred')
      .map((part) => part.partPath)
      .toSet();
  if (!_setEquals(keepParts, expectedKeepParts)) {
    throw AuditException(
      'Program manifest keep records changed without an approved prerequisite',
    );
  }
  if (!_setEquals(deferredParts, expectedDeferredParts)) {
    throw AuditException(
      'Program manifest deferred records changed without an approved '
      'prerequisite',
    );
  }
}

Future<int> runAuditCli(
  List<String> arguments, {
  Directory? workingDirectory,
  StringSink? stdoutSink,
  StringSink? stderrSink,
  OriginSourceLoader? originSourceLoader,
  int? expectedPartCount = 43,
  bool enforceProgramManifest = true,
}) async {
  final root = workingDirectory ?? Directory.current;
  final output = stdoutSink ?? stdout;
  final errors = stderrSink ?? stderr;
  try {
    final options = _AuditCliOptions.parse(arguments);
    final manifestFile = File(path.join(root.path, options.manifestPath));
    final manifest = ChatNotifierDecompositionManifest.load(
      manifestFile,
      expectedPartCount: expectedPartCount,
    );
    if (enforceProgramManifest) {
      validateProgramManifest(manifest);
    }
    final loader =
        originSourceLoader ??
        (revision, sourcePath) => _loadGitSource(
          root: root,
          revision: revision,
          sourcePath: sourcePath,
        );
    if (options.describeOrigin != null) {
      final inventory = readHistoricalPartInventory(
        revision: options.describeOrigin!,
        notifierLibraryPath: manifest.notifierLibraryPath,
        loadSource: loader,
      );
      output.write(
        '${const JsonEncoder.withIndent('  ').convert({'revision': options.describeOrigin!, 'parts': inventory.map((part) => part.toJson()).toList()})}\n',
      );
      return 0;
    }
    if (options.verifyOrigin != null) {
      verifyManifestAgainstOrigin(
        manifest: manifest,
        revision: options.verifyOrigin!,
        loadSource: loader,
      );
    }
    final report = auditChatNotifierTurnScope(
      root: root,
      manifest: manifest,
      manifestPath: options.manifestPath,
    );
    if (options.checkBaseline != null) {
      checkBaseline(report, File(path.join(root.path, options.checkBaseline!)));
    }
    if (options.writeBaseline != null) {
      writeBaseline(report, File(path.join(root.path, options.writeBaseline!)));
    }
    output.write(report.encode());
    return 0;
  } on AuditException catch (error) {
    errors.writeln(error.message);
    return 1;
  } on FileSystemException catch (error) {
    errors.writeln(error.message);
    return 1;
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await runAuditCli(arguments);
}

final class _AuditCliOptions {
  const _AuditCliOptions({
    required this.manifestPath,
    this.verifyOrigin,
    this.describeOrigin,
    this.checkBaseline,
    this.writeBaseline,
  });

  final String manifestPath;
  final String? verifyOrigin;
  final String? describeOrigin;
  final String? checkBaseline;
  final String? writeBaseline;

  factory _AuditCliOptions.parse(List<String> arguments) {
    var manifestPath = defaultDecompositionManifestPath;
    String? verifyOrigin;
    String? describeOrigin;
    String? checkBaseline;
    String? writeBaseline;
    for (var index = 0; index < arguments.length; index += 1) {
      final flag = arguments[index];
      if (!{
        '--manifest',
        '--verify-origin',
        '--describe-origin',
        '--check-baseline',
        '--write-baseline',
      }.contains(flag)) {
        throw AuditException('Unknown argument: $flag');
      }
      if (index + 1 >= arguments.length) {
        throw AuditException('$flag requires a value');
      }
      final value = arguments[index += 1];
      switch (flag) {
        case '--manifest':
          manifestPath = value;
        case '--verify-origin':
          verifyOrigin = value;
        case '--describe-origin':
          describeOrigin = value;
        case '--check-baseline':
          checkBaseline = value;
        case '--write-baseline':
          writeBaseline = value;
      }
    }
    if (checkBaseline != null && writeBaseline != null) {
      throw const AuditException(
        '--check-baseline and --write-baseline are mutually exclusive',
      );
    }
    if (describeOrigin != null &&
        (verifyOrigin != null ||
            checkBaseline != null ||
            writeBaseline != null)) {
      throw const AuditException(
        '--describe-origin cannot be combined with audit options',
      );
    }
    return _AuditCliOptions(
      manifestPath: manifestPath,
      verifyOrigin: verifyOrigin,
      describeOrigin: describeOrigin,
      checkBaseline: checkBaseline,
      writeBaseline: writeBaseline,
    );
  }
}

final class _MethodAudit {
  _MethodAudit({
    required this.path,
    required this.declaration,
    required this.name,
    required this.signature,
    required this.turnIdentityParameters,
    required this.turnScopedAccessors,
    required this.calls,
    required this.entrypoint,
    required this.publicNotifierMethod,
    required this.reads,
  });

  final String path;
  final String declaration;
  final String name;
  final String signature;
  final List<String> turnIdentityParameters;
  final List<String> turnScopedAccessors;
  final List<String> calls;
  final bool entrypoint;
  final bool publicNotifierMethod;
  final List<_ReadAudit> reads;
  bool reachable = false;
  bool turnReachable = false;

  Map<String, Object> toJson() => {
    'path': path,
    'declaration': declaration,
    'signature': signature,
    'turnIdentityParameters': turnIdentityParameters,
    'turnScopedAccessors': turnScopedAccessors,
    'calls': calls,
    'entrypoint': entrypoint,
    'reachable': reachable,
    'turnReachable': turnReachable,
  };
}

final class _ReadAudit {
  _ReadAudit({
    required this.path,
    required this.declaration,
    required this.kind,
    required this.offset,
    required this.line,
    required this.column,
    required this.occurrence,
    required this.methodHasTurnIdentity,
    required this.accessorBearing,
  });

  final String path;
  final String declaration;
  final String kind;
  final int offset;
  final int line;
  final int column;
  final int occurrence;
  final bool methodHasTurnIdentity;
  final bool accessorBearing;
  bool turnReachable = false;

  String get id => '$path::$declaration::$kind#$occurrence';

  Map<String, Object> toJson() => {
    'id': id,
    'path': path,
    'declaration': declaration,
    'kind': kind,
    'line': line,
    'column': column,
    'methodHasTurnIdentity': methodHasTurnIdentity,
    'turnReachable': turnReachable,
    'accessorBearing': accessorBearing,
  };
}

final class _AmbientOccurrence {
  const _AmbientOccurrence(this.kind, this.offset);

  final String kind;
  final int offset;
}

final class _BodyVisitor extends RecursiveAstVisitor<void> {
  final List<_AmbientOccurrence> occurrences = [];
  final Set<String> calls = {};
  final Set<String> identifiers = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    calls.add(name);
    identifiers.add(name);
    if (name == '_getEffectiveCodingProject') {
      occurrences.add(
        _AmbientOccurrence('effectiveCodingProject', node.offset),
      );
    } else if (name == '_getActiveProjectRootPath') {
      occurrences.add(_AmbientOccurrence('activeProjectRootPath', node.offset));
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.name;
    final identifier = node.identifier.name;
    identifiers
      ..add(prefix)
      ..add(identifier);
    if (prefix == 'state' && identifier == 'messages') {
      occurrences.add(_AmbientOccurrence('state.messages', node.offset));
    } else if (identifier == 'currentConversation') {
      occurrences.add(_AmbientOccurrence('currentConversation', node.offset));
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final identifier = node.propertyName.name;
    identifiers.add(identifier);
    if (identifier == 'currentConversation') {
      occurrences.add(_AmbientOccurrence('currentConversation', node.offset));
    }
    super.visitPropertyAccess(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    identifiers.add(node.name);
    super.visitSimpleIdentifier(node);
  }
}

List<_MethodAudit> _scanMethods({
  required String sourcePath,
  required String source,
  required String notifierLibraryPath,
  required Set<String> manifestEntrypoints,
}) {
  final result = parseString(
    content: source,
    path: sourcePath,
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    throw AuditException(
      'Unable to parse $sourcePath: '
      '${result.errors.map((error) => error.message).join('; ')}',
    );
  }
  final methods = <_MethodAudit>[];
  for (final declaration in result.unit.declarations) {
    if (declaration is ClassDeclaration) {
      final className = declaration.namePart.typeName.lexeme;
      final isNotifier = className == 'ChatNotifier';
      for (final member in _classMembers(
        declaration.body,
      ).whereType<MethodDeclaration>()) {
        methods.add(
          _scanMethod(
            sourcePath: sourcePath,
            source: source,
            lineInfo: result.lineInfo,
            declaration: member,
            label: isNotifier
                ? member.name.lexeme
                : '$className.${member.name.lexeme}',
            manifestEntrypoints: manifestEntrypoints,
            publicNotifierMethod:
                sourcePath == notifierLibraryPath &&
                isNotifier &&
                !member.name.lexeme.startsWith('_'),
          ),
        );
      }
    } else if (declaration is ExtensionDeclaration) {
      final onChatNotifier =
          declaration.onClause?.extendedType.toSource() == 'ChatNotifier';
      final extensionName = declaration.name?.lexeme ?? '<unnamed-extension>';
      for (final member
          in declaration.body.members.whereType<MethodDeclaration>()) {
        methods.add(
          _scanMethod(
            sourcePath: sourcePath,
            source: source,
            lineInfo: result.lineInfo,
            declaration: member,
            label: onChatNotifier
                ? member.name.lexeme
                : '$extensionName.${member.name.lexeme}',
            manifestEntrypoints: manifestEntrypoints,
            publicNotifierMethod: false,
          ),
        );
      }
    } else if (declaration is MixinDeclaration) {
      final mixinName = declaration.name.lexeme;
      for (final member
          in declaration.body.members.whereType<MethodDeclaration>()) {
        methods.add(
          _scanMethod(
            sourcePath: sourcePath,
            source: source,
            lineInfo: result.lineInfo,
            declaration: member,
            label: '$mixinName.${member.name.lexeme}',
            manifestEntrypoints: manifestEntrypoints,
            publicNotifierMethod: false,
          ),
        );
      }
    } else if (declaration is FunctionDeclaration) {
      methods.add(
        _scanFunction(
          sourcePath: sourcePath,
          source: source,
          lineInfo: result.lineInfo,
          declaration: declaration,
        ),
      );
    }
  }
  return methods;
}

Iterable<ClassMember> _classMembers(ClassBody body) {
  if (body is BlockClassBody) {
    return body.members;
  }
  return const <ClassMember>[];
}

_MethodAudit _scanMethod({
  required String sourcePath,
  required String source,
  required LineInfo lineInfo,
  required MethodDeclaration declaration,
  required String label,
  required Set<String> manifestEntrypoints,
  required bool publicNotifierMethod,
}) {
  return _buildMethodAudit(
    sourcePath: sourcePath,
    source: source,
    lineInfo: lineInfo,
    name: declaration.name.lexeme,
    label: label,
    offset: declaration.offset,
    body: declaration.body,
    parameters: declaration.parameters,
    entrypoint: manifestEntrypoints.contains(declaration.name.lexeme),
    publicNotifierMethod: publicNotifierMethod,
  );
}

_MethodAudit _scanFunction({
  required String sourcePath,
  required String source,
  required LineInfo lineInfo,
  required FunctionDeclaration declaration,
}) {
  return _buildMethodAudit(
    sourcePath: sourcePath,
    source: source,
    lineInfo: lineInfo,
    name: declaration.name.lexeme,
    label: declaration.name.lexeme,
    offset: declaration.offset,
    body: declaration.functionExpression.body,
    parameters: declaration.functionExpression.parameters,
    entrypoint: false,
    publicNotifierMethod: false,
  );
}

_MethodAudit _buildMethodAudit({
  required String sourcePath,
  required String source,
  required LineInfo lineInfo,
  required String name,
  required String label,
  required int offset,
  required FunctionBody body,
  required FormalParameterList? parameters,
  required bool entrypoint,
  required bool publicNotifierMethod,
}) {
  final parameterList = parameters?.parameters ?? const <FormalParameter>[];
  final turnParameters = parameterList
      .where((parameter) {
        final parameterName = parameter.name?.lexeme;
        return turnIdentityParameterNames.contains(parameterName) ||
            RegExp(
              r'\b(?:ChatTurnOwner|Conversation)\??\b',
            ).hasMatch(parameter.toSource());
      })
      .map((parameter) => parameter.toSource())
      .toList(growable: false);
  final visitor = _BodyVisitor();
  body.accept(visitor);
  visitor.occurrences.sort(
    (left, right) => left.offset.compareTo(right.offset),
  );
  final accessors =
      visitor.identifiers.where(turnScopedAccessorNames.contains).toList()
        ..sort();
  final occurrenceByKind = <String, int>{};
  final reads = <_ReadAudit>[];
  for (final occurrence in visitor.occurrences) {
    final occurrenceIndex = (occurrenceByKind[occurrence.kind] ?? 0) + 1;
    occurrenceByKind[occurrence.kind] = occurrenceIndex;
    final location = lineInfo.getLocation(occurrence.offset);
    reads.add(
      _ReadAudit(
        path: sourcePath,
        declaration: label,
        kind: occurrence.kind,
        offset: occurrence.offset,
        line: location.lineNumber,
        column: location.columnNumber,
        occurrence: occurrenceIndex,
        methodHasTurnIdentity: turnParameters.isNotEmpty,
        accessorBearing: accessors.isNotEmpty,
      ),
    );
  }
  return _MethodAudit(
    path: sourcePath,
    declaration: label,
    name: name,
    signature: source.substring(offset, body.offset).trim(),
    turnIdentityParameters: turnParameters,
    turnScopedAccessors: accessors,
    calls: visitor.calls.toList()..sort(),
    entrypoint: entrypoint,
    publicNotifierMethod: publicNotifierMethod,
    reads: reads,
  );
}

void _classifyReachability(List<_MethodAudit> methods) {
  final byName = <String, List<_MethodAudit>>{};
  for (final method in methods) {
    byName.putIfAbsent(method.name, () => []).add(method);
  }
  final roots = methods
      .where((method) => method.entrypoint || method.publicNotifierMethod)
      .toList();
  _walkGraph(
    roots: roots,
    byName: byName,
    mark: (method) => method.reachable = true,
    isMarked: (method) => method.reachable,
  );
  final turnRoots = methods
      .where((method) => method.turnIdentityParameters.isNotEmpty)
      .toList();
  _walkGraph(
    roots: turnRoots,
    byName: byName,
    mark: (method) {
      method.turnReachable = true;
      for (final read in method.reads) {
        read.turnReachable = true;
      }
    },
    isMarked: (method) => method.turnReachable,
  );
}

void _walkGraph({
  required List<_MethodAudit> roots,
  required Map<String, List<_MethodAudit>> byName,
  required void Function(_MethodAudit method) mark,
  required bool Function(_MethodAudit method) isMarked,
}) {
  final pending = [...roots];
  while (pending.isNotEmpty) {
    final method = pending.removeLast();
    if (isMarked(method)) {
      continue;
    }
    mark(method);
    for (final call in method.calls) {
      final candidates = byName[call];
      if (candidates != null && candidates.length == 1) {
        pending.add(candidates.single);
      }
    }
  }
}

List<String> _chatNotifierExtensionEntrypoints(CompilationUnit unit) {
  final result = <String>[];
  for (final declaration
      in unit.declarations.whereType<ExtensionDeclaration>()) {
    if (declaration.onClause?.extendedType.toSource() != 'ChatNotifier') {
      continue;
    }
    result.addAll(
      declaration.body.members.whereType<MethodDeclaration>().map(
        (method) => method.name.lexeme,
      ),
    );
  }
  return result;
}

CompilationUnit _parseUnit(String source, String sourcePath) {
  final result = parseString(
    content: source,
    path: sourcePath,
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    throw AuditException(
      'Unable to parse $sourcePath: '
      '${result.errors.map((error) => error.message).join('; ')}',
    );
  }
  return result.unit;
}

String _readRequiredSource(Directory root, String sourcePath) {
  final file = File(path.join(root.path, sourcePath));
  if (!file.existsSync()) {
    throw AuditException('Required source does not exist: $sourcePath');
  }
  return file.readAsStringSync();
}

String _loadGitSource({
  required Directory root,
  required String revision,
  required String sourcePath,
}) {
  final result = Process.runSync('git', [
    'show',
    '$revision:$sourcePath',
  ], workingDirectory: root.path);
  if (result.exitCode != 0) {
    throw AuditException(
      'Unable to read $sourcePath at $revision: ${result.stderr.toString().trim()}',
    );
  }
  return result.stdout as String;
}

Map<String, Object?> _requireStringKeyedMap(Object? value, String context) {
  if (value is! Map) {
    throw AuditException('$context must be an object');
  }
  if (value.keys.any((key) => key is! String)) {
    throw AuditException('$context must use string keys');
  }
  return value.cast<String, Object?>();
}

List<Object?> _requireList(Object? value, String context) {
  if (value is! List) {
    throw AuditException('$context must be an array');
  }
  return value.cast<Object?>();
}

List<String> _requireUniqueStrings(Object? value, String context) {
  final strings = _requireList(value, context)
      .map((entry) => _requireNonEmptyString(entry, context))
      .toList(growable: false);
  _requireUniqueValues(strings, context);
  return strings;
}

String _requireNonEmptyString(Object? value, String context) {
  if (value is! String || value.trim().isEmpty) {
    throw AuditException('$context must be a non-empty string');
  }
  return value;
}

void _requireUniqueValues(Iterable<String> values, String context) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      duplicates.add(value);
    }
  }
  if (duplicates.isNotEmpty) {
    throw AuditException(
      '$context must be unique; duplicates: ${duplicates.toList()..sort()}',
    );
  }
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _unorderedEquals(List<String> left, List<String> right) {
  final sortedLeft = [...left]..sort();
  final sortedRight = [...right]..sort();
  return _listEquals(sortedLeft, sortedRight);
}

bool _setEquals(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}

Map<String, Object?> _stableBaselineProjection(Map<String, Object?> report) {
  final copy = jsonDecode(jsonEncode(report)) as Map<String, dynamic>;
  final reads = copy['reads'];
  if (reads is List) {
    for (final read in reads.whereType<Map>()) {
      read
        ..remove('line')
        ..remove('column');
    }
  }
  return copy.cast<String, Object?>();
}

int _compareMethods(_MethodAudit left, _MethodAudit right) {
  final pathResult = left.path.compareTo(right.path);
  if (pathResult != 0) {
    return pathResult;
  }
  return left.declaration.compareTo(right.declaration);
}

int _compareReads(_ReadAudit left, _ReadAudit right) {
  final pathResult = left.path.compareTo(right.path);
  if (pathResult != 0) {
    return pathResult;
  }
  final declarationResult = left.declaration.compareTo(right.declaration);
  if (declarationResult != 0) {
    return declarationResult;
  }
  final kindResult = left.kind.compareTo(right.kind);
  if (kindResult != 0) {
    return kindResult;
  }
  return left.occurrence.compareTo(right.occurrence);
}
