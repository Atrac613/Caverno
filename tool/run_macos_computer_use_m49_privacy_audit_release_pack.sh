#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORT_ROOT="${CAVERNO_MACOS_COMPUTER_USE_M49_PRIVACY_AUDIT_RELEASE_PACK_ROOT:-${ROOT_DIR}/build/integration_test_reports}"
RUN_ID="$(date +%s)"
RUN_DIR="${REPORT_ROOT}/macos_computer_use_m49_privacy_audit_release_pack_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/privacy_audit_release_pack.json"
SUMMARY_MD="${RUN_DIR}/privacy_audit_release_pack.md"
M48_PILOT=""
DIAGNOSTICS=""
REDACTED_EXPORT_REVIEWED="${CAVERNO_MACOS_COMPUTER_USE_M49_REDACTED_EXPORT_REVIEWED:-no}"
PRIVACY_COPY_REVIEWED="${CAVERNO_MACOS_COMPUTER_USE_M49_PRIVACY_COPY_REVIEWED:-no}"
SUPPORT_DIAGNOSTICS_REVIEWED="${CAVERNO_MACOS_COMPUTER_USE_M49_SUPPORT_DIAGNOSTICS_REVIEWED:-no}"
EXPLICIT_PAYLOAD_EXPORT_POLICY_REVIEWED="${CAVERNO_MACOS_COMPUTER_USE_M49_EXPLICIT_PAYLOAD_EXPORT_POLICY_REVIEWED:-no}"
PAYLOAD_EXPORT_REQUESTED="${CAVERNO_MACOS_COMPUTER_USE_M49_PAYLOAD_EXPORT_REQUESTED:-no}"
EXPLICIT_PAYLOAD_EXPORT_APPROVED="${CAVERNO_MACOS_COMPUTER_USE_M49_EXPLICIT_PAYLOAD_EXPORT_APPROVED:-not-requested}"
SUPPORT_NOTE="${CAVERNO_MACOS_COMPUTER_USE_M49_SUPPORT_NOTE:-}"

require_value() {
  if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
    echo "$1 requires a value." >&2
    exit 64
  fi
}

usage() {
  cat <<'USAGE'
Usage: bash tool/run_macos_computer_use_m49_privacy_audit_release_pack.sh [options]

Options:
  --root PATH                                  Report root directory.
  --m48-pilot PATH                             Ready M48 user-operated action pilot JSON.
  --diagnostics PATH                           Redacted Computer Use diagnostics JSON or audit privacy controls JSON.
  --redacted-export-reviewed VALUE             yes or no.
  --privacy-copy-reviewed VALUE                yes or no.
  --support-diagnostics-reviewed VALUE         yes or no.
  --explicit-payload-export-policy-reviewed VALUE yes or no.
  --payload-export-requested VALUE             yes or no.
  --explicit-payload-export-approved VALUE     yes, no, or not-requested.
  --support-note TEXT                          Optional support review note.
  --help                                       Show this help.

This M49 release pack is report-only. It reads ready M48 action-cycle evidence
and redacted Computer Use diagnostics, then validates privacy, audit export,
support-diagnostics, and explicit-payload-export gates. It does not call an LLM,
grant TCC, open apps, operate System Settings, move the pointer, click, type,
submit, post, purchase, export raw payloads, or perform desktop actions.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      require_value "$@"
      REPORT_ROOT="$2"
      shift 2
      ;;
    --m48-pilot)
      require_value "$@"
      M48_PILOT="$2"
      shift 2
      ;;
    --diagnostics)
      require_value "$@"
      DIAGNOSTICS="$2"
      shift 2
      ;;
    --redacted-export-reviewed)
      require_value "$@"
      REDACTED_EXPORT_REVIEWED="$2"
      shift 2
      ;;
    --privacy-copy-reviewed)
      require_value "$@"
      PRIVACY_COPY_REVIEWED="$2"
      shift 2
      ;;
    --support-diagnostics-reviewed)
      require_value "$@"
      SUPPORT_DIAGNOSTICS_REVIEWED="$2"
      shift 2
      ;;
    --explicit-payload-export-policy-reviewed)
      require_value "$@"
      EXPLICIT_PAYLOAD_EXPORT_POLICY_REVIEWED="$2"
      shift 2
      ;;
    --payload-export-requested)
      require_value "$@"
      PAYLOAD_EXPORT_REQUESTED="$2"
      shift 2
      ;;
    --explicit-payload-export-approved)
      require_value "$@"
      EXPLICIT_PAYLOAD_EXPORT_APPROVED="$2"
      shift 2
      ;;
    --support-note)
      require_value "$@"
      SUPPORT_NOTE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

