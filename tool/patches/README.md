# TabbyAPI Qwen Parameter Whitespace Repair

`tabby_qwen_parameter_whitespace.patch` targets
`endpoints/OAI/utils/toolcall_formats/qwen3_coder.py` in the running EXL3
backend checkout at `/mnt/storage1/models/tabbyAPI` on `192.168.100.241`.
It was prepared and checked on 2026-10-04; it has **not been deployed**.

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

After explicitly authorizing a server change, preserve a rollback copy and
review current checkout changes before applying the patch. Run the checker
against the modified source before restarting the shared backend, then rerun
the unchanged unattended Farm canary through the managed relay. Parser tests
alone do not establish deployed behavior or live Farm readiness.

The checker loads only parser source with stubbed logger/tool containers; it
does not import the inference runtime or load a model:

```bash
python3 tool/patches/tabby_qwen_whitespace_check.py \
  /path/to/tabbyAPI/endpoints/OAI/utils/toolcall_formats/qwen3_coder.py \
  /path/to/tabbyAPI/endpoints/OAI/utils/toolcall_formats/common.py
```
