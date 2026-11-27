#!/usr/bin/env python3
"""
Puzzle generator for PIPEGRAM.

RULES
-----
A single pipe runs from the INLET to the OUTLET. Every cell either holds a
piece of pipe or is empty, and every piece is one of:

    straight   two opposite ends        (2 orientations)
    elbow      two ends at right angles (4 orientations)
    cross      four ends                (the route passes through twice)

Nothing branches: the pipe is one continuous run. So an end cell (the inlet and
the outlet) has one connection, a straight or an elbow has two, and a cross has
four -- a cross is the route crossing over itself, one pass horizontal and one
pass vertical.

Two pipe cells may sit side by side WITHOUT being joined. That is the whole
point: knowing which cells hold pipe does not tell you how they connect, so
working out the fittings is a second, separate deduction.

Formally: split every cross into two nodes (its horizontal pass and its
vertical pass) and the joined-up pipework must be a simple path from the inlet
to the outlet, visiting every pipe cell.

CLUES
-----
* Nonogram run-length clues on every row and column: "3 1" means, reading that
  line, a run of 3 pipe cells then a run of 1, with at least one empty cell
  between them.
* How many times the route crosses itself.

Those, plus the fitting rules above, pin down exactly one answer. Every puzzle
emitted here is verified: the solver counts solutions over fills AND fittings
together and the puzzle is thrown away unless the count is exactly 1.

Usage:
    heavy python3 tools/generate.py            # write data/puzzles.json
    heavy python3 tools/generate.py --selftest
"""

import argparse
import json
import os
import random
import sys
import time

# Direction bits, in the same order the game's DIRS array uses.
N, E, S, W = 1, 2, 4, 8
BITS = (N, E, S, W)
VEC = {N: (-1, 0), E: (0, 1), S: (1, 0), W: (0, -1)}
OPP = {N: S, S: N, E: W, W: E}
HORZ = E | W
VERT = N | S
CROSS = N | E | S | W
POP = [bin(i).count("1") for i in range(16)]
HEX = "0123456789abcdef"


def step(cell, bit):
    dr, dc = VEC[bit]
    return (cell[0] + dr, cell[1] + dc)


# --------------------------------------------------------------------------
# clue helpers
# --------------------------------------------------------------------------

def runs_of(bits):
    """Run-length clue for a sequence of 0/1."""
    out, n = [], 0
    for b in bits:
        if b:
            n += 1
        elif n:
            out.append(n)
            n = 0
    if n:
        out.append(n)
    return out


_PATTERN_CACHE = {}


def line_patterns(clue, width):
    """Every 0/1 tuple of `width` whose runs equal `clue`."""
    key = (tuple(clue), width)
    hit = _PATTERN_CACHE.get(key)
    if hit is not None:
        return hit

    results = []

    def place(idx, pos, acc):
        if idx == len(clue):
            results.append(tuple(acc + [0] * (width - pos)))
            return
        run = clue[idx]
        last = idx == len(clue) - 1
        tail = sum(clue[idx + 1:]) + (len(clue) - idx - 1)
        for start in range(pos, width - run - tail + 1):
            nxt = acc + [0] * (start - pos) + [1] * run
            if not last:
                place(idx + 1, start + run + 1, nxt + [0])
            else:
                place(idx + 1, start + run, nxt)

    if not clue:
        results = [tuple([0] * width)]
    else:
        place(0, 0, [])
    _PATTERN_CACHE[key] = results
    return results


def col_step(states, bit, clue):
    """Advance column DP states by one row. State = (runs_done, len_in_run)."""
    out = set()
    for i, k in states:
        if bit:
            if k == 0:
                if i < len(clue) and clue[i] >= 1:
                    out.add((i, 1))
            elif k < clue[i]:
                out.add((i, k + 1))
        else:
            if k == 0:
                out.add((i, 0))
            elif k == clue[i]:
                out.add((i + 1, 0))
    return out


def col_done(states, clue):
    """Can a column in one of these states be finished exactly?"""
    for i, k in states:
        if i == len(clue) and k == 0:
            return True
        if clue and i == len(clue) - 1 and k == clue[-1]:
            return True
    return False


# --------------------------------------------------------------------------
# solver
# --------------------------------------------------------------------------

