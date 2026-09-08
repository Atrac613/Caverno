#!/usr/bin/env python3
"""Expand and verify macOS Release entitlements for Sparkle re-sign.

The Sparkle driver re-signs the outer app with --force. Preserving whatever
is already on the binary cannot restore a stripped signature, and it can
copy Debug-only keys such as get-task-allow. This helper expands
macos/Runner/Release.entitlements with the signed team and bundle IDs, then
checks that the codesign dump actually contains those keys.
"""

from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys

REQUIRED_TRUE_KEYS = (
    "com.apple.security.network.client",
    "com.apple.security.network.server",
    "com.apple.security.files.user-selected.read-write",
)

GET_TASK_ALLOW = "com.apple.security.get-task-allow"
APP_IDENTIFIER_KEY = "com.apple.application-identifier"
TEAM_IDENTIFIER_KEY = "com.apple.developer.team-identifier"
KEYCHAIN_GROUPS_KEY = "keychain-access-groups"
APP_IDENTIFIER_PREFIX = "$(AppIdentifierPrefix)"


def parse_entitlements_blob(data: bytes) -> dict:
    """Parse a codesign entitlements dump, including the legacy blob header."""
    if not data or not data.strip():
        return {}
    if data.startswith(b"<?xml") or data.startswith(b"bplist"):
        return plistlib.loads(data)
    xml_at = data.find(b"<?xml")
    if xml_at != -1:
        return plistlib.loads(data[xml_at:])
    bplist_at = data.find(b"bplist00")
    if bplist_at != -1:
        return plistlib.loads(data[bplist_at:])
    try:
        return plistlib.loads(data)
    except Exception:
        return {}


def _expand_placeholders(value, prefix: str):
    if isinstance(value, str):
        return value.replace(APP_IDENTIFIER_PREFIX, prefix)
    if isinstance(value, list):
        return [_expand_placeholders(item, prefix) for item in value]
    if isinstance(value, dict):
        return {
            key: _expand_placeholders(item, prefix) for key, item in value.items()
        }
    return value


def expand_release_entitlements(
    source: dict,
    *,
    team_id: str,
    bundle_id: str,
) -> dict:
    team = team_id.strip()
    bundle = bundle_id.strip()
    if not team or team == "-":
        raise ValueError("team id is missing")
    if not bundle:
        raise ValueError("bundle id is missing")
    if source.get(GET_TASK_ALLOW) is True:
        raise ValueError(
            "Release entitlements must not enable com.apple.security.get-task-allow"
        )

    expanded = _expand_placeholders(dict(source), f"{team}.")
    expanded[APP_IDENTIFIER_KEY] = f"{team}.{bundle}"
    expanded[TEAM_IDENTIFIER_KEY] = team
    problems = validate_signed_entitlements(expanded)
    if problems:
        raise ValueError(
            "expanded Release entitlements are incomplete: " + ", ".join(problems)
        )
    return expanded


def validate_signed_entitlements(entitlements: dict) -> list[str]:
    if not isinstance(entitlements, dict) or not entitlements:
        return ["signed entitlements dump is empty"]
    problems: list[str] = []
    if entitlements.get(GET_TASK_ALLOW) is True:
        problems.append(GET_TASK_ALLOW)
    for key in REQUIRED_TRUE_KEYS:
        if entitlements.get(key) is not True:
            problems.append(key)
    groups = entitlements.get(KEYCHAIN_GROUPS_KEY)
    if not isinstance(groups, list) or not any(
        isinstance(group, str) and group.strip() for group in groups
    ):
        problems.append(KEYCHAIN_GROUPS_KEY)
    app_id = entitlements.get(APP_IDENTIFIER_KEY)
    if not isinstance(app_id, str) or "." not in app_id.strip():
        problems.append(APP_IDENTIFIER_KEY)
    return problems


def dump_app_entitlements(app_path: str) -> dict:
    result = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", app_path],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        err = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(
            f"codesign failed to dump entitlements for {app_path}: {err}"
        )
    return parse_entitlements_blob(result.stdout)


def _load_plist(path: str) -> dict:
    with open(path, "rb") as handle:
        loaded = parse_entitlements_blob(handle.read())
    if not isinstance(loaded, dict):
        return {}
    return loaded


def _die(message: str, code: int = 65) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _cmd_expand(args: argparse.Namespace) -> int:
    try:
        expanded = expand_release_entitlements(
            _load_plist(args.source),
            team_id=args.team_id,
            bundle_id=args.bundle_id,
        )
    except ValueError as error:
        _die(str(error))
    with open(args.output, "wb") as handle:
        plistlib.dump(expanded, handle, fmt=plistlib.FMT_XML)
    return 0


def _report_problems(problems: list[str], *, empty_hint: str) -> int:
    if not problems:
        print("Verified signed app entitlements include keychain-access-groups")
        return 0
    print("Release app is missing signed entitlements:", file=sys.stderr)
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    if "signed entitlements dump is empty" in problems:
        print(empty_hint, file=sys.stderr)
    print(
        "flutter_secure_storage then fails with errSecMissingEntitlement (-34018).",
        file=sys.stderr,
    )
    return 65


def _cmd_verify_file(args: argparse.Namespace) -> int:
    return _report_problems(
        validate_signed_entitlements(_load_plist(args.path)),
        empty_hint="The entitlements file is empty.",
    )


def _cmd_verify_app(args: argparse.Namespace) -> int:
    try:
        entitlements = dump_app_entitlements(args.app)
    except RuntimeError as error:
        _die(str(error))
    return _report_problems(
        validate_signed_entitlements(entitlements),
        empty_hint=(
            "Re-sign the outer app with --entitlements pointing at the expanded "
            "Release entitlements file. Preserving an already-empty dump cannot "
            "restore keychain-access-groups."
        ),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    expand = sub.add_parser(
        "expand",
        help="Write expanded Release entitlements for codesign --entitlements.",
    )
    expand.add_argument("--source", required=True)
    expand.add_argument("--team-id", required=True)
    expand.add_argument("--bundle-id", required=True)
    expand.add_argument("--output", required=True)
    expand.set_defaults(func=_cmd_expand)

    verify_file = sub.add_parser(
        "verify-file",
        help="Validate an entitlements plist or codesign dump.",
    )
    verify_file.add_argument("--path", required=True)
    verify_file.set_defaults(func=_cmd_verify_file)

    verify_app = sub.add_parser(
        "verify-app",
        help="Dump and validate entitlements from a signed .app.",
    )
    verify_app.add_argument("--app", required=True)
    verify_app.set_defaults(func=_cmd_verify_app)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
