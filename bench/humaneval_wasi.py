"""OpenAI HumanEval pass@1 against a running llama-server, scored inside the WASI sandbox.

Vendored from bonsai-ada-surgery's bench/humaneval_run.py (2026-10-05) with one change that matters: every
completion is executed by layer/wasi-python/sandbox.py (CPython 3.12 on WASI: no host files, network or
processes, memory and time capped), never by a host subprocess. The dataset and the tests are openai/human-eval.

Default arm is thinking-off and temperature 0. Killy's published HumanEval
column stayed near 15 because a short generation cap died inside <think>
before any code. This runner asks for the function, strips the prompt back off
when the model echoes it, and scores the official tests.

  python bench/humaneval_run.py --limit 8
  python bench/humaneval_run.py --arm medium --max-tokens 20480
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def read_problems(path: str) -> list[dict]:
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def extract_code(text: str, entry_point: str) -> str:
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<\|.*?\|>", "", text)
    fences = re.findall(r"```(?:python|py)?\s*([\s\S]*?)```", text, flags=re.IGNORECASE)
    chosen = ""
    for fence in fences:
        if f"def {entry_point}" in fence or entry_point in fence:
            chosen = fence
            break
    if not chosen and fences:
        chosen = fences[0]
    if not chosen:
        idx = text.find(f"def {entry_point}")
        chosen = text[idx:] if idx >= 0 else text
    lines = chosen.replace("\r\n", "\n").split("\n")
    kept: list[str] = []
    started = False
    for line in lines:
        stripped = line.strip()
        if not started:
            if not stripped:
                continue
            started = True
        if stripped.startswith("```"):
            break
        # A nested helper is indented. Only a following test harness is a new top-level block.
        if kept and not line.startswith((" ", "\t")) and (
            stripped.startswith("def check")
            or stripped.startswith("if __name__")
            or stripped.startswith("assert ")
            or stripped.startswith("# Test")
        ):
            break
        kept.append(line.rstrip())
    while kept and not kept[-1].strip():
        kept.pop()
    return "\n".join(kept).strip("\n")


def as_completion(prompt: str, code: str) -> tuple[str, str]:
    """Return (mode, completion). mode is 'suffix' or 'whole'."""
    if not code:
        return "whole", ""
    prompt_stripped = prompt.strip("\n")
    if prompt_stripped and prompt_stripped in code:
        suffix = code.split(prompt_stripped, 1)[1]
        if not suffix.startswith("\n"):
            suffix = "\n" + suffix
        return "suffix", suffix
    if code.startswith((" ", "\t")):
        return "suffix", "\n" + code
    return "whole", code if code.endswith("\n") else code + "\n"


def prompt_imports(prompt: str) -> str:
    lines: list[str] = []
    for line in prompt.splitlines():
        if line.startswith(("import ", "from ")):
            lines.append(line)
        elif line.strip() == "":
            continue
        else:
            break
    return "\n".join(lines)


def prompt_head(prompt: str, entry_point: str) -> str:
    """Imports and any helper already defined above the function under test."""
    lines = prompt.splitlines()
    cut = len(lines)
    for index, line in enumerate(lines):
        if line.startswith(f"def {entry_point}"):
            cut = index
            break
    return "\n".join(lines[:cut]).strip("\n")


def build_program(problem: dict, code: str) -> str:
    mode, completion = as_completion(problem["prompt"], code)
    test = problem["test"]
    entry = problem["entry_point"]
    tail = f"\n{test}\ncheck({entry})\n"
    if mode == "suffix":
        return problem["prompt"] + completion + tail
    # Rewritten function: keep the prompt's imports and helpers (poly, encode_cyclic).
    head = prompt_head(problem["prompt"], entry)
    if head and head not in completion:
        completion = head + "\n\n" + completion
    return completion + tail


HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "layer", "wasi-python"))
import sandbox  # noqa: E402


def run_program(program: str, timeout: float) -> str:
    """Run the program + official tests inside the WASI sandbox; never on the host."""
    res = sandbox.run({"check.py": program}, ["check.py"], timeout=timeout, mem_mb=256)
    if res["timed_out"]:
        return "timed out"
    if res["exit_code"] == 0:
        return "passed"
    err = (res["stderr"] or res["stdout"] or b"").decode("utf-8", "replace").strip().splitlines()
    tail = err[-1] if err else f"exit {res['exit_code']}"
    return "failed: " + tail[:240]


def chat(base: str, key: str, prompt: str, arm: str, max_tokens: int, timeout: float,
         temp: float = 0.0, effort: str = "") -> dict:
    # arm "app": what a chat app or harness sends. No chat_template_kwargs, the OpenAI top-level
    # reasoning_effort field if --effort is given, and the server's own sampling unless --temp >= 0.
    # HE_KW_EFFORT overrides the template's reasoning_effort word in the thinking arms (e.g. low); the server's
    # harness-proofing must allow it (MIRAI_EFFORT_ALLOWED), otherwise it is normalized back to medium.
    kw_effort = os.environ.get("HE_KW_EFFORT", "medium")
    kwargs = None
    if arm == "off":
        kwargs = {"enable_thinking": False, "reasoning_effort": kw_effort}
    elif arm == "medium":
        kwargs = {"enable_thinking": True, "reasoning_effort": kw_effort}
    elif arm != "app":
        raise SystemExit(f"unknown arm {arm}")
    user = (
        "Complete this Python function so it passes its docstring examples. "
        "Reply with one python code block containing only the function. "
        "Do not write tests.\n\n"
        + prompt
    )
    body = {
        "model": "mirai-s-27b",
        "messages": [{"role": "user", "content": user}],
        "max_tokens": max_tokens,
    }
    if kwargs is not None:
        body["chat_template_kwargs"] = kwargs
    if effort:
        body["reasoning_effort"] = effort
    if temp >= 0:
        body["temperature"] = temp
        if temp == 0:
            body["top_p"] = 1
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key
    req = urllib.request.Request(
        base.rstrip("/") + "/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers=headers,
    )
    started = time.time()
    raw = urllib.request.urlopen(req, timeout=timeout).read()
    out = json.loads(raw)
    choice = (out.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content = message.get("content") or ""
    reasoning = message.get("reasoning_content") or message.get("reasoning") or ""
    usage = out.get("usage") or {}
    return {
        "content": content,
        "reasoning_n": len(reasoning),
        "finish": choice.get("finish_reason"),
        "completion_tokens": usage.get("completion_tokens", 0),
        "seconds": round(time.time() - started, 1),
    }


def rescore(args: argparse.Namespace) -> None:
    problems = {item["task_id"]: item for item in read_problems(args.problems)}
    saved = [json.loads(line) for line in open(args.rescore, encoding="utf-8") if line.strip()]
    if args.limit > 0:
        saved = saved[: args.limit]
    passed = 0
    rows = []
    for index, sample in enumerate(saved, start=1):
        problem = problems[sample["task_id"]]
        code = extract_code(sample.get("content") or "", problem["entry_point"])
        mode, _completion = as_completion(problem["prompt"], code)
        result = run_program(build_program(problem, code), args.timeout) if code else "failed: empty"
        ok = result == "passed"
        passed += int(ok)
        rows.append({"task_id": sample["task_id"], "passed": ok, "result": result, "mode": mode})
        if not ok:
            print(f"{index:3} {sample['task_id']:<16} FAIL {result[:100]}", flush=True)
    print(
        f"\nrescore pass@1 {round(100.0 * passed / len(saved), 2)}%  ({passed}/{len(saved)})",
        flush=True,
    )
    out_path = os.path.join(os.path.dirname(args.rescore), "rescore.json")
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump({"passed": passed, "n": len(saved), "rows": rows}, handle, indent=2)
    print(f"wrote {out_path}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:18080", help="the inner llama-server (raw model); :8080 is the layer")
    parser.add_argument("--key-file", default=os.path.join(ROOT, "artifacts", "api_key.txt"))
    parser.add_argument(
        "--problems",
        default=os.path.join(os.environ.get("TEMP", "."), "human-eval", "data", "HumanEval.jsonl.gz"),
    )
    parser.add_argument("--arm", choices=("off", "medium", "app"), default="off")
    parser.add_argument("--temp", type=float, default=0.0, help="request temperature; < 0 = server sampling (Killy's plates: the model's own)")
    parser.add_argument("--effort", default="", help="top-level reasoning_effort to send (e.g. high, as Cline/Kilo/Open WebUI do)")
    parser.add_argument("--max-tokens", type=int, default=0)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--timeout", type=float, default=8.0)
    parser.add_argument("--request-timeout", type=float, default=900.0)
    parser.add_argument("--out", default="")
    parser.add_argument("--rescore", default="", help="samples.jsonl to rescore without calling the server")
    args = parser.parse_args()
    if args.max_tokens <= 0:
        args.max_tokens = 1024 if args.arm == "off" else 20480

    if args.rescore:
        rescore(args)
        return

    key = ""
    if args.key_file and os.path.isfile(args.key_file):
        key = open(args.key_file, encoding="utf-8").read().strip()
    problems = read_problems(args.problems)
    if args.limit > 0:
        problems = problems[: args.limit]

    out_dir = args.out or os.path.join(ROOT, "bench", "humaneval", args.arm)
    os.makedirs(out_dir, exist_ok=True)
    samples_path = os.path.join(out_dir, "samples.jsonl")
    summary_path = os.path.join(out_dir, "summary.json")

    passed = 0
    rows = []
    started = time.time()
    with open(samples_path, "w", encoding="utf-8") as samples:
        for index, problem in enumerate(problems, start=1):
            task = problem["task_id"]
            try:
                gen = chat(
                    args.base,
                    key,
                    problem["prompt"],
                    args.arm,
                    args.max_tokens,
                    args.request_timeout,
                    args.temp,
                    args.effort,
                )
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
                gen = {
                    "content": "",
                    "reasoning_n": 0,
                    "finish": "error",
                    "completion_tokens": 0,
                    "seconds": 0,
                    "error": str(exc),
                }
            code = extract_code(gen["content"], problem["entry_point"])
            mode, _completion = as_completion(problem["prompt"], code)
            result = run_program(build_program(problem, code), args.timeout) if code else "failed: empty"
            ok = result == "passed"
            passed += int(ok)
            row = {
                "task_id": task,
                "passed": ok,
                "result": result,
                "mode": mode,
                "finish": gen.get("finish"),
                "completion_tokens": gen.get("completion_tokens", 0),
                "reasoning_n": gen.get("reasoning_n", 0),
                "seconds": gen.get("seconds", 0),
                "code_n": len(code),
                "content_head": (gen.get("content") or "")[:180].replace("\n", "\\n"),
            }
            if gen.get("error"):
                row["error"] = gen["error"]
            rows.append(row)
            samples.write(json.dumps({"task_id": task, "code": code, "content": gen.get("content", ""), "result": result}) + "\n")
            samples.flush()
            print(
                f"{index:3}/{len(problems)} {task:<16} {'PASS' if ok else 'FAIL'} "
                f"{result[:80]:<80} tok={row['completion_tokens']} {row['seconds']}s",
                flush=True,
            )

    elapsed = round(time.time() - started, 1)
    summary = {
        "arm": args.arm,
        "n": len(problems),
        "passed": passed,
        "pass_at_1": round(100.0 * passed / len(problems), 2) if problems else 0,
        "temperature": args.temp if args.temp >= 0 else "server",
        "effort": args.effort or None,
        "max_tokens": args.max_tokens,
        "seconds": elapsed,
    }
    with open(summary_path, "w", encoding="utf-8") as handle:
        json.dump({"summary": summary, "rows": rows}, handle, indent=2)
    print(
        f"\npass@1 {summary['pass_at_1']}%  ({passed}/{len(problems)})  "
        f"arm={args.arm} effort={args.effort or '-'} temp={args.temp if args.temp >= 0 else 'server'} max_tokens={args.max_tokens}  {elapsed}s",
        flush=True,
    )
    print(f"wrote {summary_path}", flush=True)


if __name__ == "__main__":
    main()