class Solver:
    """Counts whole solutions -- a fill AND the fittings on it -- up to a limit.

    Stage one walks the rows like an ordinary nonogram solver, pruned by the
    column clues and by what the fittings need: no pipe cell can be a dead end,
    so every one of them needs at least two pipe neighbours (one, for a tap).

    Stage two takes a finished fill and traces the route itself, counting how
    many ways the pipework can be joined up. Most fills that satisfy the clues
    cannot be plumbed at all, which is what keeps the whole thing tractable.
    """

    def __init__(self, w, h, row_clues, col_clues, inlet, outlet, crosses):
        self.w, self.h = w, h
        self.row_clues = [list(c) for c in row_clues]
        self.col_clues = [list(c) for c in col_clues]
        self.inlet = tuple(inlet)
        self.outlet = tuple(outlet)
        self.ends = {self.inlet, self.outlet}
        self.crosses = crosses
        self.total = sum(sum(c) for c in self.row_clues)
        self.rowopts = [line_patterns(c, w) for c in self.row_clues]
        self.count = 0
        self.first = None
        self.limit = 2
        self.routes_run = 0

    # ---- entry point ----------------------------------------------------
    def solve(self, limit=2):
        self.count = 0
        self.first = None
        self.limit = limit
        self.routes_run = 0
        if self.total != sum(sum(c) for c in self.col_clues):
            return 0
        self.grid = [None] * self.h
        self._rows(0, [frozenset({(0, 0)}) for _ in range(self.w)])
        return self.count

    # ---- stage one: the fill -------------------------------------------
    def _rows(self, r, colstates):
        if self.count >= self.limit:
            return
        if r == self.h:
            for s, c in zip(colstates, self.col_clues):
                if not col_done(s, c):
                    return
            self._fitting_stage()
            return

        for pat in self.rowopts[r]:
            bad = False
            for (er, ec) in self.ends:
                if er == r and not pat[ec]:
                    bad = True
                    break
            if bad:
                continue

            nxt = []
            for c in range(self.w):
                s = col_step(colstates[c], pat[c], self.col_clues[c])
                if not s:
                    bad = True
                    break
                nxt.append(s)
            if bad:
                continue

            self.grid[r] = pat
            # row r-1 now has every neighbour it will ever have
            if self._degrees_ok(r - 1) and (r < self.h - 1 or self._degrees_ok(r)):
                self._rows(r + 1, nxt)
            self.grid[r] = None
            if self.count >= self.limit:
                return

    def _filled(self, r, c):
        if r < 0 or c < 0 or r >= self.h or c >= self.w:
            return False
        row = self.grid[r]
        return row is not None and row[c] == 1

    def _degrees_ok(self, r):
        """No pipe cell may be a dead end: it needs two pipe neighbours to
        carry the route through, or one if it is a tap."""
        if r < 0:
            return True
        for c in range(self.w):
            if not self.grid[r][c]:
                continue
            deg = 0
            for b in BITS:
                dr, dc = VEC[b]
                if self._filled(r + dr, c + dc):
                    deg += 1
            if deg < (1 if (r, c) in self.ends else 2):
                return False
        return True

    # ---- stage two: the fittings ---------------------------------------
    def _fitting_stage(self):
        filled = set()
        for r in range(self.h):
            row = self.grid[r]
            for c in range(self.w):
                if row[c]:
                    filled.add((r, c))
        if len(filled) != self.total:
            return

        # a cross needs all four neighbours, so there must be room for them
        room = 0
        edges = 0
        for (r, c) in filled:
            deg = 0
            for b in BITS:
                if step((r, c), b) in filled:
                    deg += 1
            if deg == 4:
                room += 1
            edges += deg
        edges //= 2
        if room < self.crosses:
            return
        # the joined-up route uses exactly this many of the available edges
        if edges < self.total + self.crosses - 1:
            return

        self.routes_run += 1
        self._trace(filled)

    def _trace(self, filled):
        """Count the ways the route can be threaded through `filled`."""
        inlet, outlet = self.inlet, self.outlet
        total = self.total
        want_cross = self.crosses
        limit = self.limit
        # 0 unvisited, 1 straight across, 2 straight down, 3 turned, 4 crossed
        state = {inlet: 3}

        def go(cell, travel, seen, ncross):
            if self.count >= limit:
                return
            if cell == outlet:
                if seen + 1 == total and ncross == want_cross:
                    self.count += 1
                    if self.first is None:
                        self.first = dict(state)
                return
            st = state.get(cell, 0)
            if st == 0:
                back = OPP[travel]
                for ex in BITS:
                    if ex == back:
                        continue
                    nxt = step(cell, ex)
                    if nxt not in filled or nxt == inlet:
                        continue
                    if ex == travel:
                        state[cell] = 1 if travel in (E, W) else 2
                    else:
                        state[cell] = 3
                    go(nxt, ex, seen + 1, ncross)
                    del state[cell]
                    if self.count >= limit:
                        return
            elif ncross < want_cross and (
                    (st == 1 and travel in (N, S)) or (st == 2 and travel in (E, W))):
                nxt = step(cell, travel)
                if nxt in filled and nxt != inlet:
                    state[cell] = 4
                    go(nxt, travel, seen, ncross + 1)
                    state[cell] = st

        for b in BITS:
            nxt = step(inlet, b)
            if nxt in filled:
                go(nxt, b, 1, 0)
            if self.count >= limit:
                return


