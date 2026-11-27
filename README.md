# Pipegram

Pipe Dream's plumbing, a nonogram's clues. A prototype.

**▶ Play it: <https://donkeyeatsbacon-web.github.io/pipegram/>** — works on a
phone; the first load pulls about 10 MB.

## The idea

A single pipe runs from an **inlet** to an **outlet**. Its route is fixed before
you start — your job is to work out which cells it runs through *and which
fitting sits in each one*.

The numbers down the left and across the top are **nonogram run-length clues**:
`3 1` means that line contains a run of 3 pipe cells, then later a run of 1,
with at least one empty cell between them.

There are three fittings:

| | |
|---|---|
| **straight** | two ends opposite each other — 2 orientations |
| **elbow** | two ends at right angles — 4 orientations |
| **cross** | four ends: the route passing over itself |

**Pipe cells may sit side by side without being joined.** That is the whole
game. Knowing which cells hold pipe does not tell you how they connect, so the
fittings are a second deduction stacked on the fill — and the two feed each
other, because the fill has to be one you can actually plumb.

The rules that make it deducible:

- **Nothing branches and nothing dead-ends.** The inlet and the outlet have one
  end each. Every other pipe cell has two ends, or four where the route crosses
  itself. So **every pipe cell needs at least two pipe neighbours** — one for a
  tap — which rules out a lot of fills before you start on the fittings.
- **Every joint is mutual.** If a cell opens east, its eastern neighbour opens
  west. A fitting pointing at an empty cell, or at a neighbour that does not
  point back, is wrong.
- **A cell with exactly two pipe neighbours is forced** — it must join to both.
  That is the thread you pull on.
- **A cross needs all four neighbours filled**, and the header tells you how
  many crossings the route has. Often that number alone places them.
- **One continuous run, no closed loops.** Split every cross into its two
  passes and the pipework is a single path from the inlet to the outlet.

Formally: with each cross split into a horizontal node and a vertical node, the
joined-up pipework is a **simple path** from the inlet to the outlet that
visits every pipe cell.

## Two modes

**Flow** (default) — Pipe Dream's pressure. After a thinking period the water
sets off from the inlet and follows **your** fittings, joint by joint, wherever
they lead. Two ways to drown:

- **It runs out of pipework.** The pressure builds for 12 seconds — a red
  countdown — and if the water has nowhere to go by then, the joint it is
  sitting in goes.
- **It is sent somewhere the pipe never went.** A wrong fitting routes the water
  off the real route, and it bursts the moment it arrives there. A wrong fitting
  only bites when the water reaches it, not when you lay it — and the burst
  happens where the water escaped, so it does not hand you the right answer.

Because the water follows the fittings rather than a known route, Flow mode also
*shows* you your plumbing working: watch it take a wrong elbow and you have
found your mistake yourself.

Reach the outlet, or finish the deduction before the water arrives, and you win.
`Mode: Flow` / `F` switches to:

**Zen** — no clock. Solve it in your own time; water only runs once you're done.

Dropping from Flow to Zen is **a one-way door for that puzzle** — the button
greys out to `Zen (locked)`. It takes effect instantly and restarts nothing, so
you keep the board you had. Without the lock, toggling the mode handed back a
full clock, which made the water avoidable whenever it got close. The lock is
per puzzle: the next one starts fresh in whichever mode you last chose.

### The tension worth watching

Deduction is *non-linear* — you might work out the far end of the route before
the middle — but water is strictly linear. So Flow mode quietly pressures you to
solve in roughly route order, prioritising cells near the inlet. That's a real
change to how the puzzle plays, and it's the main thing to judge: whether it
adds urgency or just fights the deduction.

Current budgets (all tunable at the top of `scripts/Main.gd`):

| Tier | Cells | Thinking time | Longest possible run |
|---|---|---|---|
| Warm-up 5×5 | 12 | 58 s | 3.2 min |
| Medium 7×7 | 25 | 78 s | 5.8 min |
| Expert 10×10 | 42 | 103 s | 9.9 min |

Water crosses a cell in 0.55 s — fast enough to look like water. **The flow
speed is not the difficulty**: the water spends most of its time waiting at your
frontier, so what the game actually asks is "lay the next cell of the route
every `PRESSURE_SECONDS`" (12 s). That constant is the dial that matters; the
"longest possible run" column is what you get by being just-in-time the whole
way down.

## Controls

