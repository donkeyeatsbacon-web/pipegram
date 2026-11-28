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

There is one decision per cell: **pipe or no pipe.** The shape of the fitting is
not yours to choose — it is read off the joints the cell has, and redrawn the
moment a neighbour changes. Lay a cell between two others and it becomes an
elbow or a straight on its own; break one of those neighbours and it changes
under you.

**The pipe never runs alongside itself.** Two pipe cells that touch are always
joined. That single rule is what makes the fill alone a complete puzzle: once
you know which cells carry pipe, there is nothing left to work out.

The rules that make it deducible:

- **Nothing branches and nothing dead-ends.** So **every pipe cell has exactly
  two pipe neighbours**, and each tap exactly one. A cell with three is
  impossible, which rules out a great many clue-satisfying fills on sight.
- **A cell with two pipe neighbours is full.** Nothing else may touch it — so
  laying one cell often forces the cells around it empty.
- **One continuous run, no closed loops.** A separate ring of pipe that happens
  to satisfy the clues is still wrong: the run has to start at the inlet and end
  at the outlet.

Formally: the filled cells, with an edge between any two that touch, form a
**simple path** from the inlet to the outlet.

## Two modes

**Flow** (default) — Pipe Dream's pressure. After a thinking period the water
sets off from the inlet and follows **your** pipework, joint by joint, wherever
it leads. Two ways to drown:

- **It runs out of pipework.** The pressure builds for 12 seconds — a red
  countdown — and if the water has nowhere to go by then, the joint it is
  sitting in goes.
- **It escapes at a junction you made.** Hang a spare cell off the route and
  that cell now has three joints where the route has two. The water does not get
  through a tee — it escapes there. It only bites once the water arrives, not
  when you lay it, and it bursts at your own junction, so it does not hand you
  the right answer.

Because the water follows the pipework you laid rather than a known route, Flow
mode also *shows* you your plumbing working: watch it stop dead at a tee and you
have found your mistake yourself.

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
| The **palette** — pipe · empty | pick what a tap lays |
| Tap / click a cell | lay that mark there |
| Drag | lay the same mark along a run |
| `1` / `2` | pick a tool · `Space` swaps them |
| Right click | paint the *other* mark |
| `Z` | undo |
| `F` | switch Flow / Zen |
| `R` | reset · `N` / `P` next & previous · `H` hint · `M` toggle error highlighting |
| `Esc` | quit |

There is no rotation and nothing to orient. A pipe cell with nothing joined onto
it yet is drawn as a blanked-off boss; it becomes a real fitting the moment you
lay something beside it.

The inlet is drawn as a **valve on the wall** and the outlet as a **drain into
it**, and both are built facing the direction the pipe actually runs. That first
and last joint is given to you, so read it off the spigots and you have two
footholds before you start. Clue numbers grey out as that line is satisfied.

### The arrangement

There is **one** screen arrangement. It was picked by building seven
alternatives, playing them against each other, and then deleting them: a tight
header, the two tools raised on their own panel, the board grown into the dead
win/lose strip so the banner overlays it when it is needed, and the Flow
countdown drawn as a ring around the water's head rather than a bar up top.

Against the first arrangement that is a 104 px cell instead of 88 px on a 6×6,
and the countdown sits where your eyes already are.

The four numbers that make it are named constants at the top of
`scripts/Main.gd` — `HEAD_H`, `CTRL_H`, `BANNER_GAP`, and the ring — so the
decision can be found and argued with rather than inferred from drawing code.
The variants, the picker, the `L` / `[` / `]` keys and the six unused chrome
builders are gone: about 340 lines.

To look at every state the board has:

```bash
heavy tools/shots.sh /tmp/pipegram-shots 6
```

The faults an arrangement produces are geometric, and tedious and unreliable to
catch by eye, so the geometry is checked instead:

```bash
godot --path . -- --layoutaudit --puzzle 6
```

