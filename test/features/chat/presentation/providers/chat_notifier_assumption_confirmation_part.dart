part of 'chat_notifier_test.dart';

/// ANA0's confirm path, driven through the real notifier rather than scanned
/// for in the source.
///
/// The milestone canary asserts that *some* production file calls
/// `confirmMaterialAssumption`, which its own comment calls the weakest honest
/// proxy for reachability a source scan can express. These run the wiring: the
/// tool loop refuses, the confirmation is raised as a pending approval, the
/// answer is given by id the way the sheet gives it, and the same call is
/// re-evaluated against the spec that answer produced.
const _assumedConstraintText = 'Existing entities have stable UUIDs';

String _assumedConstraintItemId() =>
    const ConversationContractProvenanceService().itemId(
      kind: ConversationContractItemKind.constraint,
      value: _assumedConstraintText,
    );

ConversationWorkflowSpec _specWithMaterialAssumption() {
  return ConversationWorkflowSpec(
    goal: 'Add iCloud synchronization',
    constraints: const [_assumedConstraintText],
    provenance: [
      ConversationContractItemProvenance(
        itemId: _assumedConstraintItemId(),
        kind: ConversationContractItemKind.constraint,
        assumption: true,
        material: true,
        clarificationQuestion: 'Do existing entities have stable UUIDs?',
      ),
    ],
  );
}

Future<
  ({
    ProviderContainer container,
    ChatNotifier notifier,
    Future<ChatTurnOwner?> send,
  })
>
_startBlockedMutationTurn() async {
  final projectRoot = Directory.systemTemp.createTempSync('ana0_confirm_');
  addTearDown(() => projectRoot.deleteSync(recursive: true));
  final project = CodingProject(
    id: 'ana0-project',
    name: 'ANA0 Project',
    rootPath: projectRoot.path,
    createdAt: DateTime(2026, 9, 4),
    updatedAt: DateTime(2026, 9, 4),
  );
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);

  final dataSource = _QueuedToolLoopChatDataSource(
    initialToolCalls: [
      ToolCallInfo(
        id: 'write-engine',
        name: 'write_file',
        arguments: const {
          'path': 'lib/sync/engine.dart',
          'content': '// generated',
        },
      ),
    ],
    toolLoopResponses: [
      ChatCompletionResult(content: 'Done.', finishReason: 'stop'),
    ],
  );

  final container = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _FixedCodingProjectsNotifier(project),
      ),
      mcpToolServiceProvider.overrideWithValue(
        _FakeMcpToolService(results: const {'write_file': '{"ok":true}'}),
      ),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );
  addTearDown(container.dispose);

  final conversations = container.read(conversationsNotifierProvider.notifier);
  conversations.activateWorkspace(
    workspaceMode: WorkspaceMode.coding,
    projectId: project.id,
    createIfMissing: true,
  );
  await conversations.updateCurrentWorkflow(
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: _specWithMaterialAssumption(),
  );

  final notifier = container.read(chatNotifierProvider.notifier);
  final send = notifier.sendMessage(
    'Write the sync engine.',
    bypassPlanMode: true,
  );
  await _waitForCondition(
    () => notifier.state.pendingAssumptionConfirmation != null,
  );
  return (container: container, notifier: notifier, send: send);
}

ConversationContractItemProvenance _currentAssumption(
  ProviderContainer container,
) {
  final conversation = container
      .read(conversationsNotifierProvider.notifier)
      .state
      .conversationForId(null)!;
  return conversation.effectiveWorkflowSpec.provenance.singleWhere(
    (item) => item.itemId == _assumedConstraintItemId(),
  );
}

Future<
  ({
    ProviderContainer container,
    ChatNotifier notifier,
    Future<ChatTurnOwner?> send,
    _QueuedToolLoopChatDataSource dataSource,
  })
>
_startAddressedParentTurn() async {
  final projectRoot = Directory.systemTemp.createTempSync('ana_parent_');
  addTearDown(() => projectRoot.deleteSync(recursive: true));
  final project = CodingProject(
    id: 'ana-parent-project',
    name: 'Anabasis Parent',
    rootPath: projectRoot.path,
    createdAt: DateTime(2026, 9, 4),
    updatedAt: DateTime(2026, 9, 4),
  );
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);

  final dataSource = _QueuedToolLoopChatDataSource(
    initialToolCalls: [
      ToolCallInfo(
        id: 'write-engine',
        name: 'write_file',
        arguments: const {'path': 'lib/sync/engine.dart', 'content': '// x'},
      ),
    ],
    toolLoopResponses: [
      ChatCompletionResult(content: 'Understood.', finishReason: 'stop'),
    ],
  );

  final container = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _FixedCodingProjectsNotifier(project),
      ),
      mcpToolServiceProvider.overrideWithValue(
        _FakeMcpToolService(results: const {'write_file': '{"ok":true}'}),
      ),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );
  addTearDown(container.dispose);

  container
      .read(conversationsNotifierProvider.notifier)
      .activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
  final notifier = container.read(chatNotifierProvider.notifier);
  final send = notifier.sendMessage(
    '@anabasis write the sync engine',
    bypassPlanMode: true,
  );
  return (
    container: container,
    notifier: notifier,
    send: send,
    dataSource: dataSource,
  );
}

