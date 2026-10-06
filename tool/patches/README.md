# TabbyAPI Qwen Parameter Whitespace Repair

`tabby_qwen_parameter_whitespace.patch` targets
`endpoints/OAI/utils/toolcall_formats/qwen3_coder.py` in the running EXL3
backend checkout at `/mnt/storage1/models/tabbyAPI` on `192.168.100.241`.
It was deployed on 2026-10-04 after explicit user approval. The EXL3 backend
was restarted through its existing supervisor with the same model target.

The current Qwen parser strips the parameter and calls a shared coercer that
strips again. Plain string parameters lose trailing newlines, indentation and
whitespace-only values. The patch removes only one paired LF framing newline
on each side of a Qwen parameter, tries JSON decoding as before, and preserves
the remaining plain string verbatim. Other tool formats and their shared
coercer are unchanged. This assumes the Qwen template's documented LF framing;
it does not infer arbitrary indentation or restore bytes already lost in an
API response.

Validation completed without modifying the service:

- The running parser reproduced the missing greeting newline with synthetic XML.
- The exact patch applies with `git apply --check` to the inspected checkout.
- The original source fails the checker; a disposable copy with this exact
  patch passes all ten cases: newline, indentation/tab, spaces, empty string,
  object, boolean, number, array, null and a quoted JSON string.

Deployment evidence:

- Pre-restart router state: zero active/waiting requests, no switch in progress.
- Rollback copy: `/tmp/caverno-qwen-deploy.8b8ExO/qwen3_coder.py.before` on the
  inference host. Preserve it while the repair is in use; system temporary
  storage is not a permanent backup.
- Original source SHA-256:
  `96577cf069dae5e1b4045e71d44fd7eff1579617683a51dbd0a2284768616883`.
- Deployed source SHA-256:
  `cb54a4dd00076a276bf5048ca4f88c6609b6fd5530176a154e457a205b53e34b`.
- All ten cases passed against the deployed source before restart.
- The supervisor returned the same `qwen3.8-27b-exl3` target; the native model
  endpoint reported `qwen3.8-exl3-5.0bpw`. Listener PID changed from 2110137 to
  2519623; the control process remained 1950482.
- `farm_unattended_live_canary.Pw8ZFI` passed its test, summary and independent
  native evidence gate with unchanged acceptance. Its captured HTTP write
  content included the required trailing newline, and native verification
  passed on the initial implementation without a repair turn.

For rollback, first check that the deployed source still matches the hash
above and the shared router is idle; preserve any later changes before
restoring the scoped backup and restarting through the existing supervisor.
This repository records the deployment; no upstream Git commit or push was made.

The checker loads only parser source with stubbed logger/tool containers; it
does not import the inference runtime or load a model:

```bash
python3 tool/patches/tabby_qwen_whitespace_check.py \
  /path/to/tabbyAPI/endpoints/OAI/utils/toolcall_formats/qwen3_coder.py \
  /path/to/tabbyAPI/endpoints/OAI/utils/toolcall_formats/common.py
```
