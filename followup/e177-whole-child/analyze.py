#!/usr/bin/env python3
"""Grade e177 (e176 with the child laid whole when the kit is complete) from out/<run>.csv.

    python3 experiments/e177-whole-child/analyze.py

lay: per run, the window D first reads 1 (0: never), the windows the child was laid (growth:laid:1;
how many layings), the most ghosts before that window, the ghosts in that window, the last
window with a ghost, the first from which none stands (0: one stands at the end), the parent's
crafts then.
child: per run, the child's crafts at the removal and at the end, the first window after the
removal in which its roboport reads 1 and 2 (0: never), the most it reads after the removal,
its refinery's crafts after the removal.
grids: per run, the windows with both accumulators standing, how many with equal ids, the two
ids in the last such window; the child's accumulator's first charge (kJ) when it stands.
power: per run, for the parent's accumulator from FROM to the removal and the child's after it:
lowest, highest, spans of DAY, spans reaching MARK, the longest run at 0 (ticks).
furnaces: per run, each of the child's furnaces' crafts at the removal, and the least.
"""
import csv
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REMOVE = 1100000
DAY, FROM, MARK, W = 25000, 100000, 2500, 200
FURN = ["A1", "A2", "A3", "B1", "B1i", "B2", "C1", "C2", "D1"]


def charge(by, ts, key, a, b):
    v = {t: by[t][key] for t in ts if a < t <= b and key in by[t]}
    if not v:
        return [0, 0, 0, 0, 0]
    spans = range(a, b - DAY + 1, DAY)
    ok = sum(1 for s in spans if max((x for t, x in v.items() if s < t <= s + DAY), default=0) >= MARK)
    run = best = 0
    for t in sorted(v):
        run = run + W if v[t] == 0 else 0
        best = max(best, run)
    return [min(v.values()), max(v.values()), len(spans), ok, best]


def main():
    lay = ["lay: run, D first 1, laid at, layings, most ghosts before, ghosts then, last window with a ghost, none from, parent crafted then"]
    child = ["child: run, child crafted at removal, at end, reads 1 from, reads 2 from, most read after removal, its refinery after removal"]
    grids = ["grids: run, windows with both, windows with equal ids, parent id, child id, child's first kJ"]
    power = ["power: run, AC lowest, highest, days, days reaching the mark, longest at 0; cAC the same"]
    furn = ["furnaces: run, " + ", ".join(FURN) + ", least"]
    for name in open(os.path.join(HERE, "variants.txt")).read().split():
        by, laid = {}, []
        for r in csv.DictReader(open(os.path.join(HERE, "out", name + ".csv"))):
            if r["sink"] == "growth:laid:1":
                laid.append(int(r["count"]))
            by.setdefault(int(r["tick"]), {})[r["sink"]] = int(r["count"])
        ts = sorted(t for t in by if "ghosts:child" in by[t])   # the windows (growth's log lines carry their own ticks)
        end = by[ts[-1]]
        rm = by[REMOVE - W]
        d1 = min((t for t in ts if by[t].get("probe:dq:signal-D", 0) >= 1), default=0)
        at = min(laid) if laid else 0
        win = min((t for t in ts if t >= at), default=0) if at else 0
        before = max((by[t].get("ghosts:child", 0) for t in ts if t < win), default=0)
        g = [t for t in ts if by[t].get("ghosts:child", 0) > 0]
        last = g[-1] if g else 0
        none = min((t for t in ts if t > last), default=0)
        lay.append("  ".join(str(x) for x in [name, d1, at, len(laid), before, by[win].get("ghosts:child", 0) if win else 0,
                                               last, none, by[none].get("crafted:M", 0) if none else 0]))
        after = [t for t in ts if t > REMOVE]
        cp = lambda t: by[t].get("probe:cp:construction-robot", 0)
        r1 = min((t for t in after if cp(t) >= 1), default=0)
        r2 = min((t for t in after if cp(t) >= 2), default=0)
        child.append("  ".join(str(x) for x in [name, rm.get("watch:cM:crafted", 0), end.get("watch:cM:crafted", 0), r1, r2,
                                                 max((cp(t) for t in after), default=0),
                                                 end.get("watch:cRF:crafted", 0) - rm.get("watch:cRF:crafted", 0)]))
        both = [t for t in ts if "watch:AC:grid" in by[t] and "watch:cAC:grid" in by[t]]
        eq = sum(1 for t in both if by[t]["watch:AC:grid"] == by[t]["watch:cAC:grid"])
        lt = both[-1] if both else 0
        first = min((t for t in ts if "watch:cAC:kJ" in by[t]), default=0)
        grids.append("  ".join(str(x) for x in [name, len(both), eq, by[lt]["watch:AC:grid"] if lt else 0,
                                                 by[lt]["watch:cAC:grid"] if lt else 0, by[first]["watch:cAC:kJ"] if first else 0]))
        power.append("  ".join(str(x) for x in [name] + charge(by, ts, "watch:AC:kJ", FROM, REMOVE - W)
                               + charge(by, ts, "watch:cAC:kJ", REMOVE, ts[-1])))
        c = [rm.get(f"watch:c{f}:crafted", 0) for f in FURN]
        furn.append("  ".join(str(x) for x in [name] + c + [min(c)]))
    text = "\n".join(lay + [""] + child + [""] + grids + [""] + power + [""] + furn)
    os.makedirs(os.path.join(HERE, "run"), exist_ok=True)
    open(os.path.join(HERE, "run", "rounds.txt"), "w").write(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