# --------------------------------------------------------------------------
# random route generation
# --------------------------------------------------------------------------

def on_border(r, c, w, h):
    return r == 0 or c == 0 or r == h - 1 or c == w - 1


def _enterable(m, travel):
    """Can the route enter a cell whose mask is `m`, travelling `travel`?
    Returns None if not, else the mask after entering."""
    if m == 0:
        return OPP[travel]
    if m == HORZ and travel in (N, S):
        return m | OPP[travel]
    if m == VERT and travel in (E, W):
        return m | OPP[travel]
    return None


def random_route(w, h, target, rng):
    """Grow one continuous pipe. Returns (mask, walk) or None.

    The route may run alongside itself freely. It may also cross itself, but
    only squarely: a cell is entered a second time only if its first pass went
    straight through, and the second pass must go straight through the other
    way. That is what a cross fitting is.
    """
    border = [(r, c) for r in range(h) for c in range(w) if on_border(r, c, w, h)]
    start = rng.choice(border)
    mask = {start: 0}
    walk = [start]
    cur = start
    forced = None            # mid-cross: the exit is already decided

    while True:
        if forced is None and len(mask) >= target:
            break
        if forced is not None:
            cands = [forced]
        else:
            cands = [b for b in BITS if not (mask[cur] & b)]
            rng.shuffle(cands)

        moved = False
        for b in cands:
            nb = step(cur, b)
            if not (0 <= nb[0] < h and 0 <= nb[1] < w):
                continue
            nm = _enterable(mask.get(nb, 0), b)
            if nm is None:
                continue
            nxt_forced = b if POP[nm] == 3 else None
            if nxt_forced is not None:
                # it is becoming a cross, so the straight-through must be there
                beyond = step(nb, b)
                if not (0 <= beyond[0] < h and 0 <= beyond[1] < w):
                    continue
                if _enterable(mask.get(beyond, 0), b) is None:
                    continue
            mask[cur] |= b
            mask[nb] = nm
            walk.append(nb)
            cur = nb
            forced = nxt_forced
            moved = True
            break

        if not moved:
            if forced is not None:
                return None          # painted ourselves into a half-made cross
            break

    if POP[mask[start]] != 1 or POP[mask[cur]] != 1 or cur == start:
        return None
    for m in mask.values():
        if POP[m] not in (1, 2, 4):
            return None
    return mask, walk


