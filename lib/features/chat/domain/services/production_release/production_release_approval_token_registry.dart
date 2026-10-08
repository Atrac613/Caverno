import 'dart:math';

import 'production_release_blocked_result.dart';

/// Issues and remembers the approval token for each blocked release.
///
/// Tokens are kept per conversation rather than per generation because
/// approval arrives in a later turn than the block: the model is told to ask,
/// the user answers, and only then is the release retried. A token is dropped
/// with its pending release, so it can never authorize a second, different
/// release.
final class ProductionReleaseApprovalTokenRegistry {
  ProductionReleaseApprovalTokenRegistry({String Function()? tokenFactory})
    : _tokenFactory = tokenFactory ?? randomToken;

  final String Function() _tokenFactory;
  final _tokens = <String, String>{};

  String? tokenFor(String conversationId) => _tokens[conversationId];

  /// The token for [conversationId], reused while that release stays blocked
  /// so a re-ask does not invalidate an answer the user already gave.
  ///
  /// A null conversation cannot be remembered, so it gets a throwaway token
  /// rather than sharing one with an unrelated release.
  String issueFor(String? conversationId) => conversationId == null
      ? _tokenFactory()
      : _tokens.putIfAbsent(conversationId, _tokenFactory);

  void release(String conversationId) => _tokens.remove(conversationId);

  void clear() => _tokens.clear();

  /// Deliberately unpredictable, so the model cannot pre-authorize a release
  /// it has not been blocked on yet.
  static String randomToken() {
    final random = Random.secure();
    final buffer = StringBuffer('rel-');
    for (var i = 0; i < productionReleaseApprovalTokenLength; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
