#!/usr/bin/env python3
"""Reproduce e177-whole-child's table on your own Factorio (the build it was graded on:
2.1.24, base game; headless, about 4 minutes for its one run of 1,600,000 ticks).

    python3 reproduce.py [--factorio BIN] [--data DIR]        # every run, then the table
    python3 reproduce.py --quick gen 100000                    # the run's first 100,000 ticks

BIN is the game's executable and DIR its read-only data folder (defaults:
Steam on macOS). Runs write to ./instance/write. Exit 0 when the result
matches the graded one.
"""
import csv
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXP = os.path.join(HERE, "experiments", "e177-whole-child")
MAC = os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents")


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def growth(path, until=None):
    rows = [r for r in csv.reader(open(path)) if len(r) == 3 and r[0].isdigit()]
    return sorted(r for r in rows if until is None or int(r[0]) <= until)


def run(v, ticks=None):
    src = os.path.join(EXP, v + ".json")
    if ticks:
        import json
        x = json.load(open(src))
        x["ticks"] = ticks
        src = os.path.join(EXP, "run", v + "-quick.json")
        os.makedirs(os.path.dirname(src), exist_ok=True)
        json.dump(x, open(src, "w"))
    subprocess.run([sys.executable, os.path.join(HERE, "harness", "run.py"), src], env=ENV)
    name = "e177-" + v
    return os.path.join(os.path.dirname(src), "run", name + ".csv") if ticks else os.path.join(EXP, "run", name + ".csv")


bin_ = arg("--factorio", os.path.join(MAC, "MacOS", "factorio"))
data = arg("--data", os.path.join(MAC, "data"))
write = os.path.join(HERE, "instance", "write")
os.makedirs(write, exist_ok=True)
cfg = os.path.join(HERE, "instance", "config.ini")
open(cfg, "w").write(f"[path]\nread-data={data}\nwrite-data={write}\n")
ENV = dict(os.environ, LAB_FACTORIO=bin_, LAB_CONFIG=cfg, LAB_WRITE=write)

if "--quick" in sys.argv:
    v, n = arg("--quick", ""), int(sys.argv[sys.argv.index("--quick") + 2])
    got = growth(run(v, n), n)
    want = growth(os.path.join(EXP, "expected", v + ".csv"), n)
    print(f"{v}: {len(got)} rows to tick {n}; graded run {len(want)}; "
          f"{'identical' if got == want else 'DIFFERENT'}")
    sys.exit(0 if got == want else 1)

os.makedirs(os.path.join(EXP, "out"), exist_ok=True)
for v in open(os.path.join(EXP, "variants.txt")).read().split():
    shutil.copy(run(v), os.path.join(EXP, "out", v + ".csv"))
subprocess.run([sys.executable, os.path.join(EXP, "analyze.py")], check=True)
got = open(os.path.join(EXP, "run", "rounds.txt")).read()
want = open(os.path.join(EXP, "expected", "rounds.txt")).read()
print("the table matches the graded one" if got == want else "the table DIFFERS from the graded one")
sys.exit(0 if got == want else 1)
