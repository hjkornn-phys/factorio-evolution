#!/usr/bin/env python3
"""Grade e143's runs from out/<variant>.csv (windows of 1,000; seed events
at the tick the harness saw them, checked every 60 ticks).

    python3 experiments/e143-selection/analyze.py

Each machine's lineage (growth:type: 1 light; 2 heavy in the arm sel, the
twin in the arm neu) and when it was built (growth:done); each birth's
asker (growth:by, the asker's index in the order built; the two founders,
both of lineage 2, ask for nothing). For each run: the machines built by
lineage, light's share, the births, the mutant births (lineage not the
asker's), and the tick the last site filled (the 224th built; 0: never).
For each arm: light's share (mean, least, most) and the median fill.
Then the test registered: the one-sided exact Mann-Whitney p that light's
share is larger in sel than in neu (every split of the 20 shares into two
arms of 10, the fraction with U at least the observed; ties count half).
"""
import csv
import itertools
import os
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
SITES = 224


def grade(v):
    ev = {}
    for r in csv.DictReader(open(os.path.join(HERE, "out", f"{v}.csv"))):
        p = r["sink"].split(":")
        if p[0] == "growth" and len(p) == 3 and p[1] in ("type", "done", "by"):
            ev.setdefault(int(p[2]), {})[p[1]] = int(r["count"])
    order = [i for _, i in sorted((ev[i]["done"], i) for i in ev if "done" in ev[i])]
    lin = [ev[i]["type"] for i in order]
    births = [i for i in ev if "by" in ev[i] and ev[i]["by"] < len(order)]
    mutants = sum(1 for i in births if ev[i]["type"] != lin[ev[i]["by"]])
    done = sorted(ev[i]["done"] for i in order)
    fill = done[SITES - 1] if len(done) >= SITES else 0
    n1 = sum(1 for x in lin if x == 1)
    share = n1 / len(lin)
    return share, fill, f"{v} {n1} {len(lin) - n1} {len(lin)} {share:.3f} {len(births)} {mutants} {fill}"


def u(a, b):
    return sum((x > y) + 0.5 * (x == y) for x in a for y in b)


def main():
    vs = open(os.path.join(HERE, "variants.txt")).read().split()
    a = ["runs: run, light, other, machines, light share, births, mutant births, filled at"]
    arms = {}
    for v in vs:
        share, fill, line = grade(v)
        a.append(line)
        arms.setdefault(v.split("-")[0], []).append((share, fill))
    b = ["arms: arm, runs, light share mean, least, most, filled (median), filled runs"]
    for arm, xs in arms.items():
        sh = [x[0] for x in xs]
        fl = [x[1] for x in xs if x[1]]
        b.append(f"{arm} {len(xs)} {statistics.mean(sh):.3f} {min(sh):.3f} {max(sh):.3f} "
                 f"{int(statistics.median(fl)) if fl else 0} {len(fl)}")
    sel, neu = [x[0] for x in arms["sel"]], [x[0] for x in arms["neu"]]
    obs = u(sel, neu)
    allv = sel + neu
    hits = tot = 0
    for comb in itertools.combinations(range(len(allv)), len(sel)):
        c = set(comb)
        hits += u([allv[i] for i in c], [allv[i] for i in range(len(allv)) if i not in c]) >= obs
        tot += 1
    t = ["test: U, of, p"]
    t.append(f"sel>neu {obs:g} {len(sel) * len(neu)} {hits / tot:.4f}")
    text = "\n".join(a + [""] + b + [""] + t)
    os.makedirs(os.path.join(HERE, "run"), exist_ok=True)
    open(os.path.join(HERE, "run", "rounds.txt"), "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
