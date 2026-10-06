"""Served receipt from llama-server's own per-task timing lines: decode tok/s, prompt tok/s, draft acceptance and
mean draft length over every request a log covers (for example the whole of ML2 on the product serve).

    python bench/served_receipt.py logs/product.log [--since "HH:MM"] [--md receipts/mirai-port/served-ml2.md]

Reads "prompt eval time", "eval time" and "draft acceptance" lines per task id; prints distributions (median,
p10, p90) overall and by generation length bucket. Timestamps in the log are hh.mm.ss since server start.
"""
import argparse
import re
import statistics
from collections import defaultdict

ANSI = re.compile(r"\x1b\[[0-9;]*m")
TASK = re.compile(r"task (\d+) \|")
PROMPT = re.compile(r"prompt eval time =\s*([\d.]+) ms /\s*(\d+) tokens.*?([\d.]+) tokens per second")
EVAL = re.compile(r"\|\s+eval time =\s*([\d.]+) ms /\s*(\d+) tokens.*?([\d.]+) tokens per second")
ACC = re.compile(r"draft acceptance = ([\d.]+) \(\s*(\d+) accepted /\s*(\d+) generated\), mean len =\s*([\d.]+)")


def pct(xs, p):
    xs = sorted(xs)
    if not xs:
        return float("nan")
    k = (len(xs) - 1) * p
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def fmt(xs):
    return f"n={len(xs)} median {pct(xs, .5):.1f} p10 {pct(xs, .1):.1f} p90 {pct(xs, .9):.1f}" if xs else "n=0"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--md", default="")
    a = ap.parse_args()
    tasks = defaultdict(dict)
    for line in open(a.log, encoding="utf-8", errors="replace"):
        line = ANSI.sub("", line)
        m = TASK.search(line)
        if not m:
            continue
        t = tasks[int(m.group(1))]
        if (x := PROMPT.search(line)):
            t["p_ms"], t["p_n"], t["p_tps"] = float(x.group(1)), int(x.group(2)), float(x.group(3))
        elif (x := EVAL.search(line)):
            t["e_ms"], t["e_n"], t["e_tps"] = float(x.group(1)), int(x.group(2)), float(x.group(3))
        elif (x := ACC.search(line)):
            t["acc"], t["acc_a"], t["acc_g"], t["mean_len"] = float(x.group(1)), int(x.group(2)), int(x.group(3)), float(x.group(4))
    done = [t for t in tasks.values() if "e_tps" in t and t.get("e_n", 0) >= 16]
    out = []
    out.append(f"requests with >= 16 generated tokens: {len(done)} (of {len(tasks)} tasks seen)")
    out.append(f"decode tok/s      : {fmt([t['e_tps'] for t in done])}")
    out.append(f"prompt tok/s      : {fmt([t['p_tps'] for t in done if t.get('p_n', 0) >= 256])} (prompts >= 256 tokens)")
    acc = [t for t in done if "acc" in t and t["acc_g"] > 0]
    out.append(f"draft acceptance  : {fmt([100 * t['acc'] for t in acc])} %   mean draft len {fmt([t['mean_len'] for t in acc])}")
    tot_a, tot_g = sum(t["acc_a"] for t in acc), sum(t["acc_g"] for t in acc)
    if tot_g:
        out.append(f"pooled acceptance : {100 * tot_a / tot_g:.1f} % ({tot_a} / {tot_g} drafted tokens)")
    out.append("by generation length:")
    for lo, hi in [(16, 256), (256, 2048), (2048, 8192), (8192, 10 ** 9)]:
        b = [t for t in done if lo <= t["e_n"] < hi]
        if b:
            out.append(f"  {lo:>5}-{hi if hi < 10**9 else 'inf':<5} tokens: decode {fmt([t['e_tps'] for t in b])}; "
                       f"acceptance {fmt([100 * t['acc'] for t in b if 'acc' in t])} %")
    gen = sum(t["e_n"] for t in done)
    secs = sum(t["e_ms"] for t in done) / 1000
    out.append(f"total generated   : {gen:,} tokens in {secs / 3600:.2f} h of decode time = {gen / secs if secs else 0:.1f} tok/s wall-pooled")
    text = "\n".join(out)
    print(text)
    if a.md:
        with open(a.md, "w", encoding="utf-8") as f:
            f.write(f"# Served receipt from `{a.log}`\n\n```\n{text}\n```\n")


if __name__ == "__main__":
    main()
