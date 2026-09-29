#!/usr/bin/env python3
"""Grade e144's runs from out/<variant>.csv (windows of 1,000; seed events
at the tick the harness saw them, checked every 60 ticks).

    python3 experiments/e144-greedy/analyze.py

Each seed's lineage (growth:type: 1 light, 2 greedy), when it was laid
(growth:laid) and built (growth:done), and its asker (growth:by: the
asker's index among the machines in the order built; the founders are
laid by the harness and ask for nothing). For each variant: the machines
at the end by lineage, the births by the asker's lineage, the fifteenth
machine's tick (0: never), the crafts in the last 100,000 ticks, and each
lineage's generation time: for every machine that asked, the ticks from
its being built to its first child's laying (the median, and the count).
Then, over the variants of a pool: greedy's median generation time over
light's. Fixed before the graded runs; checked on e142's out/ (its table
rebuilt exactly, heavy in greedy's column).
"""
import csv
import os
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))


def grade(v):
    rows = list(csv.DictReader(open(os.path.join(HERE, "out", f"{v}.csv"))))
    last = max(int(r["tick"]) for r in rows)
    ev, crafted = {}, {}
    for r in rows:
        k, t, c = r["sink"], int(r["tick"]), int(r["count"])
        p = k.split(":")
        if p[0] == "growth" and len(p) == 3 and p[1] in ("type", "done", "by", "laid"):
            ev.setdefault(int(p[2]), {})[p[1]] = c
        elif k.startswith("watch:m") and k.endswith("M:crafted"):
            crafted.setdefault(p[1], {})[t] = c
    order = [i for _, i in sorted((ev[i]["done"], i) for i in ev if "done" in ev[i])]
    lin = [ev[i]["type"] for i in order]
    done = [ev[i]["done"] for i in order]
    first = {}
    for i in ev:
        if "by" in ev[i] and ev[i]["by"] < len(order):
            a = ev[i]["by"]
            first[a] = min(first.get(a, ev[i]["laid"]), ev[i]["laid"])
    gen = {1: [], 2: []}
    for a, t in first.items():
        gen[lin[a]].append(t - done[a])
    births, mutants = {1: 0, 2: 0}, 0
    for i in ev:
        if "by" in ev[i] and ev[i]["by"] < len(order):
            births[lin[ev[i]["by"]]] += 1
            mutants += ev[i]["type"] != lin[ev[i]["by"]]
    fifteenth = sorted(done)[14] if len(done) >= 15 else 0
    late = 0
    for ts in crafted.values():
        before = [t for t in ts if t <= last - 100000]
        late += ts[max(ts)] - (ts[max(before)] if before else 0)
    n1 = sum(1 for x in lin if x == 1)
    med = {l: int(statistics.median(g)) if g else 0 for l, g in gen.items()}
    line = f"{v} {n1} {len(lin) - n1} {births[1]} {births[2]} {mutants} {fifteenth} {late} " \
           f"{med[1]} {len(gen[1])} {med[2]} {len(gen[2])}"
    return line, gen


def main():
    a = ["colony: run, light machines, greedy machines, light births, greedy births, mutant births, fifteenth at, "
         "crafts in the last 100000, light generation (median), n, greedy generation (median), n"]
    pools = {}
    for v in open(os.path.join(HERE, "variants.txt")).read().split():
        x, g = grade(v)
        a.append(x)
        p = pools.setdefault(v.split("-")[0], {1: [], 2: []})
        for l in g:
            p[l] += g[l]
    b = ["generation: pool, light median, n, greedy median, n, greedy over light"]
    for p, g in pools.items():
        m1 = statistics.median(g[1]) if g[1] else 0
        m2 = statistics.median(g[2]) if g[2] else 0
        b.append(f"{p} {int(m1)} {len(g[1])} {int(m2)} {len(g[2])} {m2 / m1 if m1 else 0:.3f}")
    text = "\n".join(a + [""] + b)
    os.makedirs(os.path.join(HERE, "run"), exist_ok=True)
    open(os.path.join(HERE, "run", "rounds.txt"), "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
