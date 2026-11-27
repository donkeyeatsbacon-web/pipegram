#!/usr/bin/env python3
"""
Puzzle generator for PIPEGRAM.

RULES
-----
A single pipe runs from the INLET to the OUTLET. Every cell either holds a
pipe segment or is empty. Two pipe cells may be orthogonally adjacent ONLY if
the pipe actually connects them -- the pipe never runs alongside itself.

That one rule makes the whole thing work: if you know *which* cells hold pipe,
the piece in every cell is forced (its connections are exactly its filled
orthogonal neighbours). So the player solves a fill pattern, nonogram-style,
and the pipework draws itself.

Formally: the set of filled cells, with edges between orthogonally adjacent
members, must be a simple path whose two ends are the inlet and the outlet.

CLUES
-----
Nonogram run-length clues on every row and column: "3 1" means, reading that
row, a run of 3 pipe cells then a run of 1, with at least one empty cell
between them.

Every puzzle emitted here is verified to have EXACTLY ONE solution, so it is
always solvable by deduction and never by guessing.

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

DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))


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


def line_patterns(clue, width):
    """Every 0/1 tuple of `width` whose runs equal `clue`."""
    results = []

    def place(idx, pos, acc):
        if idx == len(clue):
            results.append(tuple(acc + [0] * (width - pos)))
            return
        run = clue[idx]
        last = idx == len(clue) - 1
        # leave room for this run plus the remaining runs and their gaps
        tail = sum(clue[idx + 1:]) + (len(clue) - idx - 1)
        for start in range(pos, width - run - tail + 1):
            nxt = acc + [0] * (start - pos) + [1] * run
            if not last:
                nxt = nxt + [0]
                place(idx + 1, start + run + 1, nxt)
            else:
                place(idx + 1, start + run, nxt)

    if not clue:
        return [tuple([0] * width)]
    place(0, 0, [])
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
# solver: counts solutions, stops once it finds `limit`
# --------------------------------------------------------------------------

class Solver:
    def __init__(self, w, h, row_clues, col_clues, inlet, outlet):
        self.w, self.h = w, h
        self.row_clues = row_clues
        self.col_clues = col_clues
        self.inlet = tuple(inlet)
        self.outlet = tuple(outlet)
        self.ends = {self.inlet, self.outlet}
        self.rowopts = [line_patterns(c, w) for c in row_clues]
        self.found = []

    # --- union-find over placed cells, with undo -------------------------
    def _find(self, a):
        while self.parent[a] != a:
            a = self.parent[a]
        return a

    def solve(self, limit=2):
        self.found = []
        self.parent = {}
        self.grid = [None] * self.h
        self._rec(0, [{(0, 0)} for _ in range(self.w)], limit)
        return self.found

    def _rec(self, r, colstates, limit):
        if len(self.found) >= limit:
            return
        if r == self.h:
            if all(col_done(s, c) for s, c in zip(colstates, self.col_clues)):
                if self._one_component():
                    self.found.append([row[:] for row in self.grid])
            return

        for pat in self.rowopts[r]:
            # inlet / outlet must carry pipe
            bad = False
            for (er, ec) in self.ends:
                if er == r and not pat[ec]:
                    bad = True
                    break
            if bad:
                continue

            # column clues must stay satisfiable
            nxt = []
            for c in range(self.w):
                s = col_step(colstates[c], pat[c], self.col_clues[c])
                if not s:
                    bad = True
                    break
                nxt.append(s)
            if bad:
                continue

            self.grid[r] = list(pat)
            saved = self._link_row(r)
            if saved is not None and self._degrees_ok(r):
                self._rec(r + 1, nxt, limit)
            self._unlink(saved)
            self.grid[r] = None
            if len(self.found) >= limit:
                return

    def _link_row(self, r):
        """Union row r's cells with their left/up neighbours. None on a cycle."""
        saved = []
        for c in range(self.w):
            if not self.grid[r][c]:
                continue
            self.parent[(r, c)] = (r, c)
            saved.append(('new', (r, c)))
            for (dr, dc) in ((0, -1), (-1, 0)):
                nr, nc = r + dr, c + dc
                if nr < 0 or nc < 0 or self.grid[nr] is None:
                    continue
                if not self.grid[nr][nc]:
                    continue
                a, b = self._find((r, c)), self._find((nr, nc))
                if a == b:              # closing a loop -- not a path
                    self._unlink(saved)
                    return None
                self.parent[a] = b
                saved.append(('link', a, b))
        return saved

    def _unlink(self, saved):
        if not saved:
            return
        for entry in reversed(saved):
            if entry[0] == 'new':
                self.parent.pop(entry[1], None)
            else:
                self.parent[entry[1]] = entry[1]

    def _degrees_ok(self, r):
        """Row r-1 now has all neighbours known -- check its pipe degrees.
        On the last row, check row h-1 too."""
        rows = [r - 1] if r < self.h - 1 else [r - 1, r]
        for rr in rows:
            if rr < 0:
                continue
            for c in range(self.w):
                if not self.grid[rr][c]:
                    continue
                deg = 0
                for (dr, dc) in DIRS:
                    nr, nc = rr + dr, c + dc
                    if 0 <= nr < self.h and 0 <= nc < self.w:
                        if self.grid[nr] is not None and self.grid[nr][nc]:
                            deg += 1
                want = 1 if (rr, c) in self.ends else 2
                if deg != want:
                    return False
        return True

    def _one_component(self):
        roots = set()
        for r in range(self.h):
            for c in range(self.w):
                if self.grid[r][c]:
                    roots.add(self._find((r, c)))
                    if len(roots) > 1:
                        return False
        return len(roots) == 1


