"""List a GGUF's tensors (name, dims, ggml type id) without gguf-py, so Mirai's private type ids (90-93) print too.
    python bench/gguf_tensors.py models/Qwen3.8-27B-S-mirai.gguf [name-substring ...]
With no filter: a per-type summary plus the non-block tensors. With filters: every tensor whose name contains one.
"""
import struct
import sys
from collections import Counter, defaultdict

TYPE_NAMES = {0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 6: "Q5_0", 7: "Q5_1", 8: "Q8_0", 9: "Q8_1", 10: "Q2_K", 11: "Q3_K",
              12: "Q4_K", 13: "Q5_K", 14: "Q6_K", 15: "Q8_K", 16: "IQ2_XXS", 17: "IQ2_XS", 18: "IQ3_XXS", 19: "IQ1_S",
              20: "IQ4_NL", 21: "IQ3_S", 22: "IQ2_S", 23: "IQ4_XS", 24: "I8", 25: "I16", 26: "I32", 27: "I64", 28: "F64",
              29: "IQ1_M", 30: "BF16", 34: "TQ1_0", 35: "TQ2_0", 39: "MXFP4", 90: "MS_V4T8", 91: "MS_V2T4", 92: "MS_V2T6",
              93: "MS_I3", 142: "PQ2_0", 143: "PTQ1_0"}


def read_str(f):
    (n,) = struct.unpack("<Q", f.read(8))
    return f.read(n).decode("utf-8", "replace")


def skip_value(f, t):
    sizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}
    if t == 8:
        read_str(f)
    elif t == 9:
        (et,) = struct.unpack("<I", f.read(4))
        (n,) = struct.unpack("<Q", f.read(8))
        for _ in range(n):
            skip_value(f, et)
    else:
        f.read(sizes[t])


def main():
    path, filters = sys.argv[1], [s.lower() for s in sys.argv[2:]]
    with open(path, "rb") as f:
        magic, version, n_tensors, n_kv = struct.unpack("<IIQQ", f.read(24))
        assert magic == 0x46554747, "not a GGUF"
        for _ in range(n_kv):
            read_str(f)
            (t,) = struct.unpack("<I", f.read(4))
            skip_value(f, t)
        rows = []
        for _ in range(n_tensors):
            name = read_str(f)
            (nd,) = struct.unpack("<I", f.read(4))
            dims = struct.unpack("<" + "Q" * nd, f.read(8 * nd))
            t, off = struct.unpack("<IQ", f.read(12))
            rows.append((name, dims, t, off))
    tn = lambda t: TYPE_NAMES.get(t, f"type{t}")
    if filters:
        for name, dims, t, _ in rows:
            if any(s in name.lower() for s in filters):
                print(f"{name:48s} {'x'.join(map(str, dims)):>18s}  {tn(t)}")
        return
    by_type = Counter(tn(t) for _, _, t, _ in rows)
    print("tensors by type:", dict(by_type.most_common()))
    kinds = defaultdict(Counter)
    for name, dims, t, _ in rows:
        if name.startswith("blk."):
            kinds[".".join(name.split(".")[2:])][tn(t)] += 1
        else:
            print(f"{name:48s} {'x'.join(map(str, dims)):>18s}  {tn(t)}")
    print("per-layer tensor kinds (type: count):")
    for k, c in sorted(kinds.items()):
        print(f"  {k:36s} {dict(c)}")


if __name__ == "__main__":
    main()
