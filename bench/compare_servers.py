"""Same prompts, greedy: dump one server's outputs to JSON, or compare a server against a dump (first divergence).
Two servers cannot share a 12 GB card, so: dump the reference, swap, compare the candidate.

    python bench/compare_servers.py --base http://127.0.0.1:18081 --dump receipts/mirai-port/stock-greedy-nothink.json --n 200
    python bench/compare_servers.py --base http://127.0.0.1:18081 --against receipts/mirai-port/stock-greedy-nothink.json --n 200 [--think]

The reference dumps in receipts/mirai-port were made on alesha-pro's reference fork (2026-10-04, 64k q8 window,
templates/bonsai-template.jinja, reasoning_effort medium).
"""
import argparse
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROMPTS = [
    "Write a Python function that parses an ISO 8601 date string and returns a datetime; include three test cases.",
    "Explain in five sentences why the sky is blue.",
    "List the first 20 prime numbers, comma separated, nothing else.",
    "Translate to French, then give the word count of the French: 'The quick brown fox jumps over the lazy dog near the riverbank at dawn.'",
    "A train leaves at 09:40 and arrives at 14:05 after a 25 minute stop. How long was it moving? Show the arithmetic.",
]


def complete(base, key, prompt, n, think):
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": n, "temperature": 0,
            "top_k": 1, "seed": 1, "stream": False, "cache_prompt": False,
            "chat_template_kwargs": {"enable_thinking": think}}
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
    m = r["choices"][0]["message"]
    t = r.get("timings") or {}
    return {"text": (m.get("reasoning_content") or "") + "\n---\n" + (m.get("content") or ""),
            "tps": t.get("predicted_per_second"), "pps": t.get("prompt_per_second"), "n": r["usage"]["completion_tokens"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--key-file", default=str(ROOT / "artifacts" / "api_key.txt"))
    ap.add_argument("--dump", default="")
    ap.add_argument("--against", default="")
    ap.add_argument("--n", type=int, default=200)
    ap.add_argument("--think", action="store_true")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    out = []
    ref = json.load(open(a.against, encoding="utf-8")) if a.against else None
    for i, p in enumerate(PROMPTS):
        r = complete(a.base, key, p, a.n, a.think)
        out.append(r)
        line = f"{r['tps']:.1f} tok/s ({r['n']} tok) prefill {r['pps']:.0f} | {p[:48]!r}"
        if ref:
            ta, tb = ref[i]["text"], r["text"]
            same = ta == tb
            div = next((k for k, (x, y) in enumerate(zip(ta, tb)) if x != y), min(len(ta), len(tb)))
            line = f"{'SAME ' if same else 'DIFF '} divergence at char {div:5d} of {len(ta)}/{len(tb)} | ref {ref[i]['tps']:.1f} tok/s | " + line
            print(line)
            if not same:
                print("   ref:", repr(ta[max(0, div - 60):div + 80]))
                print("   new:", repr(tb[max(0, div - 60):div + 80]))
        else:
            print(line)
    if a.dump:
        json.dump(out, open(a.dump, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("dumped", a.dump)


if __name__ == "__main__":
    main()