def build_puzzle(w, h, rng, lo=0.40, hi=0.62, tries=1500, want_border_end=True,
                 want_cross=True, budget=None):
    """Return a puzzle dict whose solution is verified unique, or None."""
    t0 = time.time()
    area = w * h
    for attempt in range(tries):
        if budget is not None and time.time() - t0 > budget:
            return None
        target = rng.randint(int(area * lo), max(int(area * hi), int(area * lo) + 1))
        got = random_route(w, h, target, rng)
        if got is None:
            continue
        mask, walk = got
        if len(mask) < max(5, int(area * lo)):
            continue
        inlet, outlet = walk[0], walk[-1]
        if want_border_end and attempt < tries * 0.8:
            if not on_border(*outlet, w, h):
                continue
        crosses = sum(1 for m in mask.values() if m == CROSS)
        # a puzzle with no crossing teaches the player nothing about crosses,
        # but insisting on one for the smallest grids makes them impossible
        if want_cross and crosses == 0 and attempt < tries * 0.6:
            continue

        grid = [[1 if (r, c) in mask else 0 for c in range(w)] for r in range(h)]
        row_clues = [runs_of(grid[r]) for r in range(h)]
        col_clues = [runs_of([grid[r][c] for r in range(h)]) for c in range(w)]

        s = Solver(w, h, row_clues, col_clues, inlet, outlet, crosses)
        if s.solve(limit=2) != 1:
            continue

        pieces = []
        for r in range(h):
            pieces.append("".join(HEX[mask.get((r, c), 0)] for c in range(w)))
        return {
            "w": w, "h": h,
            "row_clues": row_clues,
            "col_clues": col_clues,
            "inlet": list(inlet),
            "outlet": list(outlet),
            "solution": ["".join(str(b) for b in row) for row in grid],
            "pieces": pieces,
            "path": [list(c) for c in walk],
            "crosses": crosses,
            "length": len(mask),
        }
    return None


# --------------------------------------------------------------------------
# verification helpers, used by the self test and by --verify
# --------------------------------------------------------------------------

def check_puzzle(p):
    """Independent check of one puzzle dict. Returns a list of problems."""
    errs = []
    w, h = p["w"], p["h"]
    mask = {}
    for r in range(h):
        for c in range(w):
            m = int(p["pieces"][r][c], 16)
            if m:
                mask[(r, c)] = m

    # fill agrees with the pieces
    for r in range(h):
        for c in range(w):
            if (p["solution"][r][c] == "1") != ((r, c) in mask):
                errs.append("fill and pieces disagree at %d,%d" % (r, c))

    # clues agree with the fill
    grid = [[1 if (r, c) in mask else 0 for c in range(w)] for r in range(h)]
    if [list(x) for x in p["row_clues"]] != [runs_of(grid[r]) for r in range(h)]:
        errs.append("row clues do not match the solution")
    if [list(x) for x in p["col_clues"]] != [
            runs_of([grid[r][c] for r in range(h)]) for c in range(w)]:
        errs.append("col clues do not match the solution")

    inlet, outlet = tuple(p["inlet"]), tuple(p["outlet"])
    # every connection is mutual, and every shape is legal
    for cell, m in mask.items():
        if POP[m] not in (1, 2, 4):
            errs.append("illegal fitting %x at %s" % (m, cell))
        if POP[m] == 1 and cell not in (inlet, outlet):
            errs.append("dead end at %s" % (cell,))
        for b in BITS:
            if m & b:
                nb = step(cell, b)
                if mask.get(nb, 0) & OPP[b] == 0:
                    errs.append("one-sided joint %s -> %s" % (cell, nb))
    if POP[mask.get(inlet, 0)] != 1:
        errs.append("inlet is not an end")
    if POP[mask.get(outlet, 0)] != 1:
        errs.append("outlet is not an end")
    if p["crosses"] != sum(1 for m in mask.values() if m == CROSS):
        errs.append("crosses count is wrong")

    # the stored walk really is the route
    walk = [tuple(c) for c in p["path"]]
    if walk[0] != inlet or walk[-1] != outlet:
        errs.append("path does not run inlet to outlet")
    seen = {}
    for i in range(len(walk) - 1):
        a, b = walk[i], walk[i + 1]
        d = (b[0] - a[0], b[1] - a[1])
        if abs(d[0]) + abs(d[1]) != 1:
            errs.append("path jumps at step %d" % i)
            break
        bit = next(k for k, v in VEC.items() if v == d)
        seen[a] = seen.get(a, 0) | bit
        seen[b] = seen.get(b, 0) | OPP[bit]
    if seen != mask:
        errs.append("path does not use exactly the stored fittings")
    if len(walk) != len(mask) + p["crosses"]:
        errs.append("path length %d does not match %d cells + %d crosses"
                    % (len(walk), len(mask), p["crosses"]))

    # and the solution is the only one
    s = Solver(w, h, p["row_clues"], p["col_clues"], inlet, outlet, p["crosses"])
    n = s.solve(limit=2)
    if n != 1:
        errs.append("%d solutions, not 1" % n)
    return errs


