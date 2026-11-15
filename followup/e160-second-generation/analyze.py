#!/usr/bin/env python3
"""Grade e160 (the roboport and the loader in the kit, a second generation) from
out/<run>.csv.

    python3 experiments/e160-second-generation/analyze.py

Per run: the first window of 200 ticks in which the parent's roboport read 2
construction robots and the most it ever read; "child built at" (the first window
with no ghost in the child's area); "grandchild's first part at" (the first window, after
its seed stood there, with fewer ghosts in the grandchild's area than the seed laid;
0: never); "grandchild built at" (the first such window with no ghost there; 0:
never); the child's and the grandchild's crafted counts at the end. A probe reads -2
once its entity is removed, so the most read is the most while the parent stood.
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROBOT = "construction-robot"


def main():
    out = ["gens: run, roboport reads 2 from, most robots read, child built at, grandchild's first part at, grandchild built at, child crafted, grandchild crafted"]
    for name in open(os.path.join(HERE, "variants.txt")).read().split():
        by_t = {}
        for r in csv.DictReader(open(os.path.join(HERE, "out", name + ".csv"))):
            by_t.setdefault(int(r["tick"]), {})[r["sink"]] = int(r["count"])
        two = most = child = first = grand = laid = 0
        for t in sorted(by_t):
            row = by_t[t]
            rp = row.get(f"probe:rp:{ROBOT}", 0)
            most = max(most, rp)
            two = two or (t if rp == 2 else 0)
            child = child or (t if row["ghosts:child"] == 0 else 0)
            g = row["ghosts:grand"]
            laid = max(laid, g)
            first = first or (t if g < laid else 0)
            grand = grand or (t if laid and g == 0 else 0)
        end = by_t[max(by_t)]
        out.append(f"{name}  {two}  {most}  {child}  {first}  {grand}  {end.get('watch:cM:crafted', 0)}  {end.get('watch:gM:crafted', 0)}")
    text = "\n".join(out)
    os.makedirs(os.path.join(HERE, "run"), exist_ok=True)
    open(os.path.join(HERE, "run", "rounds.txt"), "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