| | |
|---|---|
| The **palette** — pipe · empty · straight · elbow · cross | pick what a tap lays. Tapping the palette button you already hold **rotates** it |
| Tap / click a cell | lay the selected fitting there |
| Tap / click that cell again | **rotate** the fitting in place |
| Drag | lay the same fitting along a run |
| `1`–`5` | pick a tool · `Space` cycles · `Q` rotates the selected fitting |
| Right click | with a fitting: rotate the other way. With pipe or empty: paint the *other* mark |
| `Z` | undo |
| `F` | switch Flow / Zen |
| `R` | reset · `N` / `P` next & previous · `H` hint · `M` toggle error highlighting |
| `Esc` | quit |

**pipe** lays plain pipe with the fitting left open — useful while you are still
working out the fill. It shows as a blanked-off boss, and the puzzle is not
finished until every one of them has a real fitting on it.

The inlet is drawn as a **valve on the wall** and the outlet as a **drain into
it**, and both are built facing the direction the pipe actually runs. That first
and last joint is given to you, so read it off the spigots and you have two
footholds before you start. Clue numbers grey out as that line is satisfied, and
the crossings count ticks off as you place them.

### Layouts

The screen arrangement is a **playable variant**, not a fixed design. `L` (or
the **Layouts** button) opens a picker with 15 of them — the current one, twelve
alternatives from slight to radical, and a recommended combination. `[` and `]`
step through them without opening the picker, so you can compare two
arrangements on the same board mid-puzzle.

Four of them change the *input* rather than the furniture:

| | |
|---|---|
| **Rotate handle in the cell** | a corner handle turns a fitting, so a tap on the cell body always means "lay one here" |
| **Orient from the drag** | drag in and out of a cell and it fits the elbow to your stroke — no gesture to misread, because it *is* the painting stroke |
| **Long-press radial** | hold a cell and all seven fittings bloom around it; the elbows sit on the diagonals that match their own shape. Slide and release. A quick tap just marks the cell |
| **No tools at all** | a tap cycles only the states *your own marks* allow, so there is no palette. It reads your marks and never the solution, so it leaks nothing |

One is a different orientation: **Landscape, two-handed** swaps the viewport to
1080×760 and puts the fittings under your left thumb and the utilities under
your right. That is the honest fix for playing Expert on a phone.

To compare them all at once:

```bash
heavy tools/shots.sh /tmp/pipegram-shots 6 flow
```

A layout's faults are geometric, and they are tedious and unreliable to catch by
eye across fifteen screenshots, so the geometry is checked instead:

```bash
godot --path . -- --layoutaudit --puzzle 6
```

For every layout, with the picker shut and open, it checks that the board, the
win banner and every button sit inside the viewport, that no control overlaps
the board or another control, that the grid stays out of the bands the header
and the controls reserve, that the long-press ring still fits when opened on a
corner cell, and that nothing has shrunk below the size a thumb can hit. It
needs a window rather than `--headless`, because the clue gutters are sized by
measuring real text and there is no font to measure without one.

It ends by planting two faults it must catch — one rect off the edge, one too
small to hit — and failing if it misses them, because a clean run from a check
that cannot fail would mean nothing.

Two layouts hide their whole point in a still: the pressure ring only appears
once the water has caught the frontier, and the long-press ring only while a
cell is held. `--pressure` and `--radial` set up those moments so they can be
photographed.

Everything is tap-only on purpose: no swipe gestures. Swipes collide with
drag-painting and with the browser's own scrolling, which misfires exactly when
you are going fast — the worst moment in Flow mode. The **Orient from the drag**
and **Long-press radial** layouts are the two that get at what a swipe was
reaching for without that collision.

**Mistakes are not flagged.** Lay a wrong pipe or a wrong fitting and the game
says nothing — work out where you went wrong yourself, the way a nonogram makes
you. If you are well and truly stuck, `M` toggles red tinting on wrong cells,
and `Hint` hands you one cell complete with its fitting (it fixes a wrong cell
first, if there is one).

## Running it

From inside the project folder:

```bash
godot --path .
```

