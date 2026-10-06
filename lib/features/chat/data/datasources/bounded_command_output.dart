/// Retains the start and end of a stream within a fixed character budget.
/// Tracebacks and runner summaries often follow large diagnostic output.
final class BoundedCommandOutput {
  BoundedCommandOutput(this.maxLength) : assert(maxLength > 0);

  static const omission = '\n... output truncated ...\n';

  final int maxLength;
  String _text = '';
  bool truncated = false;

  void add(String chunk) {
    if (chunk.isEmpty) return;
    if (!truncated && _text.length + chunk.length <= maxLength) {
      _text += chunk;
      return;
    }
    final marker = maxLength > omission.length ? omission : '';
    final retained = maxLength - marker.length;
    final headLength = retained ~/ 2;
    final tailLength = retained - headLength;
    final combinedHead = _text.length >= headLength
        ? _text.substring(0, headLength)
        : _text + chunk.substring(0, headLength - _text.length);
    final tail = chunk.length >= tailLength
        ? chunk.substring(chunk.length - tailLength)
        : (_text + chunk).substring(_text.length + chunk.length - tailLength);
    _text = '$combinedHead$marker$tail';
    truncated = true;
  }

  String get text => _text;
}
