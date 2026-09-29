# factorio-evolution

![Two colonies of self-copying machines grow side by side on a 15 by 15 grid. Left, where the orange lineage pays a cost, blue machines spread until they hold 61% of the grid; right, where the orange lineage costs nothing extra, blue ends at 38%.](media/side-by-side.gif)

*Blue: the light lineage. Orange: heavy (left) or its cost-free twin
(right). Both colonies start from two orange founders beside the centre;
blue arises only by mutation. Founders placed west and south of the
centre: of the ten founder placements, the one whose two colonies lie
nearest their arms' medians (0.612 against 0.592, and 0.379 against
0.406). [Watch every run in the browser.](https://hjkornn-phys.github.io/factorio-evolution/)*

**factorio-evolution is a colony of self-copying machines in vanilla
Factorio 2.1 in which a cheaper lineage outgrows a costlier one by
natural selection; the only scripted act is placing a machine's
blueprint where it asks, and plates and power are supplied.**

*Vanilla Factorio can do everything a self-replicator needs, except place
a blueprint. We scripted only that, and watched evolution happen.*

**Light's share of the grown colony: 0.587 where the other lineage pays a
cost, 0.380 where it does not; every one of 10 runs above every one of
10 (one-sided exact Mann-Whitney p = 5.4 × 10⁻⁶), Factorio 2.1.20.**

## Why this exists

Inspired by Anthropic's Claude-led discovery of a CRISPR-like enzyme
system ([September 2026][anthropic]). A personal project can't run a wet
lab, so this one uses Factorio as the lab: Claude pre-registers, runs and
grades each experiment headless; one person rules. Unlike that system,
these machines are built, not found, and their function is what gets
measured. Not affiliated with Anthropic.

## How the colony works

- **The engine: a universal assembler.** One crafter makes whatever its
  target needs, deepest ingredient first, steered by a stack of
  assemblers that never craft: each only reads its recipe's ingredients,
  one per depth. Within 2 crafts of the minimum for any target to its
  depth (5 electronic circuits in 14 crafts, minimum 13).
- **A machine makes its own kit.** All 60 parts it is built from, from
  plates, by recursion (596 seconds of recipe time a kit). It gives the
  whole kit to the logistic network, and construction robots build its
  child from it.
- **The machine decides when and where.** It raises a request when its
  kit is whole, and names a direction; a free site one step away gets
  the seed. This placing is the one scripted act: no trigger in the
  game's prototype data creates a building or a ghost, so in vanilla
  only a player lays a blueprint.
- **A census stops it.** Each machine's radar adds one to a count every
  radar shares; at the quorum it stops making kits.
- **Heredity and mutation.** A child takes its parent's blueprint,
  except when the parent's clock stands at a multiple of 7 as it lays
  (about 1 in 7): then the other lineage's.
- **A cost selection can act on.** The heavy lineage carries 24 idle
  parts (84 against 60). Its kit takes 1.50 times as long, and so does
  its generation: 214,890 against 143,460 ticks.

The machines' blueprints are in [`blueprints/`](blueprints/): light,
heavy, the twin and greedy. Each needs its site's supplies (power, a
roboport with robots, plates in storage) to run.

## Results