RUN_DIR="${REPORT_ROOT}/macos_computer_use_m49_privacy_audit_release_pack_${RUN_ID}"
SUMMARY_JSON="${RUN_DIR}/privacy_audit_release_pack.json"
SUMMARY_MD="${RUN_DIR}/privacy_audit_release_pack.md"
mkdir -p "${RUN_DIR}"

if [[ -z "${M48_PILOT}" ]]; then
  M48_PILOT="$(find "${REPORT_ROOT}" -path '*/macos_computer_use_m48_user_operated_action_pilot_*/user_operated_action_pilot.json' -type f 2>/dev/null | sort | tail -n 1 || true)"
fi

if [[ -z "${M48_PILOT}" ]]; then
  echo "M48 user-operated action pilot not found under ${REPORT_ROOT}." >&2
  exit 66
fi
if [[ ! -f "${M48_PILOT}" ]]; then
  echo "M48 user-operated action pilot not found: ${M48_PILOT}" >&2
  exit 66
fi
if [[ -z "${DIAGNOSTICS}" ]]; then
  echo "--diagnostics is required for the M49 privacy and audit release pack." >&2
  exit 64
fi
if [[ ! -f "${DIAGNOSTICS}" ]]; then
  echo "Diagnostics JSON not found: ${DIAGNOSTICS}" >&2
  exit 66
fi

echo "Running macOS Computer Use M49 privacy and audit release pack"
echo "  Purpose: validate redacted audit export, privacy copy, and support diagnostics"
echo "  M48 pilot: ${M48_PILOT}"
echo "  Diagnostics: ${DIAGNOSTICS}"
echo "  Report dir: ${RUN_DIR}"
echo "  Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions, no raw payload export"

SUMMARY_JSON="${SUMMARY_JSON}" \
SUMMARY_MD="${SUMMARY_MD}" \
M48_PILOT="${M48_PILOT}" \
DIAGNOSTICS="${DIAGNOSTICS}" \
REDACTED_EXPORT_REVIEWED="${REDACTED_EXPORT_REVIEWED}" \
PRIVACY_COPY_REVIEWED="${PRIVACY_COPY_REVIEWED}" \
SUPPORT_DIAGNOSTICS_REVIEWED="${SUPPORT_DIAGNOSTICS_REVIEWED}" \
EXPLICIT_PAYLOAD_EXPORT_POLICY_REVIEWED="${EXPLICIT_PAYLOAD_EXPORT_POLICY_REVIEWED}" \
PAYLOAD_EXPORT_REQUESTED="${PAYLOAD_EXPORT_REQUESTED}" \
EXPLICIT_PAYLOAD_EXPORT_APPROVED="${EXPLICIT_PAYLOAD_EXPORT_APPROVED}" \
SUPPORT_NOTE="${SUPPORT_NOTE}" \
python3 - <<'PY'
import json
import os
from pathlib import Path


summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
m48_pilot_path = Path(os.environ["M48_PILOT"])
diagnostics_path = Path(os.environ["DIAGNOSTICS"])

m48 = json.loads(m48_pilot_path.read_text())
diagnostics = json.loads(diagnostics_path.read_text())