Or open the folder in the Godot editor and press F5. You need Godot 4.7 or
newer — [godotengine.org/download](https://godotengine.org/download). It's a
single binary with no installer.

Built against **Godot 4.7.2**, GL Compatibility renderer — light enough for the
GTX 750 Ti, and the same renderer you'd ship to Android.

### Playing in a browser

```bash
godot --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server 8099 --bind 127.0.0.1 --directory build/web
```

Then open <http://127.0.0.1:8099/>. It needs a web server — opening `index.html`
straight off disk will not work.

The preset sets `variant/thread_support=false` on purpose. The threaded build
needs `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers,
which GitHub Pages and itch.io do not send; the no-threads build runs anywhere.

Touch works because Godot's `emulate_mouse_from_touch` turns a finger drag into
a left-button drag. What touch *cannot* reach is the right button, which is why
marking cells empty needs the tap-mode toggle.

## Puzzles

`data/puzzles.json` holds the baked puzzle set, 5×5 up to 10×10.

**Every puzzle has exactly one solution** — one fill *and* one set of fittings —
so none of them ever requires a guess. `tools/generate.py` grows a random route,
derives the clues and the crossings count, then runs a solver that counts whole
solutions and throws the puzzle away unless the count is exactly 1.

```bash
heavy python3 tools/generate.py --selftest   # check the solver and the grower
heavy python3 tools/generate.py              # regenerate data/puzzles.json
heavy python3 tools/generate.py --verify      # re-check what is already there
```

The route grower may run the pipe alongside itself freely. It may also cross,
but only squarely: a cell is entered a second time only if its first pass went
straight through, and the second pass must go straight through the other way —
which is exactly what a cross fitting is.

The solver works in two stages:

1. **The fill.** A row-by-row nonogram search, pruned by column-clue
   feasibility (a DP over run states) and by the one thing the fittings demand
   of a fill: no pipe cell can be a dead end, so each needs at least two pipe
   neighbours — one for a tap.
2. **The fittings.** For a fill that survives, it threads the route through it
   and counts the ways, with a cross allowed only where the route can pass
   through squarely twice. Most clue-satisfying fills cannot be plumbed at all,
   which is what keeps the whole thing tractable.

`--verify` re-derives everything from scratch — clues from the fill, the fill
from the fittings, the route from both — and re-runs the uniqueness count, so
it checks the stored data rather than trusting the generator that wrote it.

## Tests

```bash
godot --headless --path . -- --logictest
```

Plays every puzzle through the same calls the mouse uses — checking the taps are
laid as real pipe with their real fittings, that laying the whole solution
registers as solved, and that the water traced through the laid fittings follows
the real route exactly.

It also checks the fitting rules on each solution independently: every joint
mutual, no dead ends but the taps, the crossings count agreeing with the
fittings, and the route visiting every cell once — twice at a crossing. And it
checks that the *old* rule ("a cell joins onto all of its filled neighbours") no
longer solves these puzzles, which is the whole point of the redesign; it
reports how many fittings each puzzle leaves genuinely open.

Then it drives Flow mode to all three of its endings on every puzzle: water
reaches the outlet on a fully laid route, water bursts from pressure when
nothing is laid, and water bursts when a deliberately rotated fitting sends it
into pipe that was never on the route. Plus the Zen lock — that dropping to Zen
keeps the board, stops the water, and cannot be toggled back for a fresh
clock.

Each check was confirmed to fail when the behaviour it covers is disabled.

This exists because a bug hid behind a visual check: the inlet and outlet were
drawn as rings on top of the board but never written into the grid, so nothing
could join onto them and no puzzle could be completed. The screenshot mode
wrote `marks` directly and so looked perfect. **Anything that verifies the board
must go through `_set_mark`**, the way a player does.

## Layout

```
project.godot        Godot project (GL Compatibility, 760×1080 portrait)
Main.tscn            one Node2D, everything drawn in code
scripts/Main.gd      board, fittings, clue checking, rendering, input
data/puzzles.json    verified puzzles
tools/generate.py    generator + uniqueness-verifying solver
```

## Prototype limits

Deliberately not built yet, in rough order of what a playtest will tell you to
do first:

- No level select, no progress saving, no sound. Flow mode especially wants
  sound — a rising trickle and a bang are half the tension.
- Flow timings are a first pass. See the table above.
- Puzzles are a fixed baked set; generation does not run in-game.
- Touch is playable but not polished: no drag threshold, so a sloppy tap can
  paint two cells, and there is no pinch-zoom on the bigger grids.
- Rotating is tap-to-cycle only. An elbow takes up to three taps to point the
  right way, which is fine on a mouse and a bit of a chore on a phone.
- Difficulty is just grid size. Real difficulty wants a measure of *how hard
  the deduction chain is*, not how big the board is.

### Redeploying after a change

```bash
godot --headless --path . --export-release "Web" build/web/index.html
git worktree add -B gh-pages /tmp/pg-pages main
cd /tmp/pg-pages && git rm -rq . && cp -a "$OLDPWD/build/web/." . && touch .nojekyll
git add -A && git commit -m "Deploy web build" && git push -f origin gh-pages
cd - && git worktree remove /tmp/pg-pages
```

Pages serves the `gh-pages` branch, so `main` stays free of binaries.
