"""Check Qwen parameter whitespace using parser source without server imports."""
import argparse
import ast
import json
from pathlib import Path
from types import SimpleNamespace


def check(parser_path: Path, common_path: Path) -> None:
    common = {}
    exec(compile(common_path.read_text(), str(common_path), "exec"), common)
    tree = ast.parse(parser_path.read_text())
    tree.body = [node for node in tree.body if not isinstance(node, ast.ImportFrom)]
    scope = {
        "FormatSignature": common["FormatSignature"],
        "coerce_param_value": common["coerce_param_value"],
        "ToolCall": lambda **kwargs: SimpleNamespace(**kwargs),
        "Tool": lambda **kwargs: SimpleNamespace(**kwargs),
        "xlogger": SimpleNamespace(debug=lambda *args, **kwargs: None),
    }
    exec(compile(tree, str(parser_path), "exec"), scope)
    cases = [
        ("hello from unattended\n", "hello from unattended\n"),
        ("  indented\t\n", "  indented\t\n"),
        ("   ", "   "),
        ("", ""),
        ('{"a":1}', {"a": 1}),
        ("true", True),
        ("42", 42),
        ("[1,2]", [1, 2]),
        ("null", None),
        ('"quoted\\n"', "quoted\n"),
    ]
    for raw, expected in cases:
        text = (
            '<tool_call><function=write_file><parameter=content>\n'
            + raw + '\n</parameter></function></tool_call>'
        )
        call = scope["parse_toolcalls"](text)[0]
        actual = json.loads(call.function.arguments)["content"]
        assert actual == expected and type(actual) is type(expected), (
            f"Whitespace/type mismatch: expected {expected!r}, received {actual!r}"
        )
    print(f"PASS {len(cases)} synthetic parameter cases")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parser_source", type=Path)
    parser.add_argument("common_source", type=Path)
    args = parser.parse_args()
    check(args.parser_source, args.common_source)