review_inputs = {
    "redactedExportReviewed": os.environ["REDACTED_EXPORT_REVIEWED"].strip().lower(),
    "privacyCopyReviewed": os.environ["PRIVACY_COPY_REVIEWED"].strip().lower(),
    "supportDiagnosticsReviewed": os.environ["SUPPORT_DIAGNOSTICS_REVIEWED"].strip().lower(),
    "explicitPayloadExportPolicyReviewed": os.environ[
        "EXPLICIT_PAYLOAD_EXPORT_POLICY_REVIEWED"
    ].strip().lower(),
    "payloadExportRequested": os.environ["PAYLOAD_EXPORT_REQUESTED"].strip().lower(),
    "explicitPayloadExportApproved": os.environ[
        "EXPLICIT_PAYLOAD_EXPORT_APPROVED"
    ].strip().lower(),
    "supportNote": os.environ["SUPPORT_NOTE"],
}

m48_gate = m48.get("m48UserOperatedActionPilotGate")
m48_gate = m48_gate if isinstance(m48_gate, dict) else {}


def map_value(value):
    return value if isinstance(value, dict) else {}


def list_value(value):
    return value if isinstance(value, list) else []


if diagnostics.get("schemaName") == "macos_computer_use_audit_privacy_controls":
    audit_controls = diagnostics
else:
    audit_controls = map_value(diagnostics.get("auditPrivacyControls"))

audit_gate = map_value(audit_controls.get("m37AuditPrivacyGate"))
required_event_types = [str(item) for item in list_value(audit_controls.get("requiredEventTypes"))]
redacted_field_ids = [str(item) for item in list_value(audit_controls.get("redactedFieldIds"))]
explicit_export_ids = [
    str(item) for item in list_value(audit_controls.get("explicitExportRequiredFieldIds"))
]
latest_audit_coverage = map_value(audit_controls.get("latestAuditCoverage"))
audit_log = list_value(diagnostics.get("auditLog"))

required_redactions = {
    "secrets",
    "screenshots",
    "tokens",
    "audio_payloads",
    "raw_tool_payloads",
    "typed_text",
}
required_explicit_exports = {
    "screenshots",
    "audio_payloads",
    "typed_text",
    "raw_tool_payloads",
}
required_events = {
    "observe",
    "approval",
    "execution_handoff",
    "emergency_stop",
    "result_review",
}

forbidden_raw_key_tokens = [
    "imagebase64",
    "audiobase64",
    "audio_base64",
    "typedtext",
    "typed_text_body",
    "rawtoolpayload",
    "raw_tool_payload",
    "authorization",
    "apikey",
    "api_key",
    "password",
    "secret",
]
allowed_redacted_markers = ("<", "redacted", "omitted")


