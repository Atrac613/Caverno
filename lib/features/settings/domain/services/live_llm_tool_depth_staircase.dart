/// One rung of the tool-state staircase.
///
/// Each rung is the same errand carried one tool call further, and every step
/// past the first needs a value the previous step produced. A model that can
/// call one tool cleanly but loses `doc-ds-42` on the way to step three fails
/// here and passes every other tool probe in the suite.
class LiveLlmToolDepthStep {
  const LiveLlmToolDepthStep({
    required this.toolName,
    required this.expectedArguments,
    required this.result,
  });

  final String toolName;

  /// Arguments the call must carry. Compared key by key, so a model may add
  /// its own optional fields; it may not get these wrong.
  final Map<String, Object?> expectedArguments;

  /// The canned observation handed back for this call. Scripted rather than
  /// executed so the rung measures the model's state carrying and not whatever
  /// the live catalog happens to hold.
  final Map<String, Object?> result;
}

class LiveLlmToolDepthRung {
  const LiveLlmToolDepthRung({
    required this.depth,
    required this.prompt,
    required this.steps,
    required this.expectedFinalValues,
  });

  final int depth;
  final String prompt;
  final List<LiveLlmToolDepthStep> steps;

  /// Literal values the final answer must carry. Every one of them is derived
  /// from a tool result rather than present in the prompt, so reciting the
  /// question cannot pass the rung.
  final List<String> expectedFinalValues;
}

/// The tool-chain depth axis: the same document errand at two, three and four
/// sequential tool calls.
///
/// Ported from the LocalLLM `tool_state_staircase` set rather than invented
/// here. It is a staircase on purpose -- a single hard case reports one bit,
/// while rungs report how far a model got and can be extended past four
/// without rescoring anything below.
class LiveLlmToolDepthStaircase {
  const LiveLlmToolDepthStaircase._();

  static const docId = 'doc-ds-42';
  static const revision = 'rev-7';
  static const attachmentId = 'att-91';
  static const query = 'flash attention';

  static const List<Map<String, dynamic>> toolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'search_docs',
        'description': 'Search documentation. The top result means top_k=1.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
            'top_k': {'type': 'integer'},
          },
          'required': ['query', 'top_k'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'open_doc',
        'description': 'Open a document by id.',
        'parameters': {
          'type': 'object',
          'properties': {
            'doc_id': {'type': 'string'},
          },
          'required': ['doc_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'summarize_doc',
        'description':
            'Summarize an opened document. Returns the summary and the '
            'revision it was taken from.',
        'parameters': {
          'type': 'object',
          'properties': {
            'doc_id': {'type': 'string'},
          },
          'required': ['doc_id'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'attach_summary',
        'description':
            'Attach a summary to a document at a given revision. Returns the '
            'attachment id.',
        'parameters': {
          'type': 'object',
          'properties': {
            'doc_id': {'type': 'string'},
            'revision': {'type': 'string'},
          },
          'required': ['doc_id', 'revision'],
        },
      },
    },
  ];

  static const _search = LiveLlmToolDepthStep(
    toolName: 'search_docs',
    expectedArguments: {'query': query, 'top_k': 1},
    result: {
      'results': [
        {'doc_id': docId, 'title': 'Flash attention tuning'},
      ],
    },
  );

  static const _open = LiveLlmToolDepthStep(
    toolName: 'open_doc',
    expectedArguments: {'doc_id': docId},
    result: {
      'doc_id': docId,
      'text': 'Flash attention should be enabled for long-context GPU runs.',
    },
  );

  static const _summarize = LiveLlmToolDepthStep(
    toolName: 'summarize_doc',
    expectedArguments: {'doc_id': docId},
    result: {
      'doc_id': docId,
      'summary': 'Enable flash attention for long-context GPU runs.',
      'revision': revision,
    },
  );

  static const _attach = LiveLlmToolDepthStep(
    toolName: 'attach_summary',
    expectedArguments: {'doc_id': docId, 'revision': revision},
    result: {'attachment_id': attachmentId, 'doc_id': docId},
  );

  /// Ordered shallowest first. The probe stops at the first rung that fails,
  /// so the depth it reports is a lower bound and never a lucky deep pass.
  static const List<LiveLlmToolDepthRung> rungs = [
    LiveLlmToolDepthRung(
      depth: 2,
      prompt:
          'Search the docs for flash attention, open the top result, and '
          'reply with the document id of what you opened and nothing else.',
      steps: [_search, _open],
      expectedFinalValues: [docId],
    ),
    LiveLlmToolDepthRung(
      depth: 3,
      prompt:
          'Search the docs for flash attention, open the top result, '
          'summarize it, and reply with the document id and the revision the '
          'summary came from, separated by a space, and nothing else.',
      steps: [_search, _open, _summarize],
      expectedFinalValues: [docId, revision],
    ),
    LiveLlmToolDepthRung(
      depth: 4,
      prompt:
          'Search the docs for flash attention, open the top result, '
          'summarize it, then attach that summary at the revision it came '
          'from. Reply with the attachment id and nothing else.',
      steps: [_search, _open, _summarize, _attach],
      expectedFinalValues: [attachmentId],
    ),
  ];

  static const List<int> stageDepths = [2, 3, 4];
}
