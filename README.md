# Pipegram

Pipe Dream's plumbing, a nonogram's clues. A prototype.

**▶ Play it: <https://donkeyeatsbacon-web.github.io/pipegram/>** — works on a
phone; the first load pulls about 10 MB.

## The idea

A single pipe runs from an **inlet** to an **outlet**. Its route is fixed before
you start — your job is to work out which cells it runs through.

The numbers down the left and across the top are **nonogram run-length clues**:
`3 1` means that line contains a run of 3 pipe cells, then later a run of 1,
with at least one empty cell between them.

One extra rule does all the heavy lifting:

> **The pipe never runs alongside itself.** Two pipe cells are orthogonally
> adjacent only where the pipe actually connects them.

That means once you know *which* cells hold pipe, the piece in every cell is
forced — each cell's connections are exactly its filled neighbours. You solve a
fill pattern; the elbows and straights draw themselves. It also gives you
deduction nonograms don't have:

- A run of 3 or more in a row is a straight length of pipe, so its **interior
  cells can have no vertical neighbours** — mark the cells above and below them
  empty immediately.
- Each **end** of a run needs exactly one perpendicular connection, unless it is
  the inlet or the outlet (which have exactly one connection in total).

Formally: the filled cells, with edges between orthogonally adjacent members,
must form a **simple path** whose two ends are the inlet and the outlet.

## Two modes

**Flow** (default) — Pipe Dream's pressure. After a thinking period the water
sets off from the inlet and runs along the pipe you have actually laid. Two ways
to drown:

- **It catches up with your plumbing.** The pressure builds for 7 seconds — a
  red countdown — and if you have not laid the next cell of the route by then, a
  joint goes.
- **It reaches a leak.** Pipe hanging off the wetted line that isn't on the real
  route bursts when the water arrives. Correct pipe can never do this (the route
  never runs alongside itself), so a leak is always a mistake — but it only
  bites when the water gets there, not when you place it.

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
| Left click / drag, or finger drag | paint whatever the tap-mode button shows (start on a cell that already has it to rub it out) |
| The wide **tap lays PIPE / tap marks EMPTY** button, or `Space` | switch what a tap paints |
| Right click / drag | paint the *other* mark — a mouse shortcut, so you needn't keep switching |
| `Z` | undo |
| `F` | switch Flow / Zen (restarts the puzzle) |
| `R` | reset · `N` / `P` next & previous · `H` hint · `M` toggle error highlighting |
| `Esc` | quit |

The inlet and outlet are given to you. Clue numbers grey out as that line is
satisfied.

**Mistakes are not flagged.** Lay a wrong pipe and the game says nothing — work
out where you went wrong yourself, the way a nonogram makes you. If you are well
and truly stuck, `Errors: off` toggles red tinting on wrongly-laid pipe, and
`Hint` hands you one cell (it fixes a wrong cell first, if there is one).

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

`data/puzzles.json` holds 22 hand-verified puzzles, 5×5 up to 10×10.

**Every puzzle has exactly one solution**, so none of them ever requires a
guess. `tools/generate.py` grows a random pipe, derives the clues, then runs a
solver that counts solutions and throws the puzzle away unless the count is
exactly 1.

```bash
heavy python3 tools/generate.py --selftest   # check the solver
heavy python3 tools/generate.py              # regenerate data/puzzles.json
```

The solver is a row-by-row nonogram search with three extra prunes: column
clue feasibility (a DP over run states), pipe-degree checks on each completed
row, and a union-find cycle check that kills any branch closing a loop.

## Tests

```bash
godot --headless --path . -- --logictest
```

Plays all 22 puzzles through the same calls the mouse uses — checking the taps
are laid as real pipe, that laying the solution registers as solved, and that
each tap ends up joined to exactly one neighbour.

It also drives Flow mode to all three of its endings on every puzzle: water
reaches the outlet on a fully laid route, water bursts from pressure when
nothing is laid, and water bursts on a leak placed next to the inlet. Plus the
Zen lock — that dropping to Zen keeps the board, stops the water, and cannot be
toggled back for a fresh clock.

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
scripts/Main.gd      board, clue checking, rendering, input
data/puzzles.json    22 verified puzzles
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