With one arrangement the thing that varies is the **board**: a 5×5 and a 10×10
ask very different things of the same furniture, and the clue gutters are sized
by measuring real text. So it now runs over **every puzzle in the set** rather
than one sample against seven layouts. For each it checks that the board, the
win banner and every button sit inside the viewport, that no control overlaps
the board or another control, that the grid stays out of the bands the header
and the controls reserve, and that nothing has shrunk below the size a thumb
can hit. It needs a window rather than `--headless`, because there is no font
to measure without one.

It ends by planting two faults it must catch — one rect off the edge, one too
small to hit — and failing if it misses them, because a clean run from a check
that cannot fail would mean nothing.

The pressure ring hides its whole point in a still, because it only appears
once the water has caught the frontier. `--pressure` sets that moment up so it
can be photographed.

Everything is tap-only on purpose: no swipe gestures. Swipes collide with
drag-painting and with the browser's own scrolling, which misfires exactly when
you are going fast — the worst moment in Flow mode.

**Mistakes are not flagged.** Lay a wrong cell and the game says nothing — work
out where you went wrong yourself, the way a nonogram makes you. If you are well
and truly stuck, `M` toggles red tinting on wrong cells, and `Hint` hands you
one cell (it fixes a wrong cell first, if there is one).

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

**Every puzzle has exactly one solution**, so none of them ever requires a
guess. `tools/generate.py` grows a random route that never runs alongside
itself, derives the clues from it, then runs a solver that counts whole
solutions and throws the puzzle away unless the count is exactly 1.

```bash
heavy python3 tools/generate.py --selftest   # check the solver and the grower
heavy python3 tools/generate.py              # regenerate data/puzzles.json
```

The solver is a row-by-row nonogram search with two prunes doing the real work:

1. **Column feasibility** — a DP over run states, so a partial fill that can no
   longer satisfy some column clue is dropped at that row rather than at the end.
2. **The path rule** — as each row is placed it maintains a union-find over the
   touching pipe cells, rejecting any cell that reaches three neighbours, any
   closed loop, and any component that has sealed itself off from the taps. Most
   clue-satisfying fills die here, which is what keeps it tractable.

## Tests

```bash
godot --headless --path . -- --logictest
```

Plays every puzzle through the same calls the mouse uses — checking the taps are
laid as real pipe and still know which way their spigot faces, that laying the
whole fill registers as solved, and that the water traced through the laid
pipework follows the real route exactly.

It also checks the rule on each solution independently: every pipe cell has
exactly two pipe neighbours, each tap exactly one, the run has exactly two ends,
and the route walks every filled cell once. A puzzle that fails this is not
solvable as stated, whatever its clues say.

Then it drives Flow mode to all three of its endings on every puzzle: water
reaches the outlet on a fully laid route, water bursts from pressure when
nothing is laid, and water escapes at a bad junction when a spare cell is hung
off the route — checking it bursts at *that* junction and not somewhere else.
Plus the Zen lock: dropping to Zen keeps the board, stops the water, and cannot
be toggled back for a fresh clock.

These checks earn their keep. The first run after the two-state rewrite failed
every one of the 22 puzzles, on two real bugs: the leak detector counted a
cell's neighbours in the *answer* rather than on the board as played, so a
three-way junction could never be seen and burst as ordinary pressure; and the
water left the valve by whichever joint sorted lowest, which made its exit
arbitrary whenever a player had pipe on both sides of the valve. It now leaves
the way the spigot points, which is a given and is already drawn on screen.

This exists because a bug hid behind a visual check: the inlet and outlet were
drawn as rings on top of the board but never written into the grid, so nothing
could join onto them and no puzzle could be completed. The screenshot mode
wrote `marks` directly and so looked perfect. **Anything that verifies the board
must go through `_set_fill`**, the way a player does.

## Layout

```
project.godot        Godot project (GL Compatibility, 760×1080 portrait)
Main.tscn            one Node2D, everything drawn in code
scripts/Main.gd      board, derived fittings, clue checking, rendering, input
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
- Portrait only. The landscape arrangement was deleted with the other variants,
  and it was the honest fix for the big grids on a phone: an Expert 10×10 is a
  65 px cell in portrait, playable but tight. If a playtest says Expert on a
  phone matters, landscape comes back as a real mode rather than a variant.
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
