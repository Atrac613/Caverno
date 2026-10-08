/// The context limit an endpoint's length error states, or null.
///
/// This reads an endpoint's error payload, not model prose, and only to bound
/// a learned window from above; a miss leaves the rejected prompt size as the
/// bound. Shapes seen in practice:
/// - OpenAI: "This model's maximum context length is 128000 tokens."
/// - llama.cpp: "... exceeds the available context size (65536 tokens)"
/// - vLLM: "maximum context length is 32768 tokens"
int? reportedContextLimit(String error) {
  final match = RegExp(
    r'(?:maximum context length is|context size \(|n_ctx[=:\s]+)\s*(\d{3,9})',
    caseSensitive: false,
  ).firstMatch(error);
  final value = match == null ? null : int.tryParse(match.group(1)!);
  return value != null && value > 0 ? value : null;
}
