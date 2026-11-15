#!/usr/bin/env python3
"""Run one experiment headless and print per-sink throughput.

    python3 harness/run.py experiments/<dir>/experiment.json

Writes the experiment into the harness mod, creates a fresh map, runs it under
--benchmark for warmup + ticks, and reads script-output/lab/<name>.csv.
Exit 0 only when the game exited 0, every sink wrote every window, some sink
moved items, and each declared pair has exactly one variant moving items.
"""
import csv
import json
import os
import subprocess
import sys
import time
from collections import defaultdict

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The game and its config; a reproduction kit points these elsewhere by environment.
GAME = os.environ.get("LAB_FACTORIO") or os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio")
CONFIG = os.environ.get("LAB_CONFIG") or os.path.join(LAB, "instance", "config.ini")
MODS = os.path.join(LAB, "harness", "mods")
WRITE = os.environ.get("LAB_WRITE") or os.path.join(LAB, "instance", "write")
# The experiment's keys the mod reads (experiment.lua).
EXP_KEYS = ("name", "area", "warmup", "window", "entities", "inserter_variants", "ups", "research", "wires", "observe", "chunks_radius", "pulses", "probe", "posdump", "tally", "progress", "events", "filter_read", "priority_read", "input_priority_read", "blueprint", "blueprints", "export_blueprint", "watch", "count_ghosts", "ghost_areas", "probes", "fluidprobes", "growth", "ghost_names", "screenshots", "count_networks", "count_cargo", "resources", "water_tiles", "daytime")


def lua(v):
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k} = {lua(x)}" for k, x in v.items()) + "}"
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    return repr(v)


def game(*args, log):
    with open(log, "w") as f:
        return subprocess.run([GAME, "-c", CONFIG, "--mod-directory", MODS, *args],
                              stdout=f, stderr=subprocess.STDOUT).returncode


def expand(exp):
    """Clone `unit` over a grid, and lay a power grid over it if asked.

    grid: {nx, ny, dx, dy}. Substations go in the column just left of each
    unit column (x = c*dx - 1), every 16 tiles down, so the free strip on the
    right of each unit must be at least 2 tiles wide.
    """
    ents = list(exp.get("entities", []))
    g = exp.get("grid")
    if g:
        for cx in range(g["nx"]):
            for cy in range(g["ny"]):
                for e in exp["unit"]:
                    c = dict(e)
                    c["position"] = [e["position"][0] + cx * g["dx"], e["position"][1] + cy * g["dy"]]
                    if "tag" in e:
                        c["tag"] = f'{e["tag"]}#{cx}_{cy}'
                    if "sink" in e:
                        c["sink"] = f'{e["sink"]}#{cx}_{cy}'
                    if "group" in e:
                        c["group"] = f'{e["group"]}#{cx}_{cy}'
                    ents.append(c)
                for a, b, color in exp.get("unit_wires", []):
                    exp.setdefault("wires", []).append([f"{a}#{cx}_{cy}", f"{b}#{cx}_{cy}", color])
        if exp.get("power_grid"):
            height = g["ny"] * g["dy"]
            ents.append({"name": "electric-energy-interface", "position": [-4, 8]})
            for cx in range(g["nx"] + 1):
                y = 8
                while y <= height + 8:
                    ents.append({"name": "substation", "position": [cx * g["dx"] - 1, y]})
                    y += 16
        exp["area"] = [[-8, -2], [g["nx"] * g["dx"] + 4, g["ny"] * g["dy"] + 12]]
    exp["entities"] = ents
    return exp


