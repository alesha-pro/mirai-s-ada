"""Greedy identity on LONG prompts (the paths that only prompt-sized batches take: the trellis long-input GEMM, the
tensor-core attention with the packed mask). Three prompts of ~0.6k / 2.4k / 9k tokens, 64 greedy tokens each,
thinking off, cache off. Dump one configuration, compare another against it (same engine or not).

    python bench/long_identity.py --base http://127.0.0.1:18081 --dump artifacts/long-f16.json
    python bench/long_identity.py --base http://127.0.0.1:18081 --against artifacts/long-f16.json
"""
import argparse
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]


def prompts():
    out = []
    for n_items, tag in ((75, "short"), (300, "mid"), (1100, "long")):
        body = " ".join(f"item{i} value{(i * 7) % 97} note" for i in range(n_items))
        out.append((tag, f"The notes below are a ledger. Summarize them in two sentences, then list the three most frequent values.\n\n{body}"))
    return out


def complete(base, key, prompt, n=64):
    body = {"model": "x", "messages": [{"role": "user", "content": prompt}], "max_tokens": n, "temperature": 0,
            "top_k": 1, "seed": 1, "stream": False, "cache_prompt": False, "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=1800).read())
    t = r.get("timings") or {}
    return {"text": r["choices"][0]["message"].get("content") or "", "prompt_n": t.get("prompt_n"),
            "pps": t.get("prompt_per_second"), "tps": t.get("predicted_per_second")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--key-file", default=str(ROOT / "artifacts" / "api_key.txt"))
    ap.add_argument("--dump", default="")
    ap.add_argument("--against", default="")
    a = ap.parse_args()
    key = open(a.key_file).read().strip()
    ref = json.load(open(a.against, encoding="utf-8")) if a.against else None
    out = []
    same = 0
    for i, (tag, p) in enumerate(prompts()):
        r = complete(a.base, key, p)
        out.append(r)
        line = f"{tag:5s} prompt {r['prompt_n']} tok at {r['pps']:.0f} tok/s, decode {r['tps']:.1f}"
        if ref:
            ok = ref[i]["text"] == r["text"]
            same += ok
            div = next((k for k, (x, y) in enumerate(zip(ref[i]["text"], r["text"])) if x != y), min(len(ref[i]["text"]), len(r["text"])))
            line = ("SAME " if ok else f"DIFF at char {div} ") + line
        print(line)
    if ref:
        print(f"{same} of {len(out)} identical")
    if a.dump:
        json.dump(out, open(a.dump, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("dumped", a.dump)


if __name__ == "__main__":
    main()