Twenty colonies of 224 machines, each founded by two machines of the
orange lineage beside the centre, ten founder placements, the same ten in
both arms. The arms differ only in the orange lineage's cost: heavy
carries 24 idle parts (its kit and generation 1.50 times light's); the
twin carries none.

| arm | runs | light's share, mean | least | most | grid full at (median tick) | mutant births |
|---|---|---|---|---|---|---|
| selection: light vs heavy | 10 | 0.587 | 0.504 | 0.665 | 2,626,830 | 14.6% |
| neutral control: light vs twin | 10 | 0.380 | 0.237 | 0.496 | 2,263,950 | 13.8% |

Registered before the runs: light's share larger with selection (p under
0.05); the means inside 0.42–0.64 and 0.30–0.52; every control colony
full between 1.9 and 2.5 million ticks, the selection colonies later;
mutant births 8–25%. All four held. Without an edge, drift at the
growing front spreads the control from 0.237 to 0.496; with it, every
colony is pulled the same way. Every run, with each machine's parent and
birth tick: [the viewer](https://hjkornn-phys.github.io/factorio-evolution/).

What it does not show: plates and power are supplied at every site, so
the machines compete for time, not matter; one mutation rate (about 1 in
7); a colony stopped at 224 by its census. The robots build whichever
ghost waits, so a lineage could in principle take another's parts; it
did not here: every child was built within 5,460 ticks of its seed (a
generation is about 143,000), since a parent lays its seed only when its
own kit is whole.

**The environment picks the winner.** A second lineage, greedy, carries
a second requester for each kind of plate (68 parts; its kit 1.13 times
light's). The logistic network divides a short kind evenly among open
requests, so greedy takes two turns where light takes one. Where plates
are plenty, the cheaper kit leads: light 8, greedy 7 when the census
stops the colony at 15, each light generation 12.5% shorter. Where plates
trickle in at one every 70 ticks, greedy leads, 8 to 5. Same machines,
opposite winners.

| supply | light | greedy | greedy's generation over light's |
|---|---|---|---|
| plenty (a pool of 40 kits) | 8 | 7 | 1.14 |
| trickle (one plate each 70 ticks) | 5 | 8 | 1.26 |

Both runs of each supply, founders swapped, gave the same counts. All
four registered predictions held, on runs repeated after a build fault
the first runs exposed (a second requester that never stopped filling
the first), fixed before the re-run with the prediction unchanged.

## The lab's record

Every experiment's prediction is committed before its first run, then
graded against it. Of 547 graded predictions across the lab's 142
graded experiments (2026-09-25 to 09-30), 444 held, 88 failed and 15
held in part; 60 experiments had at least one prediction fail. Failures
stay in the record, which stays private; each prediction cited here is
identified by the SHA-256 of the file as committed, before its result
was, and its text is available on request:

| experiment | what it predicted | SHA-256 |
|---|---|---|
| e143 | selection against its control | `be815e77611c0b77ea83cd80c312d8512dafc9539b17ef7b1d6d48c6d4b49c6b` |
| e144 | the supply picks the winner | `885bebc302f3ab75d2e2e9bc7061e3d826341da85a24bc5d775f5a4cde789ea9` |
| e142 | the kit's size as a cost in generations | `4a3d35fcd9e9011c230d610877431db7fd42d5fefc8e34e13986c0369002600b` |
| e141 | the lineage as a gene that mutates | `4a2481b633087b9de9e2769939ac2e9e3f91ae1dc942a56bd47d7b594f8451bc` |
| e135 | where a ghost can come from with no player | `800e4536d35c0e97a157c84bed5fb98d915ee2cd5f9cfdc7d276dbc4cb5c729f` |

The count is [`record/scoreboard.txt`](record/scoreboard.txt).

## FAQ

**Why Factorio?** A personal project can't run a wet lab. Factorio is
deterministic (the same save gives the same run, tick for tick), runs
headless at thousands of ticks a second, and its rules are fixed and
readable from its prototype data. Its circuit network, logistic robots
and assemblers are enough to build a machine that makes its own parts.

**Is this vanilla?** The machines are base-game Factorio 2.1 entities
only. A small harness mod does three things: it builds the world, records
what happens, and places a machine's blueprint as ghosts at the site the
machine names when the machine asks. Robots then build the ghosts from
the parent's kit. Plates and power are supplied at every site.

**Can Factorio self-replicate without mods?** Everything except placing
the blueprint. A scan of the game's prototypes found nothing that lays a
building or a ghost without a player; ghosts appear only where an entity
died (e135). So the one scripted act is the placing, and it happens only
when the machine's own circuit asks.

**How does mutation work?** Each machine has a clock. When it asks for a
child, the child gets the parent's blueprint, unless the clock stands at
a multiple of 7 at that moment: then the child gets the other lineage's.
About 1 birth in 7 is a mutation, in either direction (14.6% and 13.8% of
births in the two arms).

**How is this different from GreyGoo or Recursive Blueprints?** GreyGoo
Mk I (2017) grows one factory that places mining stations, hauls ore by
train and lays solar fields, using the Recursive Blueprints mod, whose
Blueprint Deployer builds a blueprint when the circuit network signals
it (supported up to Factorio 1.1). Here many copies of one machine each
make every part of their own child from plates, decide when and where the
child goes, and stop at a census; two lineages of them compete, and
selection is measured against a control.

**Is anything here new?** Parts of it are known. Recursive assemblers
with one reader per recipe depth have been posted since 2024, and a
vanilla Space Age base that makes all its own machines was shown in 2026,
placed by hand. What we did not find before this: a colony of machines
that copy themselves, grown on a grid and stopped by its own census, with
heritable variation and selection measured against a control. Searched
again 2026-09-30 (the forum, Reddit, arXiv): self-replicating factories
are an old goal of the game's players (a 2016 forum thread calls them
"one of the Reasons, why Factorio exists"), with no lineages or
selection. Mutants spreading in sectors of an expanding colony are known
from simulations of self-replicating colloids (2016), and the colonies
here grow the same way.

## Reproduce

Each result ships as a kit in [`reproduce/`](reproduce/): the
experiment's variants (world, machines and blueprints, one JSON each),
its analysis, the expected table, each run's growth events, and the
harness cut to what it needs. On Factorio 2.1.20, base game:

```
cd reproduce/e143-selection
python3 reproduce.py --factorio /path/to/factorio --data /path/to/factorio/data
```

Twenty headless runs of 3,500,000 ticks, about 25 minutes each on an
Apple Silicon Mac; it grades them and exits 0 when the table matches the
graded one. A quick check of one run's first 200,000 ticks against the
graded run's growth events:

```
python3 reproduce.py --quick sel-ws 200000 --factorio /path/to/factorio --data /path/to/factorio/data
```

The defaults are Steam's paths on macOS. `reproduce/e144-greedy` works
the same way (four runs of 800,000 ticks).

## Sources

- [Anthropic: Claude discovers a novel enzyme system][anthropic]
- [Tierra, Thomas Ray's own account](https://talkorigins.org/faqs/tierra.html):
  evolution among self-replicating programs; parasites, immunity
- [Avida](https://alife.org/encyclopedia/digital-evolution/avida/)
- [Invasion genetics](https://en.wikipedia.org/wiki/Invasion_genetics):
  drift and surfing at an expanding front
- [Mutation at Expanding Front of Self-Replicating Colloidal Clusters](https://arxiv.org/abs/1607.05802)
  (Tanaka, Zeravcic and Brenner, 2016)
- [Self Replicating (e. g. with Blueprints)](https://forums.factorio.com/viewtopic.php?t=27054)
  (the Factorio forum, 2016)
- [GreyGoo Mk I: a self-expanding factory](https://forums.factorio.com/viewtopic.php?t=41377)
  (2017)
- [Recursive Blueprints](https://mods.factorio.com/mod/recursive-blueprints)
  (DaveMcW): the Blueprint Deployer
- [Automated blueprint laying for auto base expansion](https://forums.factorio.com/viewtopic.php?t=80018):
  "In vanilla, no. Blueprints can only be designated by the player"
- [Generic recursive assembler](https://forums.factorio.com/viewtopic.php?t=122653)
  (2024), [a recursive single-assembler mall](https://www.reddit.com/r/factorio/comments/1heuv78/)
  (2024): the reader-per-depth idea behind the engine
- [A mini self-replicating Fulgora starter base](https://www.reddit.com/r/factorio/comments/1q8kq0j/)
  (2026): a vanilla base that makes all its own machines, placed by hand

## Cite

See [`CITATION.cff`](CITATION.cff). MIT licence ([`LICENSE`](LICENSE)).

[anthropic]: https://www.anthropic.com/news/claude-discovers-novel-enzyme-system