def ups(exp, save, rundir):
    u = exp["ups"]
    log = os.path.join(rundir, "benchmark.log")
    rc = game("--benchmark", save, "--benchmark-ticks", str(u["drop"] + u["ticks"]),
              "--benchmark-runs", str(u["runs"]), "--benchmark-verbose", "all", log=log)
    if rc:
        print(f"benchmark failed: exit {rc} (see {log})")
        return 1
    runs, header = [], None
    for line in open(log):
        if line.startswith("run "):
            runs.append([])
        elif line.startswith("tick,"):
            header = line.rstrip(",\n").split(",")
        elif line.startswith("t") and line[1:2].isdigit() and runs:
            runs[-1].append(line.rstrip(",\n").split(","))
    if not runs or header is None:
        print("no per-tick timings found: nothing measured")
        return 1
    cols = ["wholeUpdate", "entityUpdate", "transportLinesUpdate", "scriptUpdate"] + u.get("per", [])
    idx = {c: header.index(c) for c in cols}
    per_run = []
    for r in runs:
        body = [row for row in r if int(row[0][1:]) >= u["drop"]]
        per_run.append({c: sum(int(row[idx[c]]) for row in body) / max(1, len(body)) for c in cols})
    out = {"runs": len(per_run), "ticks_per_run": [len([x for x in r if int(x[0][1:]) >= u["drop"]]) for r in runs]}
    n = u.get("count", 1)
    for c in cols:
        vals = sorted(p[c] for p in per_run)
        med = vals[len(vals) // 2]
        out[c] = {"median_ns": med, "min_ns": vals[0], "max_ns": vals[-1], "per_entity_ns": med / n}
    # Never overwrite an earlier run: a later session's numbers once replaced
    # round 1's under the same name, and a table built from them read wrong.
    stamp = time.strftime("%Y%m%dT%H%M%S", time.gmtime())
    json.dump(out, open(os.path.join(rundir, f'{exp["name"]}-ups.{stamp}.json'), "w"), indent=1)
    json.dump(out, open(os.path.join(rundir, exp["name"] + "-ups.json"), "w"), indent=1)
    for c in cols:
        o = out[c]
        print(f"{c}: median {o['median_ns']:.0f} ns/tick (min {o['min_ns']:.0f}, max {o['max_ns']:.0f}); per entity {o['per_entity_ns']:.1f} ns")
    active = [c for c in u.get("expect_active", []) if out[c]["median_ns"] <= 0]
    if active:
        print(f"expected active but zero: {active}")
        return 1
    return 0


def observed(exp, save, rundir):
    """Observe mode: run untimed to `last` and report what the mod sampled."""
    name, o = exp["name"], exp["observe"]
    out = os.path.join(WRITE, "script-output", "lab", name + "-observe.csv")
    if os.path.exists(out):
        os.remove(out)
    rc = game("--benchmark", save, "--benchmark-ticks", str(o["last"] + 2), log=os.path.join(rundir, "benchmark.log"))
    if rc:
        print(f"benchmark failed: exit {rc} (see {rundir}/benchmark.log)")
        return 1
    if not os.path.exists(out):
        print("no observation written: nothing observed")
        return 1
    text = open(out).read()
    with open(os.path.join(rundir, name + "-observe.csv"), "w") as f:
        f.write(text)
    rows = list(csv.DictReader(text.splitlines()))
    ticks = sorted({int(r["tick"]) for r in rows})
    want = list(range(0, o["last"] + 1, o["every"]))
    for t in ticks:
        parts = [f'{r["kind"]}.{r["key"]}={r["value"]}' for r in rows if int(r["tick"]) == t]
        print(f"t={t}: " + " ".join(sorted(parts)))
    if ticks != want:
        print(f"samples at {ticks}, expected {want}")
        return 1
    return 0


def checked(exp, check, rundir):
    """Report the beacon check the mod wrote; a layout that expects beacons
    and wrote no check is a fault."""
    want = sum(1 for e in exp["entities"] if "expect_beacons" in e)
    if not want:
        return 0
    if not os.path.exists(check):
        print("no beacon check written: layout unverified")
        return 1
    rows = list(csv.DictReader(open(check)))
    with open(os.path.join(rundir, exp["name"] + "-check.csv"), "w") as f:
        f.write(open(check).read())
    if len(rows) != want:
        print(f"beacon check covers {len(rows)} of {want} receivers")
        return 1
    speeds = sorted(float(r["crafting_speed"]) for r in rows)
    counts = sorted({int(r["beacons_count"]) for r in rows})
    print(f"beacon check: {len(rows)} receivers, beacons_count {counts}, crafting_speed {speeds[0]:.6f}..{speeds[-1]:.6f}")
    return 0


def main(path):
    exp = expand(json.load(open(path)))
    name, ticks = exp["name"], exp.get("ticks", 0)
    rundir = os.path.join(os.path.dirname(os.path.abspath(path)), "run")
    os.makedirs(rundir, exist_ok=True)
    with open(os.path.join(MODS, "lab-harness", "experiment.lua"), "w") as f:
        f.write("return " + lua({k: exp[k] for k in EXP_KEYS if k in exp}) + "\n")
    out = os.path.join(WRITE, "script-output", "lab", name + ".csv")
    for stale in (out, os.path.join(WRITE, "script-output", "lab", name + "-pos.csv")):
        if os.path.exists(stale):
            os.remove(stale)
    save = os.path.join(rundir, name + ".zip")
    if os.path.exists(save):
        os.remove(save)
    create = []
    if "map_gen" in exp:
        # Map generation settings, written beside the run so the map can be remade.
        mg = os.path.join(rundir, name + "-map-gen.json")
        json.dump(exp["map_gen"], open(mg, "w"), indent=1)
        create += ["--map-gen-settings", mg]
    if "seed" in exp:
        create += ["--map-gen-seed", str(exp["seed"])]
    rc = game("--create", save, *create, log=os.path.join(rundir, "create.log"))
    if rc:
        print(f"create failed: exit {rc} (see {rundir}/create.log)")
        return 1
    check = os.path.join(WRITE, "script-output", "lab", name + "-check.csv")
    if os.path.exists(check):
        os.remove(check)
    if "observe" in exp:
        return observed(exp, save, rundir)
    if "ups" in exp:
        rc = ups(exp, save, rundir)
        return rc or checked(exp, check, rundir)
    total = exp["warmup"] + ticks + 1
    rc = game("--benchmark", save, "--benchmark-ticks", str(total), log=os.path.join(rundir, "benchmark.log"))
    if rc:
        print(f"benchmark failed: exit {rc} (see {rundir}/benchmark.log)")
        return 1
    if not os.path.exists(out):
        print("no CSV written: nothing measured")
        return 1
    if checked(exp, check, rundir):
        return 1
    rows = list(csv.DictReader(open(out)))
    with open(os.path.join(rundir, name + ".csv"), "w") as f:
        f.write(open(out).read())
    pos = os.path.join(WRITE, "script-output", "lab", name + "-pos.csv")
    if "posdump" in exp and os.path.exists(pos):
        with open(os.path.join(rundir, name + "-pos.csv"), "w") as f:
            f.write(open(pos).read())
    windows = ticks // exp["window"]
    per = defaultdict(list)
    for r in rows:
        per[r["sink"]].append(int(r["count"]))
    sinks = [e["sink"] for e in exp["entities"] if "sink" in e]
    sinks += [f'{e["belt_sink"]}:{side}' for e in exp["entities"] if "belt_sink" in e for side in ("left", "right")]
    sinks += [f"tally:{g}" for g in exp.get("tally", [])]
    bad = [s for s in sinks if len(per[s]) != windows]
    for s in sinks:
        n = sum(per[s])
        print(f"{s}: {n} items in {len(per[s]) * exp['window']} ticks = {n * 60 / max(1, len(per[s]) * exp['window']):.4f}/s")
    if bad:
        print(f"sinks missing windows: {bad}")
        return 1
    if not sinks:
        # An experiment with no item sink (fluids only, e165): the guard below has no referee.
        print("no sink declared: the nothing-moved guard skipped, not passed")
        return 0
    if not any(sum(per[s]) for s in sinks):
        print("nothing moved: every sink is empty, a harness fault until shown otherwise")
        return 1
    # A pair names two variants of which exactly one should move items, e.g.
    # the two directions of one inserter. Both or neither is a fault.
    broken = [p for p in exp.get("pairs", []) if sum(bool(sum(per[s])) for s in p) != 1]
    if broken:
        print(f"pairs where not exactly one variant moved items: {broken}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]) if len(sys.argv) == 2 else (print(__doc__.strip()) or 2))