# --------------------------------------------------------------------------

def selftest():
    ok = True

    assert runs_of([1, 1, 0, 1]) == [2, 1]
    assert runs_of([0, 0, 0]) == []
    assert line_patterns([], 3) == [(0, 0, 0)]
    assert len(line_patterns([1, 1], 4)) == 3
    assert set(line_patterns([2], 3)) == {(1, 1, 0), (0, 1, 1)}
    print("clue helpers      OK")

    # the route grower must never emit an illegal shape
    rng = random.Random(3)
    made = 0
    for _ in range(4000):
        got = random_route(7, 7, 24, rng)
        if got is None:
            continue
        made += 1
        mask, walk = got
        for cell, m in mask.items():
            if POP[m] not in (1, 2, 4):
                print("route grower      FAIL illegal fitting at %s" % (cell,))
                ok = False
                break
    print("route grower      OK (%d routes)" % made if ok else "")

    rng = random.Random(11)
    for size in (5, 6, 7):
        t0 = time.time()
        p = build_puzzle(size, size, rng, tries=4000, budget=180)
        if p is None:
            print("generator %dx%d    NO PUZZLE" % (size, size))
            ok = False
            continue
        errs = check_puzzle(p)
        if errs:
            print("puzzle %dx%d       FAIL -- %s" % (size, size, "; ".join(errs)))
            ok = False
        else:
            print("%dx%d unique, %2d cells, %d crossing(s), %.1fs  OK"
                  % (size, size, p["length"], p["crosses"], time.time() - t0))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--verify", action="store_true",
                    help="re-check data/puzzles.json and exit")
    ap.add_argument("--seed", type=int, default=20261126)
    ap.add_argument("--out", default=None)
    ap.add_argument("--budget", type=float, default=150.0,
                    help="seconds to spend per tier")
    args = ap.parse_args()

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = args.out or os.path.join(here, "data", "puzzles.json")

    if args.selftest:
        sys.exit(0 if selftest() else 1)

    if args.verify:
        with open(out) as f:
            data = json.load(f)
        bad = 0
        for p in data["puzzles"]:
            errs = check_puzzle(p)
            if errs:
                bad += 1
                print("  %-12s FAIL -- %s" % (p.get("name", "?"), "; ".join(errs)))
            else:
                print("  %-12s %dx%d  %2d cells, %d crossing(s)  OK"
                      % (p.get("name", "?"), p["w"], p["h"], p["length"],
                         p["crosses"]))
        print("\n%d/%d verified" % (len(data["puzzles"]) - bad, len(data["puzzles"])))
        sys.exit(1 if bad else 0)

    rng = random.Random(args.seed)
    tiers = [
        ("Warm-up", 5, 4, False),
        ("Easy", 6, 4, True),
        ("Medium", 7, 4, True),
        ("Tricky", 8, 4, True),
        ("Hard", 9, 3, True),
        ("Expert", 10, 3, True),
    ]

    puzzles = []
    for label, size, count, want_cross in tiers:
        made = 0
        t0 = time.time()
        while made < count and time.time() - t0 < args.budget:
            p = build_puzzle(size, size, rng, want_cross=want_cross,
                             budget=args.budget - (time.time() - t0))
            if p is None:
                continue
            if any(q["pieces"] == p["pieces"] for q in puzzles):
                continue
            p["tier"] = label
            p["name"] = "%s %d" % (label, made + 1)
            puzzles.append(p)
            made += 1
            print("  %-12s %dx%d  %2d cells, %d crossing(s)"
                  % (p["name"], size, size, p["length"], p["crosses"]))
            sys.stdout.flush()
        if made < count:
            print("  (%s: only made %d/%d inside the time budget)"
                  % (label, made, count))

    with open(out, "w") as f:
        json.dump({"version": 2, "puzzles": puzzles}, f, indent=1)
    print("\n%d puzzles -> %s" % (len(puzzles), out))


if __name__ == "__main__":
    main()
