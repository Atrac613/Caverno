import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../domain/services/feedback_submission_service.dart';

final feedbackSubmissionServiceProvider = Provider<FeedbackSubmissionClient>((
  ref,
) {
  final client = http.Client();
  ref.onDispose(client.close);
  return FeedbackSubmissionService(client: client);
});
