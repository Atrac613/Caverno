import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../../core/theme/app_tokens.dart';

/// Markdown extensions that render LaTeX math written by LLMs.
///
/// LLM responses frequently emit math using TeX delimiters that the base
/// markdown renderer would otherwise show verbatim (e.g. `$O(\sqrt{n})$`).
/// These inline syntaxes capture the four delimiter styles models use in
/// practice and emit a `<math>` element that [MathElementBuilder] renders with
/// flutter_math:
///
/// - `$$ ... $$` and `\[ ... \]` -> display (block) math
/// - `$ ... $`  and `\( ... \)`  -> inline math
class MathMarkdown {
  MathMarkdown._();

  static const String tag = 'math';

  /// Inline syntaxes to pass to `MarkdownBody.inlineSyntaxes`.
  ///
  /// Order matters: the `$$` (display) syntax must precede the single-`$`
  /// (inline) syntax so a display block is not consumed as two empty inline
  /// spans. The markdown package evaluates user-provided syntaxes before its
  /// own escape handling, so `\(`/`\[` are captured here before they would be
  /// treated as escaped punctuation.
  ///
  /// Cached as a single reusable list: the syntaxes are stateless and the chat
  /// view rebuilds this markdown on every streaming token, so recompiling the
  /// patterns per build would be wasteful.
  static List<md.InlineSyntax> inlineSyntaxes() => _inlineSyntaxes;

  static final List<md.InlineSyntax> _inlineSyntaxes = <md.InlineSyntax>[
    _MathSyntax(r'\$\$([\s\S]+?)\$\$', display: true),
    _MathSyntax(r'\\\[([\s\S]+?)\\\]', display: true),
    _MathSyntax(r'\\\(([\s\S]+?)\\\)', display: false),
    // Inline `$...$`: opening `$` must not be followed by whitespace, the
    // closing `$` must not be preceded by whitespace and must not be followed
    // by a digit. The digit guard keeps currency ranges such as "$5 ... $10"
    // from being mistaken for a math span.
    _MathSyntax(r'\$(?!\s)((?:[^$\n])+?)(?<!\s)\$(?!\d)', display: false),
  ];
}

/// Recognizes a single TeX delimiter pair and emits a `<math>` element carrying
/// the raw expression in a `tex` attribute and the layout mode in `display`.
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax(super.pattern, {required this.display});

  final bool display;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = match[1]?.trim() ?? '';
    final element = md.Element.text(MathMarkdown.tag, tex)
      ..attributes['tex'] = tex
      ..attributes['display'] = display ? 'block' : 'inline';
    parser.addNode(element);
    // Always consume the full match; flutter_math renders an inline fallback
    // for unparseable/empty expressions, so we never bail out (returning false
    // here would stall the parser at this position).
    return true;
  }
}

/// Renders `<math>` elements produced by [MathMarkdown]'s inline syntaxes.
///
/// The widget keeps its intrinsic size so it composes cleanly inside the
/// `Wrap` that flutter_markdown_plus uses for inline children — wrapping it in a
/// scroll view or [Expanded] would crash with unbounded-width constraints.
class MathElementBuilder extends MarkdownElementBuilder {
  MathElementBuilder({required this.textColor, this.fontSize = 14});

  final Color textColor;
  final double fontSize;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag != MathMarkdown.tag) return null;

    final tex = element.attributes['tex'] ?? element.textContent;
    final isBlock = element.attributes['display'] == 'block';
    final style = TextStyle(color: textColor, fontSize: fontSize, height: 1.2);

    final math = Math.tex(
      tex,
      mathStyle: isBlock ? MathStyle.display : MathStyle.text,
      textStyle: style,
      // Fall back to the original delimited source so a malformed expression is
      // still legible instead of throwing or showing a raw exception string.
      onErrorFallback: (_) => Text(
        isBlock ? '\$\$$tex\$\$' : '\$$tex\$',
        style: style.copyWith(fontFamily: kMonoFontFamily),
      ),
    );

    if (!isBlock) {
      return math;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: math,
    );
  }
}