# --------------------------------------------------------------------------
# random path generation
# --------------------------------------------------------------------------

def on_border(r, c, w, h):
    return r == 0 or c == 0 or r == h - 1 or c == w - 1


def random_path(w, h, target, rng):
    """Grow a pipe whose adjacency graph stays a simple path."""
    border = [(r, c) for r in range(h) for c in range(w) if on_border(r, c, w, h)]
    start = rng.choice(border)
    filled = {start}
    path = [start]

    while len(path) < target:
        r, c = path[-1]
        opts = []
        for (dr, dc) in DIRS:
            nr, nc = r + dr, c + dc
            if not (0 <= nr < h and 0 <= nc < w) or (nr, nc) in filled:
                continue
            # the new cell may touch the pipe only at the cell we came from
            clash = False
            for (ar, ac) in DIRS:
                ar, ac = nr + ar, nc + ac
                if (ar, ac) in filled and (ar, ac) != (r, c):
                    clash = True
                    break
            if not clash:
                opts.append((nr, nc))
        if not opts:
            break
        # lean towards keeping near the edges, it makes prettier plumbing
        nxt = rng.choice(opts)
        filled.add(nxt)
        path.append(nxt)

    return path


def build_puzzle(w, h, rng, lo=0.42, hi=0.62, tries=4000, want_border_end=True):
    """Return a puzzle dict with a verified-unique solution, or None."""
    best = None
    for attempt in range(tries):
        target = rng.randint(int(w * h * lo), max(int(w * h * hi), int(w * h * lo) + 1))
        path = random_path(w, h, target, rng)
        if len(path) < w * h * lo:
            continue
        if want_border_end and attempt < tries * 0.75:
            if not on_border(*path[-1], w, h):
                continue
        if len(path) < 4:
            continue

        grid = [[0] * w for _ in range(h)]
        for (r, c) in path:
            grid[r][c] = 1
        row_clues = [runs_of(grid[r]) for r in range(h)]
        col_clues = [runs_of([grid[r][c] for r in range(h)]) for c in range(w)]

        inlet, outlet = path[0], path[-1]
        s = Solver(w, h, row_clues, col_clues, inlet, outlet)
        sols = s.solve(limit=2)
        if len(sols) == 1:
            return {
                "w": w, "h": h,
                "row_clues": row_clues,
                "col_clues": col_clues,
                "inlet": list(inlet),
                "outlet": list(outlet),
                "solution": ["".join(str(b) for b in row) for row in grid],
                "length": len(path),
            }
        if best is None and sols:
            best = None
    return best


# --------------------------------------------------------------------------
# self test
# --------------------------------------------------------------------------

def selftest():
    ok = True

    assert runs_of([1, 1, 0, 1]) == [2, 1]
    assert runs_of([0, 0, 0]) == []
    assert line_patterns([], 3) == [(0, 0, 0)]
    assert len(line_patterns([1, 1], 4)) == 3
    assert set(line_patterns([2], 3)) == {(1, 1, 0), (0, 1, 1)}
    print("clue helpers      OK")

    rng = random.Random(7)
    # a generated puzzle's own solution must be the unique solution found
    for size in (5, 6, 7):
        p = build_puzzle(size, size, rng, tries=3000)
        if p is None:
            print(f"generator {size}x{size}  NO PUZZLE")
            ok = False
            continue
        s = Solver(p["w"], p["h"], p["row_clues"], p["col_clues"],
                   p["inlet"], p["outlet"])
        sols = s.solve(limit=3)
        want = [[int(ch) for ch in row] for row in p["solution"]]
        if len(sols) != 1 or sols[0] != want:
            print(f"uniqueness {size}x{size}  FAIL ({len(sols)} solutions)")
            ok = False
        else:
            # verify the no-parallel path property of the solution itself
            cells = {(r, c) for r in range(p["h"]) for c in range(p["w"]) if want[r][c]}
            ends = {tuple(p["inlet"]), tuple(p["outlet"])}
            for (r, c) in cells:
                deg = sum(1 for (dr, dc) in DIRS if (r + dr, c + dc) in cells)
                if deg != (1 if (r, c) in ends else 2):
                    print(f"path shape {size}x{size}  FAIL at {(r, c)} deg {deg}")
                    ok = False
                    break
            else:
                print(f"{size}x{size} unique, len {p['length']:2d}  OK")
    return ok


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--seed", type=int, default=20261126)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    if args.selftest:
        sys.exit(0 if selftest() else 1)

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = args.out or os.path.join(here, "data", "puzzles.json")

    rng = random.Random(args.seed)
    # (label, size, how many)
    tiers = [
        ("Warm-up", 5, 4),
        ("Easy", 6, 4),
        ("Medium", 7, 4),
        ("Tricky", 8, 4),
        ("Hard", 9, 3),
        ("Expert", 10, 3),
    ]

    puzzles = []
    for label, size, count in tiers:
        made = 0
        t0 = time.time()
        while made < count and time.time() - t0 < 120:
            p = build_puzzle(size, size, rng)
            if p is None:
                continue
            # no duplicates
            if any(q["solution"] == p["solution"] for q in puzzles):
                continue
            p["tier"] = label
            p["name"] = f"{label} {made + 1}"
            puzzles.append(p)
            made += 1
            print(f"  {p['name']:<12} {size}x{size}  pipe length {p['length']}")
        if made < count:
            print(f"  ({label}: only made {made}/{count} inside the time budget)")

    with open(out, "w") as f:
        json.dump({"version": 1, "puzzles": puzzles}, f, indent=1)
    print(f"\n{len(puzzles)} puzzles -> {out}")


if __name__ == "__main__":
    main()
