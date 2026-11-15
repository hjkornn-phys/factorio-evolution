#!/usr/bin/env python3
"""Grade e161 (e160 again with the child's and the grandchild's roboports read) from
out/<run>.csv and e160's out/gen.csv.

    python3 experiments/e161-child-roboport/analyze.py

Per run: whether the output with the cp and gp lines dropped is e160's out/gen.csv
byte for byte (1: yes; by e160's SHA-256, recheck running each experiment alone); for the child's roboport: the first window with a network
(a read of 0 or more), the least and the most it read before 290,000 in such
windows, the first window after 290,000 reading 1 and reading 2 (0: never), the
most it read in the run; for the grandchild's: the first window with a network, the
most it read, and its read at the end. -2: not there; -1: no network.
"""
import csv
import hashlib
import os

HERE = os.path.dirname(os.path.abspath(__file__))
E160 = "c3ada59a8404f0eb36d7ce00444625192935a322714250cda8572b33668a19d3"  # shasum -a 256 experiments/e160-second-generation/out/gen.csv (b06284f)
FILL1 = 290000
CP, GP = "probe:cp:construction-robot", "probe:gp:construction-robot"


def main():
    out = ["reads: run, same as e160, child's roboport has a network from, least before 290000, most before 290000, "
           "reads 1 from, reads 2 from, most in the run, grandchild's has a network from, most, at end"]
    for name in open(os.path.join(HERE, "variants.txt")).read().split():
        rows = [tuple(r) for r in csv.reader(open(os.path.join(HERE, "out", name + ".csv")))]
        kept = b"".join(ln for ln in open(os.path.join(HERE, "out", name + ".csv"), "rb")
                        if b"," + CP.encode() + b"," not in ln and b"," + GP.encode() + b"," not in ln)
        differ = int(hashlib.sha256(kept).hexdigest() == E160)
        cp = [(int(t), int(v)) for t, k, v in rows[1:] if k == CP]
        gp = [(int(t), int(v)) for t, k, v in rows[1:] if k == GP]
        first = lambda s, f: next((t for t, v in s if f(t, v)), 0)
        before = [v for t, v in cp if t < FILL1 and v >= 0] or [0]
        out.append(f"{name}  {differ}  {first(cp, lambda t, v: v >= 0)}  {min(before)}  {max(before)}  "
                   f"{first(cp, lambda t, v: t > FILL1 and v == 1)}  {first(cp, lambda t, v: t > FILL1 and v == 2)}  "
                   f"{max(v for _, v in cp)}  {first(gp, lambda t, v: v >= 0)}  {max(v for _, v in gp)}  {gp[-1][1]}")
    text = "\n".join(out)
    os.makedirs(os.path.join(HERE, "run"), exist_ok=True)
    open(os.path.join(HERE, "run", "rounds.txt"), "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
