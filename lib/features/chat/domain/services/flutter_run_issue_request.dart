import '../entities/flutter_run_issue.dart';

/// What the analyser asks the model for, and the shape it must answer in.
class FlutterRunIssueRequest {
  const FlutterRunIssueRequest._();

  static const schema = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'title': {
        'type': 'string',
        'description':
            'One short line naming the problem, in the user\'s words',
      },
      'cause': {
        'type': 'string',
        'description': 'One sentence on why it happens, grounded in the block',
      },
      'severity': {
        'type': 'string',
        'enum': ['error', 'warning', 'info'],
      },
      'location': {
        'type': 'string',
        'description': 'file:line from the block, or an empty string',
      },
      'isFailure': {
        'type': 'boolean',
        'description':
            'False only when the excerpt contains no actual failure at all',
      },
    },
    'required': ['title', 'cause', 'severity'],
  };

  static String prompt(FlutterRunLogCandidate candidate) {
    final isWindow = candidate.kind == FlutterRunIssueKind.unclassifiedFailure;
    return 'You are reading output from a running Flutter app.\n'
        '${isWindow ? 'This is the tail of a run that ended badly, not a '
                  'framed failure: identify the actual failure in it, and set '
                  'isFailure to false only if there is genuinely none.\n' : ''}'
        'Report it as a single issue for the developer who owns this code.\n'
        'Use only what the block says; do not guess at code you cannot see.\n'
        'Keep the title under 80 characters and name the symptom, not the fix.\n'
        'Set severity to error for a crash or a failed build, warning for a '
        'layout or lint complaint the app survives, info otherwise.\n\n'
        'Failure kind: ${candidate.kind.name}\n'
        '${candidate.location == null ? '' : 'Reported at: ${candidate.location}\n'}'
        'Block:\n${candidate.evidence}';
  }
}
