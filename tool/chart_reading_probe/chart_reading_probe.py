#!/usr/bin/env python3
"""Measure whether a vision model can read the charts in a real PDF.

Caverno currently extracts a PDF's text layer and sends that. Reading a graph
needs the page as an image instead, and everything that would take -- a
rasterizer, multi-image messages, page selection -- is wasted work if the model
cannot read a chart once it has one. This tool answers that question before any
of it is built.

It renders the pages you name at several widths, asks graded questions about
them over ``/v1/chat/completions``, and prints how many each width got right.

Two things it does deliberately:

  - **A no-image control arm.** Chart questions are guessable ("which line is
    highest?"), so every question is also asked with no image attached. A width
    only counts as read when it beats its own control; the vision probe in the
    Live LLM diagnostic learned this the hard way.
  - **Several widths.** The diagnostic's quadrant probe scored a vision-capable
    model 0/3 at 64px and 3/3 at 256px over the same endpoint and payload.
    Resolution is a property of the harness, not the model, so a single width
    cannot tell you which one you measured.

Usage:

    python3 tool/chart_reading_probe/chart_reading_probe.py \\
        --pdf report.pdf --spec questions.json

    # questions.json
    {
      "questions": [
        {"page": 4, "ask": "What is the 2023 value of the Alpha series?",
         "expect": ["1200", "1,200"]},
        {"page": 4, "ask": "Which series ends highest?", "expect": ["Beta"]}
      ]
    }

The endpoint defaults to ``$CAVERNO_LLM_BASE_URL`` (same variable the live
canaries use), then ``http://localhost:1234/v1``.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

RENDERER = Path(__file__).with_name("render_pdf_page.swift")
DEFAULT_WIDTHS = (800, 1500, 2200)


class ProbeError(RuntimeError):
    pass


def render_page(pdf: Path, page: int, width: int, out: Path) -> tuple[int, int]:
    """Rasterizes one page, returning the pixel size actually produced."""
    if sys.platform != "darwin":
        raise ProbeError(
            "page rendering uses PDFKit and only runs on macOS; render the "
            "pages elsewhere and point --spec at them"
        )
    try:
        completed = subprocess.run(
            ["swift", str(RENDERER), str(pdf), str(page), str(width), str(out)],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError as error:
        raise ProbeError("swift is not on PATH; install the Xcode tools") from error
    except subprocess.CalledProcessError as error:
        raise ProbeError(f"page {page} at {width}px: {error.stderr.strip()}") from error
    rendered_width, rendered_height, _pages = completed.stdout.split()
    return int(rendered_width), int(rendered_height)


def ask(
    base_url: str,
    model: str,
    api_key: str,
    question: str,
    image: Path | None,
    timeout: float,
) -> str:
    """One chat/completions turn, with or without the page image attached."""
    content: list[dict] | str
    if image is None:
        content = question
    else:
        encoded = base64.b64encode(image.read_bytes()).decode("ascii")
        content = [
            {"type": "text", "text": question},
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/png;base64,{encoded}"},
            },
        ]
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        # Answers are graded by substring, so keep them short and repeatable.
        "temperature": 0,
        "max_tokens": 200,
    }
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:300]
        raise ProbeError(f"HTTP {error.code}: {detail}") from error
    except OSError as error:
        raise ProbeError(f"request failed: {error}") from error
    try:
        return body["choices"][0]["message"]["content"] or ""
    except (KeyError, IndexError, TypeError) as error:
        raise ProbeError(f"unexpected response shape: {body}") from error


def _normalize(text: str) -> str:
    """Folds away the differences grading should not care about."""
    lowered = text.lower().replace(",", "").replace("、", "")
    return re.sub(r"\s+", " ", lowered).strip()


def graded(answer: str, expected: list[str]) -> bool:
    """Whether any accepted answer appears in what the model said."""
    normalized = _normalize(answer)
    return any(_normalize(candidate) in normalized for candidate in expected)


def load_spec(path: Path) -> list[dict]:
    spec = json.loads(path.read_text())
    questions = spec.get("questions")
    if not questions:
        raise ProbeError(f"{path} has no 'questions'")
    for index, question in enumerate(questions):
        missing = {"page", "ask", "expect"} - question.keys()
        if missing:
            raise ProbeError(f"question {index} is missing {sorted(missing)}")
        if not isinstance(question["expect"], list) or not question["expect"]:
            raise ProbeError(f"question {index}: 'expect' must be a non-empty list")
    return questions


def run(args: argparse.Namespace) -> int:
    questions = load_spec(Path(args.spec))
    pdf = Path(args.pdf)
    if not pdf.exists():
        raise ProbeError(f"{pdf} does not exist")

    # The control arm does not depend on the image, so it is asked once per
    # question rather than once per width.
    control: dict[int, bool] = {}
    print("no-image control arm")
    for index, question in enumerate(questions):
        answer = ask(
            args.base_url, args.model, args.api_key, question["ask"], None, args.timeout
        )
        control[index] = graded(answer, question["expect"])
        print(f"  q{index + 1} p{question['page']:>3}  "
              f"{'HIT ' if control[index] else 'miss'}  {answer.strip()[:90]}")
    control_hits = sum(control.values())
    print(f"  control: {control_hits}/{len(questions)} guessable without the page\n")

    rows = []
    with tempfile.TemporaryDirectory(prefix="chart_probe_") as workspace:
        for width in args.widths:
            hits = 0
            print(f"width {width}px")
            for index, question in enumerate(questions):
                page = question["page"]
                image = Path(workspace) / f"p{page}_w{width}.png"
                if not image.exists():
                    size = render_page(pdf, page, width, image)
                    rendered = f"{size[0]}x{size[1]}"
                else:
                    rendered = "cached"
                answer = ask(
                    args.base_url,
                    args.model,
                    args.api_key,
                    question["ask"],
                    image,
                    args.timeout,
                )
                correct = graded(answer, question["expect"])
                hits += correct
                marker = "PASS" if correct else "fail"
                if correct and control[index]:
                    marker = "PASS?"  # the control got it too; not evidence
                print(
                    f"  q{index + 1} p{page:>3} {rendered:>10} {marker:<5} "
                    f"{answer.strip()[:90]}"
                )
                time.sleep(args.pause)
            rows.append((width, hits))
            print(f"  {width}px: {hits}/{len(questions)}\n")

    print("summary")
    print(f"  control (no image)  {control_hits}/{len(questions)}")
    for width, hits in rows:
        verdict = "reads the chart" if hits > control_hits else "no better than blind"
        print(f"  {width:>5}px            {hits}/{len(questions)}  {verdict}")
    best = max(rows, key=lambda row: row[1]) if rows else None
    if best and best[1] <= control_hits:
        print(
            "\nNo width beat the control arm. Either the model does not read "
            "charts, or the questions are answerable from the prompt alone -- "
            "check the control answers above before concluding the former."
        )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pdf", required=True, help="PDF holding the charts")
    parser.add_argument("--spec", required=True, help="JSON file of graded questions")
    parser.add_argument(
        "--widths",
        default=",".join(str(width) for width in DEFAULT_WIDTHS),
        help=f"comma-separated pixel widths (default {DEFAULT_WIDTHS})",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("CAVERNO_LLM_BASE_URL", "http://localhost:1234/v1"),
        help="OpenAI-compatible base URL, ending in /v1",
    )
    parser.add_argument(
        "--model", default=os.environ.get("CAVERNO_LLM_MODEL", "qwen3.8-27b-vision")
    )
    parser.add_argument("--api-key", default=os.environ.get("CAVERNO_LLM_API_KEY", "no-key"))
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument(
        "--pause",
        type=float,
        default=0.0,
        help="seconds between requests, for a shared endpoint",
    )
    args = parser.parse_args()
    args.widths = [int(width) for width in args.widths.split(",") if width.strip()]
    if not args.widths:
        parser.error("--widths needs at least one width")

    try:
        return run(args)
    except ProbeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