void registerChatNotifierAssumptionConfirmationTests() {
  test('a material assumption asks before the mutation runs', () async {
    final harness = await _startBlockedMutationTurn();
    final pending = harness.notifier.state.pendingAssumptionConfirmation!;

    expect(
      pending.itemText,
      _assumedConstraintText,
      reason:
          'The provenance record carries a hash. A sheet showing that instead '
          'of the claim asks the user to confirm something they cannot read.',
    );
    expect(
      pending.clarificationQuestion,
      'Do existing entities have stable UUIDs?',
    );
    expect(
      pending.toolName,
      'write_file',
      reason: 'The interruption has to say what it is holding up.',
    );

    harness.notifier.resolveAssumptionConfirmation(
      id: pending.id,
      confirmed: false,
    );
    final owner = await harness.send.timeout(const Duration(seconds: 5));

    expect(
      harness.notifier.takeLatestToolResults(owner!).single.result,
      contains(MaterialContractAssumptionGuard.blockedCode),
      reason:
          'Declining is not a deferral: the assumption stays unconfirmed and '
          'the call stays refused.',
    );
    expect(_currentAssumption(harness.container).confirmed, isFalse);
  });

  test('confirming records provenance and lets the same call through', () async {
    final harness = await _startBlockedMutationTurn();
    final pending = harness.notifier.state.pendingAssumptionConfirmation!;

    harness.notifier.resolveAssumptionConfirmation(
      id: pending.id,
      confirmed: true,
    );
    // The same call now reaches its own approval, which is the observable
    // proof that the assumption gate stopped holding it: the write is gated
    // twice -- on what the plan assumes and on touching the file -- and only
    // the first of those has been answered.
    await _waitForCondition(
      () => harness.notifier.state.pendingFileOperation != null,
    );
    harness.notifier.resolveFileOperation(
      id: harness.notifier.state.pendingFileOperation!.id,
      approved: false,
    );
    final owner = await harness.send.timeout(const Duration(seconds: 5));

    expect(
      harness.notifier.takeLatestToolResults(owner!).single.result,
      isNot(contains(MaterialContractAssumptionGuard.blockedCode)),
      reason:
          'The gate re-evaluates after the answer, so the refused call is the '
          'one that proceeds. Waiting for the next tool call would mean the '
          'confirmation unblocked nothing the user was watching.',
    );

    final confirmed = _currentAssumption(harness.container);
    expect(confirmed.confirmed, isTrue);
    final conversation = harness.container
        .read(conversationsNotifierProvider.notifier)
        .state
        .conversationForId(null)!;
    final source = conversation.effectiveWorkflowSpec.sources.singleWhere(
      (source) =>
          source.kind == ConversationContractSourceKind.userConfirmedAssumption,
    );
    expect(
      confirmed.sourceIds,
      contains(source.id),
      reason:
          'A flag alone cannot answer why this was later treated as known; '
          'the provenance graph has to reach the confirmation from the item.',
    );
  });

  test('an answered confirmation leaves the slot it was shown in', () async {
    final harness = await _startBlockedMutationTurn();
    final pending = harness.notifier.state.pendingAssumptionConfirmation!;

    harness.notifier.resolveAssumptionConfirmation(
      id: pending.id,
      confirmed: true,
    );
    await _waitForCondition(
      () => harness.notifier.state.pendingFileOperation != null,
    );
    harness.notifier.resolveFileOperation(
      id: harness.notifier.state.pendingFileOperation!.id,
      approved: false,
    );
    await harness.send.timeout(const Duration(seconds: 5));

    expect(
      harness.notifier.state.pendingAssumptionConfirmation,
      isNull,
      reason:
          'A slot still holding an answered approval re-presents its sheet on '
          'the next rebuild, and the second answer has nothing to complete.',
    );
  });

  test('a turn addressed to the parent cannot change the workspace', () async {
    // The @anabasis entry point, end to end: the address puts the turn in the
    // parent role, the role reaches the tool loop through the zone, and the
    // authority guard refuses the mutation there. Nothing in this test names
    // the guard — if the wiring is wrong the write simply happens.
    final harness = await _startAddressedParentTurn();
    final owner = await harness.send.timeout(const Duration(seconds: 5));

    expect(
      harness.notifier.takeLatestToolResults(owner!).single.result,
      contains(AnabasisParentAuthorityGuard.refusedCode),
      reason:
          'The parent orchestrates and delegates; it does not edit. A refusal '
          'here is the boundary working, not a failure.',
    );
    expect(
      harness.notifier.state.pendingFileOperation,
      isNull,
      reason:
          'The call must be refused before it reaches its own approval — '
          'asking the user to approve a write the parent may not perform is a '
          'question with no right answer.',
    );
  });

  test('a parent turn actually gets the parent prompt', () async {
    // The defect this pins, found by typing @anabasis into the real app: the
    // role was carried in a zone, and the request zone opened inside the turn
    // defaults to ModelUsageRole.chat. An inner zone wins, so the role was
    // replaced before the system prompt was built and @anabasis reached a live
    // conversation with none of the parent's instructions.
    //
    // Every unit test passed throughout, because they exercised the zone
    // directly rather than the request path that nests inside it. This one
    // reads the system prompt the datasource was handed.
    final harness = await _startAddressedParentTurn();
    await harness.send.timeout(const Duration(seconds: 5));

    final systemPrompt = harness.dataSource.initialRequestMessages
        .firstWhere((message) => message.role == MessageRole.system)
        .content;

    expect(
      systemPrompt,
      contains('You are Anabasis'),
      reason:
          'Without this the model is told nothing about its boundary and reads '
          "the guard's refusal as a transient failure.",
    );

    // The reply the user reads has to say who answered. The first version
    // marked only the hidden-prompt path, so a real @anabasis turn rendered as
    // an ordinary one.
    expect(
      harness.notifier.state.messages
          .where((message) => message.role == MessageRole.assistant)
          .every((message) => message.isAnabasisParent),
      isTrue,
      reason:
          'Every assistant message this turn produced is the parent speaking, '
          'including the continuation that follows a tool call.',
    );
  });
}
