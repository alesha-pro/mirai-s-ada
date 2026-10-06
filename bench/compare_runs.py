"""Line up two suite runs item by item (same plan, same seeds): per-family and per-item outcomes for each arm of each
run, rescues/losses within each run, and what moved between runs.

    python bench/compare_runs.py bench/ML1 bench/ML2 [--arms mirai-raw mirai-layer] [--md receipts/mirai-port/ml1-vs-ml2.md]
"""
import argparse
import json
import os
from collections import OrderedDict, defaultdict


def load(d):
    rows = {}
    for line in open(os.path.join(d, "results.jsonl"), encoding="utf-8"):
        r = json.loads(line)
        rows[(r["family"], r["name"], r["seed"], r["arm"])] = r
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--arms", nargs=2, default=["mirai-raw", "mirai-layer"])
    ap.add_argument("--md", default="")
    args = ap.parse_args()
    A, B = load(args.a), load(args.b)
    raw, lay = args.arms
    items = sorted({k[:3] for k in list(A) + list(B)})
    out = []
    na, nb = os.path.basename(args.a.rstrip("/\\")), os.path.basename(args.b.rstrip("/\\"))
    out.append(f"| family | item | seed | {na} {raw} | {na} {lay} | {nb} {raw} | {nb} {lay} | moved |")
    out.append("| --- | --- | ---: | :---: | :---: | :---: | :---: | --- |")
    fam = defaultdict(lambda: defaultdict(int))
    tok = defaultdict(int)
    for f, n, s in items:
        cells = []
        for run, R in ((na, A), (nb, B)):
            for arm in (raw, lay):
                r = R.get((f, n, s, arm))
                cells.append("-" if r is None else ("pass" if r["ok"] else "fail"))
                if r is not None:
                    fam[(run, arm)][f] += int(r["ok"])
                    fam[(run, arm)]["_n"] += 1
                    tok[(run, arm)] += int(r.get("tokens") or 0)
        moved = []
        if cells[0] != cells[2] and "-" not in (cells[0], cells[2]):
            moved.append(f"{raw}: {cells[0]}->{cells[2]}")
        if cells[1] != cells[3] and "-" not in (cells[1], cells[3]):
            moved.append(f"{lay}: {cells[1]}->{cells[3]}")
        out.append(f"| {f} | {n} | {s} | " + " | ".join(cells) + f" | {'; '.join(moved)} |")
    out.append("")
    out.append("| run / arm | " + " | ".join(sorted({f for f, _, _ in items})) + " | total | tokens |")
    out.append("| --- | " + " | ".join("---:" for _ in {f for f, _, _ in items}) + " | ---: | ---: |")
    for run in (na, nb):
        for arm in (raw, lay):
            c = fam[(run, arm)]
            if not c:
                continue
            fams = sorted({f for f, _, _ in items})
            totals = {f: sum(1 for ff, _, _ in items if ff == f) for f in fams}
            out.append(f"| {run} {arm} | " + " | ".join(f"{c[f]}/{totals[f]}" for f in fams) + f" | {sum(c[f] for f in fams)}/{c['_n']} | {tok[(run, arm)]:,} |")
    for run, R in ((na, A), (nb, B)):
        resc = loss = 0
        for f, n, s in items:
            a, b = R.get((f, n, s, raw)), R.get((f, n, s, lay))
            if a and b:
                resc += int(b["ok"] and not a["ok"])
                loss += int(a["ok"] and not b["ok"])
        out.append(f"\n{run}: rescues {resc}, losses {loss} ({lay} vs {raw})")
    text = "\n".join(out)
    print(text)
    if args.md:
        open(args.md, "w", encoding="utf-8").write(text + "\n")


if __name__ == "__main__":
    main()
