#!/usr/bin/env python3
"""Classify why `edit_file` anchors miss, reusing analyze_tool_results parsing.

Roughly a third of all edit_file calls fail with `old_text was not found`
(57 of 155 across the local logs). This asks which kind of mismatch produced
each one, by comparing the attempted `old_text` against the `current_content`
the error returns for files under 4 KB.

Buckets, in the order they are tested:

  verbatim present            -- should be impossible; a canary for this script
  whitespace differs          -- matches once whitespace runs are collapsed
  indentation differs         -- matches once per-line indentation is stripped
  already applied             -- the new_text is in the file; the edit was a repeat
  first line matches, drifted -- anchor start is real, the block below it is not
  absent entirely             -- no part of the anchor is in the file
  no current_content          -- file over 4 KB, so the error returns no content

Kept in tool/ rather than written ad hoc: two throwaway versions of this
analysis produced clean-looking but meaningless results today (see
docs/reread_loop_mechanism_2026-07-21.md), and a script that lives somewhere
can be checked instead of rebuilt.

Usage:  python3 tool/analyze_edit_anchors.py
"""
import importlib.util, json, re, collections, pathlib, sys

spec = importlib.util.spec_from_file_location("air", "tool/analyze_tool_results.py")
air = importlib.util.module_from_spec(spec); spec.loader.exec_module(air)

ARGS = re.compile(r"Arguments: (\{.*\})")
root = air.log_dir()
buckets = collections.Counter()
samples = collections.defaultdict(list)

def norm_ws(s):      return re.sub(r"\s+", " ", s).strip()
def strip_indent(s): return "\n".join(l.strip() for l in s.splitlines())

for path in sorted(root.glob("*/*.jsonl")):
    seen = set()
    for rec in air.iter_records(path):
        for msg in (rec.get("request") or {}).get("messages") or []:
            mid = msg.get("id")
            if mid is None or mid in seen: continue
            seen.add(mid)
            content = msg.get("content")
            if not isinstance(content, str) or "[Tool: edit_file]" not in content: continue
            marks = list(air.TOOL_SECTION.finditer(content))
            for i, m in enumerate(marks):
                if m.group(1) != "edit_file": continue
                end = marks[i+1].start() if i+1 < len(marks) else len(content)
                sec = content[m.end():end]
                cut = sec.find(air.RESULT_MARKER)
                if cut < 0: continue
                payload = sec[cut+len(air.RESULT_MARKER):].strip()
                try: dec = json.loads(payload)
                except ValueError: continue
                if not isinstance(dec, dict) or "not found" not in str(dec.get("error","")): continue
                am = ARGS.search(sec[:cut])
                if not am: 
                    buckets["(args unparsed)"] += 1; continue
                try: args = json.loads(am.group(1))
                except ValueError:
                    buckets["(args unparsed)"] += 1; continue
                old = args.get("old_text") or ""
                new = args.get("new_text") or ""
                cur = dec.get("current_content")
                if not isinstance(cur, str):
                    buckets["no current_content (file >4KB)"] += 1; continue
                if old and old in cur:                      b = "verbatim present (?!)"
                elif old and norm_ws(old) in norm_ws(cur):   b = "whitespace differs"
                elif old and strip_indent(old) in strip_indent(cur): b = "indentation differs"
                elif new and new in cur:                     b = "already applied (new_text present)"
                elif old.splitlines() and old.splitlines()[0].strip() and old.splitlines()[0].strip() in cur:
                    b = "first line matches, block drifted"
                else:                                        b = "absent entirely"
                buckets[b] += 1
                if len(samples[b]) < 2:
                    samples[b].append((path.name[:8], old[:150]))

tot = sum(buckets.values())
print(f"failed edit_file anchors classified: {tot}\n")
for b, c in buckets.most_common():
    print(f"{c:5} ({100*c/tot:4.1f}%)  {b}")
print()
for b in ("already applied (new_text present)", "whitespace differs", "indentation differs", "absent entirely"):
    for sess, s in samples.get(b, [])[:1]:
        print(f"--- {b} [{sess}]\n    {s!r}\n")