def find_raw_payload_leaks(value, path="$"):
    leaks = []
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            normalized_key = key_text.replace("-", "_").lower()
            child_path = f"{path}.{key_text}"
            if any(token in normalized_key for token in forbidden_raw_key_tokens):
                if isinstance(child, str) and child:
                    normalized_child = child.lower()
                    if not any(marker in normalized_child for marker in allowed_redacted_markers):
                        leaks.append(child_path)
                elif child not in (None, False, 0, ""):
                    if not isinstance(child, bool):
                        leaks.append(child_path)
            leaks.extend(find_raw_payload_leaks(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            leaks.extend(find_raw_payload_leaks(child, f"{path}[{index}]"))
    return leaks


raw_payload_leaks = sorted(set(find_raw_payload_leaks(diagnostics)))
payload_requested = review_inputs["payloadExportRequested"] == "yes"
payload_approval = review_inputs["explicitPayloadExportApproved"]


def value_allowed(value, allowed):
    return value in allowed


checks = [
    {
        "id": "m48_pilot_schema_valid",
        "ok": m48.get("schemaName") == "macos_computer_use_m48_user_operated_action_pilot"
        and m48.get("milestone") == "M48",
        "nextAction": "Select a valid M48 user_operated_action_pilot.json before preparing the M49 release pack.",
    },
    {
        "id": "m48_pilot_ready",
        "ok": bool(m48.get("ready")) and m48_gate.get("status") == "ready",
        "nextAction": "Run the M48 user-operated action pilot until m48UserOperatedActionPilotGate.status is ready.",
    },
    {
        "id": "audit_privacy_schema_valid",
        "ok": audit_controls.get("schemaName") == "macos_computer_use_audit_privacy_controls",
        "nextAction": "Export diagnostics that include auditPrivacyControls or provide the M37 audit controls JSON.",
    },
    {
        "id": "audit_privacy_gate_ready",
        "ok": audit_controls.get("status") in {"defined", "ready"}
        and audit_gate.get("status") == "ready",
        "nextAction": "Provide ready M37 audit privacy controls before preparing M49.",
    },
    {
        "id": "required_event_types_declared",
        "ok": required_events.issubset(set(required_event_types)),
        "nextAction": "Audit privacy controls must declare observe, approval, execution handoff, emergency stop, and result review events.",
    },
    {
        "id": "latest_audit_coverage_present",
        "ok": bool(latest_audit_coverage) or bool(audit_log),
        "nextAction": "Export diagnostics with latest audit coverage or redacted audit entries.",
    },
    {
        "id": "default_export_redacted",
        "ok": audit_controls.get("defaultExportRedacted") is True,
        "nextAction": "Default Computer Use diagnostics exports must be redacted.",
    },
    {
        "id": "required_redactions_declared",
        "ok": required_redactions.issubset(set(redacted_field_ids)),
        "nextAction": "Redacted field ids must include secrets, screenshots, tokens, audio payloads, raw tool payloads, and typed text.",
    },
    {
        "id": "explicit_payload_export_required",
        "ok": audit_controls.get("explicitPayloadExportRequired") is True
        and required_explicit_exports.issubset(set(explicit_export_ids)),
        "nextAction": "Screenshot, audio, typed text, and raw tool payload exports must require explicit payload export approval.",
    },
    {
        "id": "ordinary_diagnostics_redacted",
        "ok": not raw_payload_leaks,
        "nextAction": "Remove raw screenshots, audio payloads, typed text, secrets, tokens, and raw tool payloads from ordinary diagnostics.",
    },
    {
        "id": "redacted_export_reviewed",
        "ok": review_inputs["redactedExportReviewed"] == "yes",
        "nextAction": "Review the redacted audit export and record approval before M49 is ready.",
    },
    {
        "id": "privacy_copy_reviewed",
        "ok": review_inputs["privacyCopyReviewed"] == "yes",
        "nextAction": "Review Computer Use privacy copy before M49 is ready.",
    },
    {
        "id": "support_diagnostics_reviewed",
        "ok": review_inputs["supportDiagnosticsReviewed"] == "yes",
        "nextAction": "Review support diagnostics for redaction and supportability before M49 is ready.",
    },
    {
        "id": "explicit_payload_export_policy_reviewed",
        "ok": review_inputs["explicitPayloadExportPolicyReviewed"] == "yes",
        "nextAction": "Review and record the explicit payload export policy before M49 is ready.",
    },
    {
        "id": "payload_export_request_state_valid",
        "ok": value_allowed(review_inputs["payloadExportRequested"], {"yes", "no"})
        and value_allowed(payload_approval, {"yes", "no", "not-requested"}),
        "nextAction": "Use valid payload export values: requested yes/no and approved yes/no/not-requested.",
    },
    {
        "id": "explicit_payload_export_gate_closed",
        "ok": (not payload_requested and payload_approval == "not-requested")
        or (payload_requested and payload_approval == "yes"),
        "nextAction": "If raw payload export is requested, record separate explicit approval; otherwise keep it not-requested.",
    },
    {
        "id": "report_only_boundaries_preserved",
        "ok": m48.get("llmBoundary") == "no_llm_call"
        and m48.get("tccBoundary") == "no_tcc_operation"
        and m48.get("desktopActionBoundary") == "user_operated_evidence_only",
        "nextAction": "Keep M49 report-only and separate from TCC, LLM, and desktop action execution.",
    },
]

blockers = [check["id"] for check in checks if not check["ok"]]
ready = not blockers
summary = {
    "schemaName": "macos_computer_use_m49_privacy_audit_release_pack",
    "schemaVersion": 1,
    "purpose": "computer_use_m49_privacy_audit_release_pack",
    "milestone": "M49",
    "previousMilestone": "M48",
    "ready": ready,
    "status": "ready" if ready else "blocked",
    "executionBoundary": "report_only_privacy_audit_release_pack",
    "desktopActionBoundary": "no_desktop_action",
    "tccBoundary": "no_tcc_operation",
    "llmBoundary": "no_llm_call",
    "sourceArtifacts": {
        "m48Pilot": str(m48_pilot_path),
        "diagnostics": str(diagnostics_path),
    },
    "reviewInputs": review_inputs,
    "auditPrivacySummary": {
        "schemaName": audit_controls.get("schemaName"),
        "status": audit_controls.get("status"),
        "gateStatus": audit_gate.get("status"),
        "requiredEventTypes": required_event_types,
        "redactedFieldIds": redacted_field_ids,
        "explicitExportRequiredFieldIds": explicit_export_ids,
        "latestAuditCoveragePresent": bool(latest_audit_coverage),
        "redactedAuditEntryCount": len(audit_log),
        "rawPayloadLeakCount": len(raw_payload_leaks),
        "rawPayloadLeakPaths": raw_payload_leaks,
    },
    "m49PrivacyAuditReleasePackGate": {
        "status": "ready" if ready else "blocked",
        "ready": ready,
        "checks": checks,
        "blockers": blockers,
        "nextAction": "M49 privacy and audit release pack is ready for M50 signed beta."
        if ready
        else "Resolve blocked M49 privacy and audit checks before starting M50.",
    },
    "manualBoundary": [
        "M49 reads existing M48 and diagnostics evidence only.",
        "M49 does not export raw screenshots, typed text, audio payloads, or raw tool payloads.",
        "Raw payload export requires a separate explicit user-approved artifact flow.",
    ],
}
summary_json.write_text(json.dumps(summary, indent=2) + "\n")


def cell(value):
    return str(value).replace("|", "\\|") if value is not None else "-"


lines = [
    "# macOS Computer Use M49 Privacy And Audit Release Pack",
    "",
    f"- Ready: {str(ready).lower()}",
    "- Boundary: report-only, no LLM call, no TCC, no System Settings, no desktop actions, no raw payload export",
    f"- M48 pilot: `{m48_pilot_path}`",
    f"- Diagnostics: `{diagnostics_path}`",
    "",
    "## Gate",
    "",
    "| Check | Status | Next Action |",
    "| --- | --- | --- |",
]
for check in checks:
    lines.append(
        "| {id} | {status} | {nextAction} |".format(
            id=check["id"],
            status="passed" if check["ok"] else "blocked",
            nextAction=cell(check["nextAction"]),
        )
    )

lines.extend(
    [
        "",
        "## Review Inputs",
        "",
        "| Input | Value |",
        "| --- | --- |",
    ]
)
for key, value in review_inputs.items():
    lines.append(f"| {cell(key)} | {cell(value)} |")

lines.extend(
    [
        "",
        "## Audit Privacy Summary",
        "",
        f"- Schema: {cell(audit_controls.get('schemaName'))}",
        f"- Status: {cell(audit_controls.get('status'))}",
        f"- Gate: {cell(audit_gate.get('status'))}",
        f"- Redacted audit entries: {len(audit_log)}",
        f"- Raw payload leak count: {len(raw_payload_leaks)}",
        "- Redacted fields: " + ", ".join(redacted_field_ids),
        "- Explicit payload export fields: " + ", ".join(explicit_export_ids),
        "",
        "## Manual Boundary",
        "",
        "This release pack reads existing redacted diagnostics and M48 evidence.",
        "Raw payload export remains outside ordinary diagnostics and requires",
        "a separate explicit user-approved artifact flow.",
        "",
    ]
)
summary_md.write_text("\n".join(lines) + "\n")

print(f"M49 privacy and audit release pack written to {summary_json}")
print(f"M49 privacy and audit release pack Markdown written to {summary_md}")
print(f"Gate status: {summary['m49PrivacyAuditReleasePackGate']['status']}")
print(f"Ready: {str(ready).lower()}")
print("Blockers: " + (", ".join(blockers) if blockers else "none"))

raise SystemExit(0 if ready else 1)
PY
