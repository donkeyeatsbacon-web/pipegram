extends Node2D
##
## PIPEGRAM -- prototype
##
## Pipe Dream's plumbing, a nonogram's clues.
##
## One pipe runs from the inlet to the outlet. The numbers down the side and
## across the top are nonogram run-length clues: how many pipe cells sit in a
## line, in order, with a gap between runs.
##
## The pipe NEVER runs alongside itself: touching pipe cells are always
## joined. So the only thing you decide is whether a cell carries pipe. The
## fitting in it is not a choice -- it is read off the joints the cell has,
## and redrawn the moment a neighbour changes.
##
## Nothing branches, nothing dead-ends: the inlet and the outlet have one
## joint each, every other pipe cell exactly two. Formally the filled cells
## form a simple path from the inlet to the outlet.
##
## Both taps are drawn as spigots facing the way their pipe leaves, so the
## first and last joint are given to you.
##

var VW := 760.0            # design viewport, swapped for landscape layouts
var VH := 1080.0

# cell marks -- the fill layer
const UNKNOWN := 0
const PIPE := 1
const BLOCKED := 2

# A fitting is a bitmask of the sides it opens onto, in DIRS order.
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const BITS := [1, 2, 4, 8]                 # N E S W
const MASK_NONE := 0                       # pipe laid, nothing joined onto it

# tools. Two, and only two: a cell either carries pipe or it does not. The
# shape of the fitting is not a choice -- it follows from which neighbours the
# cell ends up joined to, and is redrawn whenever that changes.
const TOOL_PIPE := 0
const TOOL_EMPTY := 1      # cross it off

# modes
const MODE_ZEN := 0                # no clock, solve it in your own time
const MODE_FLOW := 1               # the water is coming

# --- layout variants -------------------------------------------------------
# Every screen arrangement worth trying, each playable so it can be judged by
# playing rather than by looking at a picture. Press L for the picker.
const HDR_FULL := 0        # title, tagline, label, clue, timer, flow line
const HDR_TIGHT := 1       # one title line plus a single status strip
const HDR_CHIP := 2        # just a thin strip; the board takes the rest

const CHROME_ROWS := 0     # palette row over a nav row -- what we have now
const CHROME_PANEL := 1    # palette raised on a panel, nav dimmed to chrome
const CHROME_BAR := 2      # one tool chip; the palette slides up on demand
const CHROME_PAD := 3      # 3x3 thumb pad in the corner, nav beside it
const CHROME_NONE := 4     # no palette at all -- the input carries it
const CHROME_SIDE := 5     # columns down both edges, for landscape
const CHROME_TRAY := 6     # a workbench parts tray

const IN_PALETTE := 0      # pick pipe or empty, tap to place
const IN_CYCLE := 1        # no palette: a tap cycles unknown -> pipe -> empty

const TOOL_NAMES := ["pipe", "empty"]
const TOOL_ACTIONS := ["tool_pipe", "tool_empty"]
const RULE_LINE := "the pipe never runs alongside itself — touching pipe cells are always joined"

var LAYOUTS: Array = [
	{"name": "As it is now", "tier": "baseline",
	 "note": "the arrangement you have been playing"},
	{"name": "Tight header", "tier": "slight", "hdr": HDR_TIGHT,
	 "note": "title and status on two lines — about 80px back into the board"},
	{"name": "Clear hierarchy", "tier": "slight", "chrome": CHROME_PANEL,
	 "note": "the two tools raised on their own panel, the rest dimmed"},
	{"name": "Board into the banner", "tier": "slight", "grow": true,
	 "note": "the dead win/lose strip given to the board; banner overlays it"},
	{"name": "Bigger board, tight header", "tier": "slight",
	 "hdr": HDR_TIGHT, "grow": true,
	 "note": "both cheap wins at once — the largest board without moving a button"},
	{"name": "Thumb pad", "tier": "moderate", "chrome": CHROME_PAD,
	 "note": "every button in one block under your thumb, nothing up top"},
	{"name": "Pressure ring", "tier": "moderate", "ring": true,
	 "note": "the Flow countdown drawn around the water's head, not up top"},
	{"name": "Clue rails all round", "tier": "moderate", "rails": true,
	 "note": "clues repeated right and bottom so one is always near your work"},
	{"name": "Landscape, two-handed", "tier": "radical",
	 "land": true, "chrome": CHROME_SIDE, "hdr": HDR_TIGHT,
	 "note": "board centred, tools under the left thumb, utilities right"},
	{"name": "Board first", "tier": "radical",
	 "hdr": HDR_CHIP, "chrome": CHROME_BAR, "grow": true,
	 "note": "board fills the screen; the controls slide up when you want them"},
	{"name": "No palette, tap to cycle", "tier": "radical",
	 "input": IN_CYCLE, "chrome": CHROME_NONE, "grow": true,
	 "note": "a tap cycles blank → pipe → crossed off; no palette to aim at"},
	{"name": "Workbench", "tier": "radical",
	 "chrome": CHROME_TRAY, "hdr": HDR_TIGHT,
	 "note": "blueprint on a bench, tools in a parts tray, a pressure gauge"},
	{"name": "Recommended: 1 + 2 + 3 + 6", "tier": "combination",
	 "hdr": HDR_TIGHT, "chrome": CHROME_PANEL, "grow": true, "ring": true,
	 "note": "the cheap wins plus the pressure ring, all together"},
]

# Flow timings. These are the dials to turn after a playtest: they decide
# whether this is tense or merely unfair.
const GRACE_BASE := 40.0           # thinking time before the water sets off
const GRACE_PER_CELL := 1.5        # ...plus this much per cell of pipe
const FLOW_SPC := 0.55             # seconds the water takes to cross a cell
const PRESSURE_SECONDS := 12.0     # grace once the water catches you up
#
# The real clock is PRESSURE_SECONDS, not the flow speed: the water spends most
# of its time sitting at your frontier, so what the game actually asks is "lay
# the next cell of the route every PRESSURE_SECONDS". The flow speed only
# decides how it looks getting there, and it wants to look like water.

# --- palette --------------------------------------------------------------
const C_BG          := Color("13161c")
const C_PANEL       := Color("1b202a")
const C_CELL        := Color("222835")
const C_CELL_ALT    := Color("262d3b")
const C_GRID        := Color("323b4d")
const C_GRID_BOLD   := Color("46526b")
const C_PIPE_SHADOW := Color("27160a")   # the rim that separates pipe from board
const C_PIPE_DARK   := Color("6b4420")   # underside of the tube
const C_PIPE        := Color("b87c41")   # body
const C_PIPE_LIGHT  := Color("dda268")   # lit side
const C_PIPE_HI     := Color("f2d2a6")   # specular streak
const C_FLANGE      := Color("8c5e2e")   # collars at the section joins
const C_WATER_DEEP  := Color("1c6f9e")   # shaded edge of the channel
const C_WATER       := Color("3fb6e8")
const C_WATER_HI    := Color("9fe4ff")
const C_BLOCK       := Color("4b5568")
const C_TEXT        := Color("dfe5ef")
const C_TEXT_DIM    := Color("6f7a8e")
const C_TEXT_DONE   := Color("46526b")
const C_BAD         := Color("e2566a")
const C_GOOD        := Color("6fd08c")
const C_ACCENT      := Color("f0b45e")
const C_BTN         := Color("2a3240")
const C_BTN_HOT     := Color("3a4556")
const C_BENCH       := Color("2b2118")   # workbench: the bench itself
const C_BENCH_DARK  := Color("1d160f")
const C_BP_PANEL    := Color("17344a")   # workbench: blueprint paper
const C_BP_CELL     := Color("1b3d57")
const C_BP_ALT      := Color("1e4460")

# --- state ----------------------------------------------------------------
var font: Font
var puzzles: Array = []
var index := 0

var W := 0
var H := 0
var row_clues: Array = []
var col_clues: Array = []
var inlet := Vector2i.ZERO
var outlet := Vector2i.ZERO
var solution: Dictionary = {}      # Vector2i -> fitting mask
var sol_walk: Array = []           # the route in order; a cross appears twice

var marks: Array = []              # marks[y][x]: UNKNOWN / PIPE / BLOCKED
var pieces: Array = []             # pieces[y][x]: derived mask, 0 = no joints
var undo_stack: Array = []

var solved := false
var elapsed := 0.0

# The water's route is the player's own pipework, traced from the inlet
# through whatever fittings they have laid. Recomputed on every change.
var route: Array = []              # cells the water passes through, in order
var route_fault := -1              # index where it leaves the real route

# --- flow mode -------------------------------------------------------------
# Pipe Dream's pressure, adapted to a route you deduce rather than build.
# After a thinking period the water sets off from the inlet and follows the
# fittings you have actually laid. Two ways to drown:
#   * it runs out of pipework and the pressure builds until a joint goes;
#   * it is routed somewhere the real pipe never went -- a leak. A wrong
#     fitting only bites once the water gets to it.
var mode := MODE_FLOW
var lost := false
var zen_locked := false            # this puzzle has been dropped to Zen for good
var flowing := false               # grace is over, water is on the move
var grace_left := 0.0
var flow_pos := 0.0                # how far along `route` the water has got
var flow_spc := 4.0                # seconds per cell
var pressure_left := 0.0
var burst_cell := Vector2i(-1, -1)
var burst_leak := false            # a leak, rather than the pressure
# Off by default on purpose: flagging a wrong pipe the moment it is laid hands
# the player the deduction they came to make. Opt in with the button or M.
var show_errors := false
var hint_cells: Dictionary = {}    # cells given away by Hint

# the active layout
var layout := 0
var L: Dictionary = {}
var head_h := 208.0               # height the header reserves
var ctrl_h := 176.0               # height the controls reserve at the bottom
var banner_gap := 90.0            # the strip the win/lose banner sits in
var side_w := 0.0                 # columns down each edge, for landscape
var picking := false              # the layout picker is open
var bar_open := false             # CHROME_BAR: the palette is slid up
var last_painted := Vector2i(-1, -1)

# geometry, recomputed per puzzle
var cell := 48.0
var origin := Vector2.ZERO
var gutter := 90.0
var gutter_l := 90.0
var gutter_t := 90.0
var gutter_r := 0.0
var gutter_b := 0.0
var clue_font := 18

# input
var tool := TOOL_PIPE
var dragging := false
var drag_fill := UNKNOWN           # what a fill-tool drag is painting
var painted: Dictionary = {}
var hover := Vector2i(-1, -1)
var buttons: Array = []
var pipe_flanges: Array = []       # collars, drawn over the water
var mouse := Vector2.ZERO

# headless screenshot mode
var shot_path := ""
var shot_solve := false
var shot_flow := false
var shot_press := false
var logic_test := false
var layout_audit := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	_parse_args()
	_load_puzzles()
	if puzzles.is_empty():
		push_error("No puzzles found at res://data/puzzles.json -- run tools/generate.py")
		return
	if logic_test:
		_apply_layout()
		_logic_test()
		return
	_apply_layout()
	_load_puzzle(index)
	if layout_audit:
		await _audit_all()
		return
	if shot_path != "":
		await _take_shot()


# =========================================================================
#  fittings
# =========================================================================

func _pop(m: int) -> int:
	var n := 0
	while m != 0:
		n += m & 1
		m >>= 1
	return n


func _bit_of_dir(d: Vector2i) -> int:
	var i: int = DIRS.find(d)
	return BITS[i] if i >= 0 else 0


func _dir_of_bit(b: int) -> Vector2i:
	var i: int = BITS.find(b)
	return DIRS[i] if i >= 0 else Vector2i.ZERO


func _opp_bit(b: int) -> int:
	return ((b << 2) | (b >> 2)) & 15


func _derive_mask(c: Vector2i, filled: Callable) -> int:
	## A cell's fitting is not chosen, it is read off: one bit for every
	## orthogonal neighbour that also carries pipe. Under this game's rule
	## touching pipe cells are always joined, so this is the whole of it.
	var m := 0
	for i in 4:
		if filled.call(c + DIRS[i]):
			m |= BITS[i]
	return m


func _derive_pieces() -> void:
	## Recompute every laid cell's shape. Called after any change to the
	## marks, so a cell's fitting always matches the joints it actually has.
	var filled := func(n: Vector2i) -> bool: return _mark_at(n) == PIPE
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			pieces[y][x] = _derive_mask(c, filled) if marks[y][x] == PIPE else MASK_NONE


func _walk_solution() -> Array:
	## Walk the finished pipework from the inlet. With touching cells always
	## joined there is exactly one way through, so this is the route the water
	## will take.
	var out: Array = [inlet]
	if not solution.has(inlet):
		return out
	var prev := Vector2i(-1, -1)
	var cur := inlet
	var guard := W * H + 8
	while guard > 0 and cur != outlet:
		guard -= 1
		var m := int(solution[cur])
		var moved := false
		for i in 4:
			if (m & BITS[i]) == 0:
				continue
			var n: Vector2i = cur + DIRS[i]
			if n == prev:
				continue
			prev = cur
			cur = n
			out.append(cur)
			moved = true
			break
		if not moved:
			break
	return out


# =========================================================================
#  tests
# =========================================================================

func _lay_solution() -> void:
	for c in solution:
		_set_fill(c, PIPE)
	_after_change()


func _flow_test(i: int) -> Array[String]:
	## Drive flow mode through its endings: the water gets home, the water
	## catches up and bursts, the water is routed into pipe that was never on
	## the route and bursts there.
	var errs: Array[String] = []
	var step := 0.25
	mode = MODE_FLOW

	# 1. the whole route laid -- the water should get home
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	_lay_solution()
	solved = false                 # ignore the exact-match win; test the water
	var guard := 0
	while not solved and not lost and guard < 20000:
		_flow_step(step)
		guard += 1
	if lost:
		errs.append("water burst on a fully laid route")
	elif not solved:
		errs.append("water never reached the outlet")

	# 2. nothing laid beyond the inlet -- pressure should burst it
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	guard = 0
	while not lost and guard < 20000:
		_flow_step(step)
		guard += 1
	if not lost:
		errs.append("water never burst with no pipe laid")
	elif burst_leak:
		errs.append("an empty board was called a leak")

	# 3. a wrong cell hung off the route -- the water should escape there
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	_lay_solution()
	# The spare cell has to touch exactly ONE route cell, and not a tap. A cell
	# wedged against two of them makes several bad junctions at once and there
	# is no single place the water is owed to escape -- it would assert
	# whichever one the walk happened to reach first.
	var diverted := false
	var junction := Vector2i(-1, -1)
	for y in H:
		for x in W:
			var n := Vector2i(x, y)
			if solution.has(n) or _is_given(n):
				continue
			var touches: Array[Vector2i] = []
			for b in BITS:
				var t: Vector2i = n + _dir_of_bit(b)
				if solution.has(t):
					touches.append(t)
			if touches.size() != 1:
				continue
			var c: Vector2i = touches[0]
			if c == inlet or c == outlet:
				continue
			_set_fill(n, PIPE)
			junction = c
			diverted = true
			break
		if diverted:
			break
	_after_change()
	if not diverted:
		errs.append("could not build a leak to test")
	else:
		solved = false
		guard = 0
		while not lost and guard < 20000:
			_flow_step(step)
			guard += 1
		if not lost:
			errs.append("water ignored a wrong cell hung off the route")
		elif not burst_leak:
			errs.append("a wrong junction was reported as pressure")
		elif burst_cell != junction:
			errs.append("the water escaped at %s, not the bad junction %s"
					% [str(burst_cell), str(junction)])

	# 4. dropping to Zen must not hand back a fresh clock
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	for k in range(1, mini(6, sol_walk.size())):
		_set_fill(sol_walk[k], PIPE)
	_after_change()
	for _n in 8:
		_flow_step(step)
	var pos_before := flow_pos
	var route_before := route.size()
	_do_action("mode")
	if mode != MODE_ZEN or not zen_locked:
		errs.append("Flow did not drop to Zen")
	if route.size() != route_before:
		errs.append("dropping to Zen disturbed the board")
	_flow_step(step)
	if not is_equal_approx(flow_pos, pos_before):
		errs.append("water kept moving in Zen")
	_do_action("mode")                  # try to cheat back into Flow
	if mode != MODE_ZEN:
		errs.append("Zen lock let the player back into Flow")
	if grace_left > 0.0:
		errs.append("mode toggle handed back " + str(grace_left) + "s of clock")

	mode = MODE_FLOW
	_load_puzzle(i)
	return errs


func _rule_test() -> Array[String]:
	## The one rule the whole puzzle rests on: touching pipe cells are always
	## joined, so every pipe cell has exactly two pipe neighbours and the two
	## taps have exactly one. If that fails the puzzle is not solvable as
	## stated, whatever the clues say.
	var errs: Array[String] = []
	var ends := 0
	for c in solution:
		var n := _sol_neighbours(c)
		var want := 1 if (c == inlet or c == outlet) else 2
		if n != want:
			errs.append("cell %s has %d pipe neighbours, wants %d"
					% [str(c), n, want])
			break
		if n == 1:
			ends += 1
	if ends != 2:
		errs.append("the run has %d ends, not 2" % ends)

	# and the walk really does visit every cell of the fill, once
	if sol_walk.size() != solution.size():
		errs.append("the route walks %d cells, the fill has %d"
				% [sol_walk.size(), solution.size()])
	var seen := {}
	for c in sol_walk:
		if seen.has(c):
			errs.append("the route visits %s twice" % str(c))
			break
		seen[c] = true
	return errs


func _sol_neighbours(c: Vector2i) -> int:
	## How many pipe cells touch this one in the ANSWER.
	var n := 0
	for d in DIRS:
		if solution.has(c + d):
			n += 1
	return n


func _laid_neighbours(c: Vector2i) -> int:
	## How many pipe cells touch this one on the BOARD AS PLAYED. Reading the
	## answer here instead was the bug that let a three-way junction burst as
	## pressure: in the answer the cell has two joints, so the leak never fired.
	var n := 0
	for d in DIRS:
		if _mark_at(c + d) == PIPE:
			n += 1
	return n


func _logic_test() -> void:
	## Play every puzzle through the same calls the mouse uses. The screenshot
	## path can only show what is drawn, so it cannot catch anything the real
	## editing path gets wrong -- which is how the unlaid-taps bug survived a
	## visual check.
	var fails := 0
	for i in puzzles.size():
		_load_puzzle(i)
		var pname: String = str(puzzles[index].get("name", "?"))
		var errs: Array[String] = []

		# The taps have to be real pipe in the grid, not just drawn on top.
		# Their SHAPE is not checked here: a tap's joint is derived from its
		# neighbour, and on a fresh board that neighbour is not laid yet, so a
		# bare valve is the correct drawing. What must hold is that the spigot
		# still knows which way the pipe leaves -- that is the free foothold.
		if _mark_at(inlet) != PIPE:
			errs.append("inlet not laid as real pipe")
		if _mark_at(outlet) != PIPE:
			errs.append("outlet not laid as real pipe")
		if _tap_dir(inlet) == Vector2.ZERO:
			errs.append("inlet spigot faces nowhere")
		if _tap_dir(outlet) == Vector2.ZERO:
			errs.append("outlet spigot faces nowhere")

		errs.append_array(_rule_test())

		# lay it the way a player does, through _set_fill
		_load_puzzle(i)
		_lay_solution()
		_check_solved()
		if not solved:
			errs.append("never registers as solved")
		if route != sol_walk:
			errs.append("the laid pipework traces " + str(route.size())
					+ " cells, the route is " + str(sol_walk.size()))
		if route_fault != -1:
			errs.append("the real route reads as faulty")

		errs.append_array(_flow_test(i))

		if errs.is_empty():
			print("  " + pname + ": OK  (" + str(solution.size()) + " cells)")
		else:
			fails += 1
			print("  " + pname + ": FAIL -- " + ", ".join(errs))

	print("")
	print(str(puzzles.size() - fails) + "/" + str(puzzles.size())
			+ " puzzles playable from inlet to outlet")
	get_tree().quit(1 if fails > 0 else 0)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--screenshot":
				if i + 1 < args.size():
					shot_path = args[i + 1]
			"--puzzle":
				if i + 1 < args.size():
					index = int(args[i + 1])
			"--solved":
				shot_solve = true
			"--logictest":
				logic_test = true
			"--layoutaudit":
				layout_audit = true
			"--flow":
				shot_flow = true
			"--pressure":
				shot_press = true
			"--zen":
				mode = MODE_ZEN
			"--layout":
				if i + 1 < args.size():
					layout = int(args[i + 1])


func _load_puzzles() -> void:
	var f := FileAccess.open("res://data/puzzles.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("puzzles"):
		puzzles = parsed["puzzles"]
	# The fill lives in "solution", one row of 0/1 per line. A file from the
	# short-lived fittings generator has "pieces" instead, and loading it
	# would fail obscurely rather than say why.
	if not puzzles.is_empty():
		var first: Dictionary = puzzles[0]
		if not first.has("solution"):
			push_error("data/puzzles.json has no \"solution\" -- it is from the "
					+ "fittings generator. Run: heavy python3 tools/generate.py")
			puzzles = []


func _load_puzzle(i: int) -> void:
	index = wrapi(i, 0, puzzles.size())
	var p: Dictionary = puzzles[index]

	W = int(p["w"])
	H = int(p["h"])
	row_clues = p["row_clues"]
	col_clues = p["col_clues"]
	inlet = Vector2i(int(p["inlet"][1]), int(p["inlet"][0]))    # json is [row, col]
	outlet = Vector2i(int(p["outlet"][1]), int(p["outlet"][0]))
	# The fill is the puzzle. Each cell's shape follows from its neighbours,
	# so the solution masks are derived here exactly as the player's are.
	var fill := {}
	var rows: Array = p["solution"]
	for y in H:
		var line: String = rows[y]
		for x in W:
			if line.substr(x, 1) == "1":
				fill[Vector2i(x, y)] = true
	solution.clear()
	var in_fill := func(n: Vector2i) -> bool: return fill.has(n)
	for c in fill:
		solution[c] = _derive_mask(c, in_fill)

	sol_walk = _walk_solution()

	marks = []
	pieces = []
	for y in H:
		var row := []
		row.resize(W)
		row.fill(UNKNOWN)
		marks.append(row)
		var prow := []
		prow.resize(W)
		prow.fill(MASK_NONE)
		pieces.append(prow)

	undo_stack.clear()
	hint_cells.clear()
	solved = false
	elapsed = 0.0

	lost = false
	zen_locked = false             # the lock is per puzzle, not for the session
	flowing = false
	flow_pos = 0.0
	burst_cell = Vector2i(-1, -1)
	burst_leak = false
	pressure_left = PRESSURE_SECONDS
	grace_left = GRACE_BASE + GRACE_PER_CELL * float(sol_walk.size())
	flow_spc = FLOW_SPC

	# The taps are given and must be real pipe in the grid, not just drawn on
	# top. Written straight in, because _set_fill refuses cells _is_given()
	# covers and that includes the taps -- going through it left them unlaid,
	# so nothing could ever join onto them.
	marks[inlet.y][inlet.x] = PIPE
	marks[outlet.y][outlet.x] = PIPE
	_derive_pieces()

	_retrace()
	_layout()
	queue_redraw()


func _lay(key: String, dflt: Variant) -> Variant:
	return L.get(key, dflt)


func _chrome() -> int:
	return int(_lay("chrome", CHROME_ROWS))


func _input_mode() -> int:
	return int(_lay("input", IN_PALETTE))


func _apply_layout() -> void:
	## Turn the chosen variant into the handful of numbers the rest of the
	## drawing works from. Nothing below here knows a layout's name.
	layout = wrapi(layout, 0, LAYOUTS.size())
	L = LAYOUTS[layout]

	if bool(_lay("land", false)):
		VW = 1080.0
		VH = 760.0
	else:
		VW = 760.0
		VH = 1080.0
	var win := get_window()
	if win != null:
		win.content_scale_size = Vector2i(int(VW), int(VH))

	match int(_lay("hdr", HDR_FULL)):
		HDR_TIGHT: head_h = 124.0
		HDR_CHIP: head_h = 58.0
		_: head_h = 208.0

	side_w = 0.0
	banner_gap = 0.0 if bool(_lay("grow", false)) else 90.0
	match _chrome():
		CHROME_PANEL: ctrl_h = 182.0
		CHROME_BAR:
			ctrl_h = 66.0
			banner_gap = 0.0
		CHROME_PAD:
			ctrl_h = 240.0
			banner_gap = 0.0
		CHROME_NONE: ctrl_h = 92.0
		CHROME_SIDE:
			# 54 of these are the tip and rule lines at the foot of the screen.
			# Declaring 0 let the board run to the very edge and the text then
			# landed on its bottom row.
			ctrl_h = 54.0
			side_w = 172.0
			banner_gap = 0.0
		CHROME_TRAY: ctrl_h = 174.0
		_: ctrl_h = 176.0

	bar_open = false
	if W > 0:
		_layout()
	queue_redraw()


func _banner_rect() -> Rect2:
	## One formula for every layout. Where the board has eaten the strip, the
	## banner simply lands on top of the board instead.
	return Rect2(20.0, VH - ctrl_h - 90.0, VW - 40.0, 80.0)


func _layout() -> void:
	var avail_w := VW - 40.0 - side_w * 2.0
	var top := head_h
	var avail_h := (VH - ctrl_h - banner_gap) - top
	var rails: bool = bool(_lay("rails", false))

	# The gutters have to hold the longest clue in either direction, so size
	# the cells and the gutters together: two passes settle it.
	gutter_l = 86.0
	gutter_t = 86.0
	gutter_r = 86.0 if rails else 0.0
	gutter_b = 86.0 if rails else 0.0
	if font == null:          # headless logic runs have no font to measure
		cell = min((avail_w - gutter_l - gutter_r) / float(W),
				(avail_h - gutter_t - gutter_b) / float(H))
		origin = Vector2(20.0 + side_w + gutter_l, top + gutter_t)
		gutter = gutter_l
		return
	for _pass in 2:
		cell = min((avail_w - gutter_l - gutter_r) / float(W),
				(avail_h - gutter_t - gutter_b) / float(H))
		cell = min(cell, 104.0)
		clue_font = int(clampf(cell * 0.33, 13.0, 25.0))

		var widest := 0.0
		for y in H:
			var clue: Array = row_clues[y]
			var txt := "0"
			if not clue.is_empty():
				var parts := []
				for n in clue:
					parts.append(str(int(n)))
				txt = " ".join(parts)
			widest = maxf(widest, font.get_string_size(
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, clue_font).x)
		var tallest := 1
		for x in W:
			tallest = maxi(tallest, (col_clues[x] as Array).size())

		gutter_l = clampf(widest + 26.0, 54.0, 150.0)
		gutter_t = clampf(14.0 + tallest * (clue_font + 3.0) + 8.0, 54.0, 150.0)
		gutter_r = gutter_l if rails else 0.0
		gutter_b = gutter_t if rails else 0.0

	var board_w := cell * W
	var board_h := cell * H
	origin = Vector2(
			20.0 + side_w + (avail_w - (board_w + gutter_l + gutter_r)) * 0.5 + gutter_l,
			top + (avail_h - (board_h + gutter_t + gutter_b)) * 0.5 + gutter_t)
	gutter = gutter_l


# =========================================================================
#  the board
# =========================================================================

func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func _mark_at(c: Vector2i) -> int:
	if not _in_grid(c):
		return BLOCKED       # outside the grid counts as "no pipe"
	return marks[c.y][c.x]


func _piece_at(c: Vector2i) -> int:
	if not _in_grid(c):
		return MASK_NONE
	return pieces[c.y][c.x]


func _is_given(c: Vector2i) -> bool:
	return c == inlet or c == outlet or hint_cells.has(c)


func _record(c: Vector2i) -> void:
	undo_stack.push_back([c, marks[c.y][c.x], pieces[c.y][c.x]])
	if undo_stack.size() > 600:
		undo_stack.pop_front()


func _set_fill(c: Vector2i, v: int, record := true) -> void:
	## Lay or clear plain pipe. Clearing takes the fitting with it.
	if not _in_grid(c) or _is_given(c):
		return
	var keep: int = pieces[c.y][c.x] if v == PIPE else MASK_NONE
	if marks[c.y][c.x] == v and pieces[c.y][c.x] == keep:
		return
	if record:
		_record(c)
	marks[c.y][c.x] = v
	pieces[c.y][c.x] = keep


func _undo() -> void:
	if undo_stack.is_empty() or solved:
		return
	var e: Array = undo_stack.pop_back()
	var c: Vector2i = e[0]
	marks[c.y][c.x] = e[1]
	pieces[c.y][c.x] = e[2]
	_after_change()


# =========================================================================
#  clue checking
# =========================================================================

func _runs(bits: Array) -> Array:
	var out := []
	var n := 0
	for b in bits:
		if b:
			n += 1
		elif n > 0:
			out.append(n)
			n = 0
	if n > 0:
		out.append(n)
	return out


func _row_bits(y: int) -> Array:
	var out := []
	for x in W:
		out.append(1 if marks[y][x] == PIPE else 0)
	return out


func _col_bits(x: int) -> Array:
	var out := []
	for y in H:
		out.append(1 if marks[y][x] == PIPE else 0)
	return out


func _clue_done(clue: Array, bits: Array) -> bool:
	var r := _runs(bits)
	if r.size() != clue.size():
		return false
	for i in r.size():
		if int(r[i]) != int(clue[i]):
			return false
	return true


func _trace_player() -> Array:
	## Follow the water out of the inlet, through the fittings the player has
	## actually laid, until the pipework stops carrying it. A cross appears
	## twice, once per pass, exactly as the real route does.
	var out: Array = [inlet]
	if _piece_at(inlet) == MASK_NONE:
		return out                 # nothing joined onto the valve yet
	# The valve's direction is a given -- it is drawn on the spigot. Taking it
	# from the joints instead made the water's exit arbitrary when a player had
	# pipe on both sides of the valve: it would follow whichever joint sorted
	# lowest, which is not something the board shows.
	var d := Vector2i(_tap_dir(inlet))
	if d == Vector2i.ZERO:
		return out
	var guard := W * H + 8
	while guard > 0:
		guard -= 1
		var cur: Vector2i = out[out.size() - 1]
		var n: Vector2i = cur + d
		if _mark_at(n) != PIPE:
			break
		var nm := _piece_at(n)
		var entry := _opp_bit(_bit_of_dir(d))
		if (nm & entry) == 0:
			break                  # nothing on that side to join onto
		out.append(n)
		var pc := _pop(nm)
		if pc == 2:
			d = _dir_of_bit(nm & ~entry)
		else:
			# One joint is an end: the outlet, or a stub going nowhere. Three
			# or more is a tee the route never has, and the water does not get
			# through it -- it escapes. Either way the walk stops here.
			break
	return out


func _retrace() -> void:
	route = _trace_player()
	route_fault = -1
	for i in route.size():
		if i >= sol_walk.size() or route[i] != sol_walk[i]:
			route_fault = i
			break
	if route_fault >= 0 or route.is_empty():
		return

	# Every cell can be a route cell and the pipework still leak: hang a spare
	# cell off one of them and it has three joints where the route has two. The
	# water escapes at that junction -- the player's own mistake, and it gives
	# nothing away about the answer. A tap takes only one joint, so laying pipe
	# on both sides of the valve leaks at the valve.
	for i in route.size():
		var c: Vector2i = route[i]
		var want := 1 if (c == inlet or c == outlet) else 2
		if _laid_neighbours(c) > want:
			route_fault = i
			return


func _route_complete() -> bool:
	return route_fault == -1 and route.size() == sol_walk.size()


func _burst(c: Vector2i, leak: bool) -> void:
	lost = true
	burst_cell = c
	burst_leak = leak
	queue_redraw()


func _flow_step(delta: float) -> void:
	if mode != MODE_FLOW or solved or lost or sol_walk.is_empty():
		return

	if grace_left > 0.0:
		grace_left -= delta
		if grace_left > 0.0:
			return
		flowing = true

	# The water can run to the end of the pipework it has, but no further than
	# the first cell the real route never went through -- that is the leak.
	var last := float(route.size() - 1)
	var limit := last if route_fault < 0 else float(route_fault)

	if flow_pos < limit:
		flow_pos = minf(flow_pos + delta / flow_spc, limit)
		pressure_left = PRESSURE_SECONDS

	if route_fault >= 0 and flow_pos >= limit - 0.0001:
		_burst(route[route_fault], true)
		return

	if flow_pos >= last - 0.0001:
		if _route_complete():
			solved = true
			return
		# caught up with the plumbing -- the pressure starts to tell
		pressure_left -= delta
		if pressure_left <= 0.0:
			_burst(route[route.size() - 1], false)


func _check_solved() -> void:
	## Every pipe cell laid and nothing else. The generator guarantees one
	## solution, so this is exactly "clues satisfied and the pipework joins
	## the inlet to the outlet"; the shapes follow from the fill, so there is
	## nothing else left to get right.
	var count := 0
	for y in H:
		for x in W:
			if marks[y][x] != PIPE:
				continue
			count += 1
			if not solution.has(Vector2i(x, y)):
				return
	if count == solution.size():
		solved = true
		if mode == MODE_ZEN:
			flow_pos = 0.0


# =========================================================================
#  input
# =========================================================================

func _cell_from_point(p: Vector2) -> Vector2i:
	var rel := p - origin
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)
	var c := Vector2i(int(rel.x / cell), int(rel.y / cell))
	return c if _in_grid(c) else Vector2i(-1, -1)


func _cycle_cell(c: Vector2i, by: int) -> void:
	## No palette: a tap walks the cell round blank -> pipe -> crossed off.
	if _is_given(c):
		return
	var order := [UNKNOWN, PIPE, BLOCKED]
	var at: int = order.find(_mark_at(c))
	_set_fill(c, int(order[posmod((at if at >= 0 else 0) + by, order.size())]))


func _press_cell(c: Vector2i, secondary: bool, _at: Vector2) -> void:
	if _input_mode() == IN_CYCLE:
		_cycle_cell(c, -1 if secondary else 1)
		drag_fill = -2
		return

	var want: int = PIPE if tool == TOOL_PIPE else BLOCKED
	if secondary:
		want = BLOCKED if want == PIPE else PIPE
	if _is_given(c):
		drag_fill = want
	else:
		# pressing a cell that already has this mark rubs it out
		drag_fill = UNKNOWN if marks[c.y][c.x] == want else want
	_set_fill(c, drag_fill)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = get_global_mouse_position()
		var c := _cell_from_point(mouse)
		if c != hover:
			hover = c
			queue_redraw()
		if dragging and _in_grid(c) and not painted.has(c):
			painted[c] = true
			if drag_fill >= 0:
				_set_fill(c, drag_fill)
			last_painted = c
			_after_change()
		elif not dragging:
			for b in buttons:
				if (b["rect"] as Rect2).has_point(mouse):
					queue_redraw()
					break

	elif event is InputEventMouseButton:
		mouse = get_global_mouse_position()
		var mb := event as InputEventMouseButton
		if picking:
			# the picker owns the screen while it is open
			if mb.pressed:
				for b in buttons:
					if (b["rect"] as Rect2).has_point(mouse):
						_do_action(b["action"])
						return
				picking = false
				queue_redraw()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			for b in buttons:
				if (b["rect"] as Rect2).has_point(mouse):
					_do_action(b["action"])
					return
		if solved:
			if mb.pressed:
				_load_puzzle(index + 1)
			return
		if lost:
			if mb.pressed:
				_load_puzzle(index)        # same puzzle, another go
			return

		var c := _cell_from_point(mouse)
		if mb.pressed and _in_grid(c):
			var left := mb.button_index == MOUSE_BUTTON_LEFT
			if not left and mb.button_index != MOUSE_BUTTON_RIGHT:
				return
			_press_cell(c, not left, mouse)
			dragging = true
			painted = {c: true}
			last_painted = c
			_after_change()
		elif not mb.pressed:
			dragging = false
			painted.clear()
			last_painted = Vector2i(-1, -1)

	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1: _do_action("tool_pipe")
			KEY_2: _do_action("tool_empty")
			KEY_L: _do_action("layouts")
			KEY_BRACKETLEFT:
				layout -= 1
				_apply_layout()
			KEY_BRACKETRIGHT:
				layout += 1
				_apply_layout()
			KEY_R: _do_action("reset")
			KEY_N, KEY_RIGHT: _do_action("next")
			KEY_P, KEY_LEFT: _do_action("prev")
			KEY_H: _do_action("hint")
			KEY_M: _do_action("errors")
			KEY_F: _do_action("mode")
			KEY_SPACE, KEY_TAB: _do_action("cycle")
			KEY_Z: _undo()
			KEY_ESCAPE: get_tree().quit()


func _after_change() -> void:
	_derive_pieces()         # shapes follow the joints, so redo them first
	_retrace()
	if not solved:
		_check_solved()
	queue_redraw()


func _do_action(a: String) -> void:
	if a.begins_with("pick_"):
		layout = int(a.substr(5))
		picking = false
		_apply_layout()
		return
	match a:
		"layouts":
			picking = not picking
			queue_redraw()
		"bar":
			bar_open = not bar_open
			queue_redraw()
		"undo": _undo()
		"prev": _load_puzzle(index - 1)
		"next": _load_puzzle(index + 1)
		"reset": _load_puzzle(index)
		"errors":
			show_errors = not show_errors
			queue_redraw()
		"mode":
			if solved or lost:
				return
			if mode == MODE_FLOW:
				# Dropping to Zen is a one-way door for this puzzle, and it
				# restarts nothing. Reloading here would have let a player
				# toggle the mode to buy a fresh clock whenever the water
				# got close.
				mode = MODE_ZEN
				zen_locked = true
				flowing = false
				queue_redraw()
			elif not zen_locked:
				# opting into the chase part way through: keep the board, start
				# the water's clock from now
				mode = MODE_FLOW
				flowing = false
				flow_pos = 0.0
				pressure_left = PRESSURE_SECONDS
				grace_left = GRACE_BASE + GRACE_PER_CELL * float(sol_walk.size())
				queue_redraw()
		"cycle":
			tool = (tool + 1) % TOOL_NAMES.size()
			queue_redraw()
		"tool_pipe": _pick_tool(TOOL_PIPE)
		"tool_empty": _pick_tool(TOOL_EMPTY)
		"hint": _give_hint()


func _pick_tool(t: int) -> void:
	# tapping the tool you already hold turns it, so one button both selects
	tool = t
	queue_redraw()


func _give_hint() -> void:
	if solved:
		return
	## Hand over one cell the player has not got right yet: a wrong one
	## first, then a blank.
	var wrong := []
	var blank := []
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if _is_given(c):
				continue
			var want_pipe := solution.has(c)
			if marks[y][x] == UNKNOWN:
				blank.append(c)
			elif (marks[y][x] == PIPE) != want_pipe:
				wrong.append(c)
	var pool: Array = wrong
	if pool.is_empty():
		pool = blank
	if pool.is_empty():
		return
	var c: Vector2i = pool[randi() % pool.size()]
	_record(c)
	marks[c.y][c.x] = PIPE if solution.has(c) else BLOCKED
	hint_cells[c] = true
	_after_change()


# =========================================================================
#  process
# =========================================================================

func _process(delta: float) -> void:
	if puzzles.is_empty():
		return
	if lost:
		return
	if solved:
		var last := float(maxi(route.size() - 1, 0))
		if flow_pos < last:
			flow_pos = minf(flow_pos + delta * 4.0, last)
			queue_redraw()
		return

	elapsed += delta
	if mode == MODE_FLOW:
		_flow_step(delta)
		queue_redraw()
	elif int(elapsed * 2.0) != int((elapsed - delta) * 2.0):
		queue_redraw()


# =========================================================================
#  drawing
# =========================================================================

func _blueprint() -> bool:
	return _chrome() == CHROME_TRAY


func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), C_BENCH if _blueprint() else C_BG, true)
	if puzzles.is_empty():
		_text_c("No puzzles. Run: heavy python3 tools/generate.py",
				Vector2(VW * 0.5, VH * 0.5), 20, C_BAD)
		return

	_draw_header()
	_draw_clues()
	_draw_cells()
	_draw_pipes()
	if solved or flowing:
		_draw_water()
	_draw_flanges()
	_draw_taps()
	if bool(_lay("ring", false)):
		_draw_pressure_ring()
	if lost:
		_draw_burst()
	_draw_controls()
	if solved:
		_draw_banner()
	elif lost:
		_draw_lost_banner()
	if picking:
		_draw_picker()


# ---- header --------------------------------------------------------------

func _status_text() -> String:
	var p: Dictionary = puzzles[index]
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	return "%s  ·  %d×%d  ·  %d/%d  ·  %d:%02d" % [
		str(p.get("name", "?")), W, H, index + 1, puzzles.size(), mins, secs]


func _flow_ahead() -> float:
	var reach := float(route.size() - 1)
	if route_fault >= 0:
		reach = float(route_fault)
	return reach - flow_pos


func _draw_flow_line(y: float, size := 17) -> void:
	## Where the water is, or how long you have left. The bar is skipped when
	## the layout puts the countdown on the board instead.
	if mode != MODE_FLOW or solved or lost:
		return
	if grace_left > 0.0:
		_text_c("water in %d s" % int(ceil(grace_left)), Vector2(VW * 0.5, y),
				size, C_ACCENT)
		return
	var ahead := _flow_ahead()
	if ahead > 0.35:
		_text_c("water rising — %d cells of pipe ahead of it" % int(ahead),
				Vector2(VW * 0.5, y), size, C_WATER)
		return
	_text_c("PRESSURE BUILDING — %.1f s" % pressure_left, Vector2(VW * 0.5, y),
			size + 1, C_BAD)
	if bool(_lay("ring", false)):
		return                        # the ring on the board carries it
	var frac := clampf(pressure_left / PRESSURE_SECONDS, 0.0, 1.0)
	var bw := 300.0
	var br := Rect2(VW * 0.5 - bw * 0.5, y + 7.0, bw, 6.0)
	draw_rect(br, C_PANEL, true)
	draw_rect(Rect2(br.position, Vector2(bw * frac, br.size.y)), C_BAD, true)


func _draw_header() -> void:
	match int(_lay("hdr", HDR_FULL)):
		HDR_TIGHT:
			_text_c("PIPEGRAM", Vector2(VW * 0.5, 32), 26, C_ACCENT)
			_text_c(_status_text(), Vector2(VW * 0.5, 58), 15,
					C_GOOD if solved else C_TEXT_DIM)
			_draw_flow_line(106)
		HDR_CHIP:
			draw_rect(Rect2(0, 0, VW, 46), C_PANEL, true)
			_text_l("PIPEGRAM", Vector2(20, 30), 18, C_ACCENT)
			_text_r(_status_text(), Vector2(VW - 20, 16), 14, C_TEXT_DIM)
			_draw_flow_line(70, 14)
		_:
			_text_c("PIPEGRAM", Vector2(VW * 0.5, 50), 36, C_ACCENT)
			_text_c("lay the pipe by the numbers", Vector2(VW * 0.5, 76), 16,
					C_TEXT_DIM)
			_text_c(_status_text(), Vector2(VW * 0.5, 112), 18, C_TEXT)
			var mins := int(elapsed) / 60
			var secs := int(elapsed) % 60
			_text_c("%d:%02d" % [mins, secs], Vector2(VW * 0.5, 166), 16,
					C_GOOD if solved else C_TEXT_DIM)
			_draw_flow_line(190)


func _draw_pressure_ring() -> void:
	## The Flow countdown drawn round the water's head, so your eyes never
	## have to leave the frontier to read it.
	if mode != MODE_FLOW or solved or lost or route.is_empty():
		return
	if grace_left > 0.0 or _flow_ahead() > 0.35:
		return
	var head: Vector2i = route[clampi(int(round(flow_pos)), 0, route.size() - 1)]
	var ctr := _cell_centre(head)
	var frac := clampf(pressure_left / PRESSURE_SECONDS, 0.0, 1.0)
	var r := cell * 0.47
	draw_arc(ctr, r, 0.0, TAU, 32, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.18),
			maxf(cell * 0.07, 3.0), true)
	draw_arc(ctr, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, C_BAD,
			maxf(cell * 0.07, 3.0), true)


# ---- clues ---------------------------------------------------------------

func _draw_clues() -> void:
	var board_w := cell * W
	var board_h := cell * H

	# panel behind the clue gutters
	draw_rect(Rect2(origin.x - gutter_l, origin.y - gutter_t,
			board_w + gutter_l + gutter_r, board_h + gutter_t + gutter_b),
			C_BP_PANEL if _blueprint() else C_PANEL, true)

	for y in H:
		var clue: Array = row_clues[y]
		var done := _clue_done(clue, _row_bits(y))
		var col := C_TEXT_DONE if done else C_TEXT
		var txt := ""
		if clue.is_empty():
			txt = "0"
			col = C_TEXT_DONE if done else C_TEXT_DIM
		else:
			var parts := []
			for n in clue:
				parts.append(str(int(n)))
			txt = " ".join(parts)
		var cy := origin.y + y * cell + cell * 0.5
		_text_r(txt, Vector2(origin.x - 12.0, cy), clue_font, col)
		if gutter_r > 0.0:
			_text_l(txt, Vector2(origin.x + cell * W + 12.0, cy + clue_font * 0.36),
					clue_font, col)

	for x in W:
		var clue: Array = col_clues[x]
		var done := _clue_done(clue, _col_bits(x))
		var col := C_TEXT_DONE if done else C_TEXT
		var cx := origin.x + x * cell + cell * 0.5
		if clue.is_empty():
			_text_c("0", Vector2(cx, origin.y - 14.0), clue_font,
					C_TEXT_DONE if done else C_TEXT_DIM)
		else:
			var line_h := clue_font + 3.0
			var base := origin.y - 14.0 - (clue.size() - 1) * line_h
			for i in clue.size():
				_text_c(str(int(clue[i])), Vector2(cx, base + i * line_h), clue_font, col)
		if gutter_b > 0.0:
			var by2 := origin.y + cell * H + 24.0
			if clue.is_empty():
				_text_c("0", Vector2(cx, by2), clue_font,
						C_TEXT_DONE if done else C_TEXT_DIM)
			else:
				for i in clue.size():
					_text_c(str(int(clue[i])),
							Vector2(cx, by2 + i * (clue_font + 3.0)), clue_font, col)


# ---- cells ---------------------------------------------------------------

func _draw_cells() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var r := Rect2(origin.x + x * cell, origin.y + y * cell, cell, cell)
			var base := C_CELL if (x + y) % 2 == 0 else C_CELL_ALT
			if _blueprint():
				base = C_BP_CELL if (x + y) % 2 == 0 else C_BP_ALT
			if hover == c and not solved:
				base = base.lightened(0.10)
			draw_rect(r, base, true)

			var m: int = marks[y][x]
			if m == BLOCKED:
				var pad := cell * 0.32
				var a := r.position + Vector2(pad, pad)
				var b := r.position + Vector2(cell - pad, cell - pad)
				var wdt := maxf(cell * 0.055, 2.0)
				draw_line(a, b, C_BLOCK, wdt, true)
				draw_line(Vector2(a.x, b.y), Vector2(b.x, a.y), C_BLOCK, wdt, true)

			if show_errors and not solved and m == PIPE:
				var bad := not solution.has(c)
				if not bad and pieces[y][x] != MASK_NONE:
					bad = pieces[y][x] != int(solution[c])
				if bad:
					draw_rect(r, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.26), true)
			if hint_cells.has(c):
				draw_rect(r, Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.14), true)

	# grid lines
	var board_w := cell * W
	var board_h := cell * H
	# every fifth line is heavier, but only once the grid is big enough to need
	# counting help -- on a 6-wide board it just looks like a mistake
	var band := W >= 10
	for x in range(W + 1):
		var bold := x == 0 or x == W or (band and x % 5 == 0)
		draw_line(Vector2(origin.x + x * cell, origin.y),
				Vector2(origin.x + x * cell, origin.y + board_h),
				C_GRID_BOLD if bold else C_GRID, 2.0 if bold else 1.0)
	for y in range(H + 1):
		var bold := y == 0 or y == H or (band and y % 5 == 0)
		draw_line(Vector2(origin.x, origin.y + y * cell),
				Vector2(origin.x + board_w, origin.y + y * cell),
				C_GRID_BOLD if bold else C_GRID, 2.0 if bold else 1.0)


# ---- pipes ---------------------------------------------------------------

func _cell_centre(c: Vector2i) -> Vector2:
	return origin + Vector2((c.x + 0.5) * cell, (c.y + 0.5) * cell)


func _tube_layers() -> Array:
	## colour, width multiple, how far the layer shifts towards the light
	return [
		[C_PIPE_SHADOW, 1.10, 0.00],
		[C_PIPE_DARK,   0.94, 0.00],
		[C_PIPE,        0.74, 0.08],
		[C_PIPE_LIGHT,  0.40, 0.20],
		[C_PIPE_HI,     0.15, 0.29],
	]


func _draw_pipes() -> void:
	## Drawn as a lit tube rather than a flat line: a dark rim, a body, a lit
	## side and a specular streak, all offset towards a light up and to the
	## left. Collars go on at the section joins afterwards, over the water, the
	## way a real coupling wraps the outside of the pipe.
	var w := cell * 0.36
	pipe_flanges.clear()

	var legs: Array = []          # [centre, outer end, direction]
	var joints: Array = []        # cell centres, where legs meet
	var plugs: Array = []         # pipe laid with nothing joined onto it yet
	for y in H:
		for x in W:
			if marks[y][x] != PIPE:
				continue
			var c := Vector2i(x, y)
			var ctr := _cell_centre(c)
			var m: int = pieces[y][x]
			if m == MASK_NONE:
				plugs.append(ctr)
				continue
			joints.append(ctr)
			for i in 4:
				if (m & BITS[i]) == 0:
					continue
				var dv := Vector2(DIRS[i])
				# overshoot slightly so neighbouring cells meet with no seam
				legs.append([ctr, ctr + dv * (cell * 0.5 + 0.7), dv])
				pipe_flanges.append([ctr + dv * (cell * 0.5), dv])

	# light from the upper left: for a horizontal run that is upwards, for a
	# vertical run it is to the left
	var lit := func(d: Vector2, amount: float) -> Vector2:
		return Vector2(-absf(d.y), -absf(d.x)) * amount

	# Each layer is drawn across every leg before the next starts, so one
	# cell's rim can never land on top of a neighbour's body.
	for layer in _tube_layers():
		var col: Color = layer[0]
		var mul: float = layer[1]
		var shift: float = layer[2]
		for l in legs:
			var off: Vector2 = lit.call(l[2], w * shift)
			draw_line(l[0] + off, l[1] + off, col, w * mul, true)
		# a blob at the middle rounds the elbows and caps a lone stub
		var joff := Vector2(-w * shift, -w * shift) * 0.7
		for p in joints:
			draw_circle(p + joff, w * mul * 0.5, col)

	# a blanked-off boss: pipe laid with nothing joined onto it yet
	for p in plugs:
		draw_circle(p, w * 0.58, C_PIPE_SHADOW)
		draw_circle(p, w * 0.46, C_PIPE_DARK)
		draw_circle(p + Vector2(-w * 0.06, -w * 0.06), w * 0.26, C_PIPE)
		draw_arc(p, w * 0.36, PI * 1.05, PI * 1.75, 12,
				Color(C_PIPE_LIGHT.r, C_PIPE_LIGHT.g, C_PIPE_LIGHT.b, 0.7),
				maxf(w * 0.08, 1.0), true)


func _draw_flanges() -> void:
	## Collars at every cell boundary the pipe crosses -- the detail that reads
	## as "sections of pipe bolted together" rather than "a drawn line".
	var w := cell * 0.36
	for f in pipe_flanges:
		var p: Vector2 = f[0]
		var d: Vector2 = f[1]
		var side := Vector2(-d.y, d.x)
		draw_line(p - side * w * 0.72, p + side * w * 0.72,
				C_PIPE_SHADOW, w * 0.34, true)
		draw_line(p - side * w * 0.66, p + side * w * 0.66,
				C_FLANGE, w * 0.22, true)
		draw_line(p - side * w * 0.66 - d * w * 0.06,
				p + side * w * 0.66 - d * w * 0.06,
				C_PIPE_LIGHT, w * 0.07, true)


func _water_run(pts: Array) -> void:
	## Shaded channel, brighter core, then a sheen along the top: it has to read
	## as liquid sitting inside the bore, not a line painted over the pipe.
	## Each colour finishes before the next starts -- painting the shaded
	## circles after the bright core left a ring at every cell centre.
	var thick := cell * 0.36 * 0.50
	var line := PackedVector2Array()
	for p in pts:
		line.append(p)
	if line.size() < 2:
		if line.size() == 1:
			draw_circle(line[0], thick * 0.5, C_WATER)
		return
	draw_polyline(line, C_WATER_DEEP, thick, true)
	for i in range(line.size() - 1):
		draw_circle(line[i], thick * 0.5, C_WATER_DEEP)
	draw_polyline(line, C_WATER, thick * 0.64, true)
	for i in range(line.size() - 1):
		draw_circle(line[i], thick * 0.32, C_WATER)
	var sheen := PackedVector2Array()
	for p in line:
		sheen.append(p + Vector2(-thick * 0.15, -thick * 0.21))
	draw_polyline(sheen, Color(C_WATER_HI.r, C_WATER_HI.g, C_WATER_HI.b, 0.45),
			thick * 0.20, true)
	draw_circle(line[line.size() - 1], thick * 0.58, C_WATER_HI)


func _draw_water() -> void:
	if route.is_empty():
		return
	var thick := cell * 0.36 * 0.50
	if route.size() == 1:
		draw_circle(_cell_centre(route[0]), thick * 0.58, C_WATER_HI)
		return
	var last := float(route.size() - 1)
	var front := clampf(flow_pos, 0.0, last)
	var full := clampi(int(floor(front)), 0, route.size() - 1)
	var frac := clampf(front - float(full), 0.0, 1.0)

	# One continuous run ending at the exact front, rather than per-cell
	# halves -- drawing a cell's inbound half as soon as the front entered it
	# made the water lurch half a cell at every boundary.
	var pts: Array = []
	for i in range(full + 1):
		pts.append(_cell_centre(route[i]))
	if full < route.size() - 1 and frac > 0.0:
		pts.append(_cell_centre(route[full]).lerp(_cell_centre(route[full + 1]), frac))
	_water_run(pts)


func _tap_dir(c: Vector2i) -> Vector2:
	## Which way the pipe leaves this tap. It is given to you, so the spigot
	## is drawn facing it -- a real fitting points somewhere, and that first
	## (or last) joint is a free foothold into the puzzle.
	var m := int(solution.get(c, 0))
	return Vector2(_dir_of_bit(m & -m))


func _draw_spigot(c: Vector2i, is_in: bool) -> void:
	## The inlet is a valve on the wall, the outlet a drain into it. Both are
	## built along the direction the pipe actually runs, so you can read the
	## first and last joint straight off the board.
	var f := _tap_dir(c)
	if f == Vector2.ZERO:
		return
	var ctr := _cell_centre(c)
	var w := cell * 0.36
	var col := C_GOOD if is_in else C_WATER

	# the handle goes towards the light where there is a choice
	var s := Vector2(-f.y, f.x)
	if s.y > 0.0 or (is_zero_approx(s.y) and s.x > 0.0):
		s = -s

	var back := ctr - f * cell * 0.46
	var plate := s * cell * 0.27

	# the wall plate it is bolted to
	draw_line(back - plate, back + plate, C_PIPE_SHADOW, cell * 0.15, true)
	draw_line(back - plate, back + plate, C_FLANGE, cell * 0.11, true)
	draw_line(back - plate + f * cell * 0.025, back + plate + f * cell * 0.025,
			C_PIPE_LIGHT, cell * 0.035, true)
	for k in [-0.19, 0.19]:
		draw_circle(back + s * cell * k, maxf(cell * 0.024, 1.0), C_PIPE_DARK)

	# the body, a shade fatter than the pipe so it reads as a casting
	var body_a := back + f * cell * 0.07
	for layer in _tube_layers():
		var off := Vector2(-absf(f.y), -absf(f.x)) * (w * float(layer[2]))
		draw_line(body_a + off, ctr + off, layer[0],
				w * 1.16 * float(layer[1]), true)

	if is_in:
		# a valve: bonnet, stem, handwheel
		var base := ctr - f * cell * 0.17
		var stem := base + s * cell * 0.29
		draw_line(base, stem, C_PIPE_SHADOW, cell * 0.13, true)
		draw_line(base, stem, C_FLANGE, cell * 0.085, true)
		var bar := Vector2(-s.y, s.x) * cell * 0.16
		draw_line(stem - bar, stem + bar, C_PIPE_SHADOW, cell * 0.11, true)
		draw_line(stem - bar, stem + bar, col, cell * 0.065, true)
		draw_circle(stem, cell * 0.06, C_PIPE_SHADOW)
		draw_circle(stem, cell * 0.042, col)
	else:
		# a drain: the pipe flares into a bell mouth with a grate over it
		var mouth := ctr - f * cell * 0.26
		draw_colored_polygon(PackedVector2Array([
				mouth - plate * 0.52, mouth + plate * 0.52,
				back + plate * 0.94, back - plate * 0.94]), C_PIPE_DARK)
		draw_colored_polygon(PackedVector2Array([
				mouth - plate * 0.34, mouth + plate * 0.34,
				back + plate * 0.74, back - plate * 0.74]), C_PIPE_SHADOW)
		# bars across the opening, splaying out with the flare
		for i in 3:
			var k := -0.45 + 0.45 * float(i)
			var p0: Vector2 = mouth.lerp(back, 0.25) + plate * (0.55 * k)
			var p1: Vector2 = mouth.lerp(back, 0.85) + plate * (0.80 * k)
			draw_line(p0, p1, col, maxf(cell * 0.03, 1.0), true)
		draw_line(mouth - plate * 0.52, mouth + plate * 0.52,
				C_FLANGE, maxf(cell * 0.04, 1.5), true)


func _draw_taps() -> void:
	_draw_spigot(inlet, true)
	_draw_spigot(outlet, false)


# ---- footer / buttons ----------------------------------------------------

func _draw_mini(centre: Vector2, size: float, t: int) -> void:
	var w := size * 0.36
	if t == TOOL_EMPTY:
		var h := size * 0.3
		draw_line(centre + Vector2(-h, -h), centre + Vector2(h, h), C_BLOCK, 3.0, true)
		draw_line(centre + Vector2(-h, h), centre + Vector2(h, -h), C_BLOCK, 3.0, true)
		return
	if t == TOOL_PIPE:
		draw_circle(centre, w * 0.58, C_PIPE_SHADOW)
		draw_circle(centre, w * 0.46, C_PIPE_DARK)
		draw_circle(centre + Vector2(-w * 0.06, -w * 0.06), w * 0.26, C_PIPE)
		return


func _button(r: Rect2, label: String, action: String, off := false,
		on := false, fsize := 16, dim := false) -> void:
	var hot := r.has_point(mouse) and not off
	var fill := C_BTN_HOT if (hot or on) else C_BTN
	if dim and not (hot or on):
		fill = Color(C_BTN.r, C_BTN.g, C_BTN.b, 0.55)
	draw_rect(r, fill, true)
	draw_rect(r, C_ACCENT if on else C_GRID_BOLD, false, 2.0 if on else 1.0)
	var lc := C_TEXT_DONE if off else (C_TEXT if (hot or on) else C_TEXT_DIM)
	_text_c(label, r.position + Vector2(r.size.x * 0.5,
			r.size.y * 0.5 + float(fsize) * 0.36), fsize, lc)
	buttons.append({"rect": r, "action": action})


func _tool_button(r: Rect2, t: int, labelled := true, icon := 34.0) -> void:
	var on: bool = tool == t
	draw_rect(r, C_BTN_HOT if (on or r.has_point(mouse)) else C_BTN, true)
	draw_rect(r, C_ACCENT if on else C_GRID_BOLD, false, 2.0 if on else 1.0)
	var cy := 24.0 if labelled else r.size.y * 0.5
	_draw_mini(r.position + Vector2(r.size.x * 0.5, cy), icon, t)
	if labelled:
		_text_c(TOOL_NAMES[t], r.position + Vector2(r.size.x * 0.5,
				r.size.y - 9.0), 13, C_TEXT if on else C_TEXT_DIM)
	buttons.append({"rect": r, "action": TOOL_ACTIONS[t]})


func _nav_items() -> Array:
	var mode_label := "Mode: Flow"
	var mode_off := false
	if mode == MODE_ZEN:
		if zen_locked:
			mode_label = "Zen (locked)"
			mode_off = true
		else:
			mode_label = "Mode: Zen"
	return [
		["‹ Prev", "prev", false], ["Reset", "reset", false], ["Hint", "hint", false],
		[mode_label, "mode", mode_off], ["Next ›", "next", false],
		["Layouts", "layouts", false],
	]


func _draw_nav_row(y: float, h: float, fsize: int, dim: bool) -> void:
	var items := _nav_items()
	var gap := 8.0
	var bw := (VW - 40.0 - gap * float(items.size() - 1)) / float(items.size())
	for i in items.size():
		_button(Rect2(20.0 + i * (bw + gap), y, bw, h), str(items[i][0]),
				str(items[i][1]), bool(items[i][2]), false, fsize, dim)


func _tip_text() -> String:
	if _input_mode() == IN_CYCLE:
		return "tap a cell to cycle it: blank → pipe → crossed off"
	if tool == TOOL_PIPE:
		return "tap to lay pipe · the shape follows the joints it makes"
	return "cross off a cell the pipe cannot run through"


func _draw_controls() -> void:
	buttons.clear()
	var top := VH - ctrl_h
	match _chrome():
		CHROME_PANEL: _chrome_panel(top)
		CHROME_BAR: _chrome_bar()
		CHROME_PAD: _chrome_pad(top)
		CHROME_NONE: _chrome_none(top)
		CHROME_SIDE: _chrome_side()
		CHROME_TRAY: _chrome_tray(top)
		_: _chrome_rows(top)


func _palette_row(x: float, y: float, w: float, h: float) -> void:
	var n := TOOL_NAMES.size()
	var gap := 10.0
	var tw := (w - gap * float(n - 1)) / float(n)
	for i in n:
		_tool_button(Rect2(x + float(i) * (tw + gap), y, tw, h), i)


func _chrome_rows(top: float) -> void:
	_palette_row(20.0, top + 2.0, VW - 40.0, 64.0)
	_text_c(_tip_text(), Vector2(VW * 0.5, top + 84.0), 14, C_TEXT_DIM)
	_draw_nav_row(top + 94.0, 44.0, 16, false)
	_text_c(RULE_LINE, Vector2(VW * 0.5, top + 160.0), 14, C_TEXT_DONE)


func _chrome_panel(top: float) -> void:
	## The palette raised onto its own panel, everything else dimmed to chrome,
	## so the thing you touch most no longer looks like the thing you touch least.
	var panel := Rect2(14.0, top, VW - 28.0, 112.0)
	draw_rect(panel, C_PANEL, true)
	draw_rect(Rect2(panel.position, Vector2(panel.size.x, 3.0)), C_ACCENT, true)
	draw_rect(panel, C_GRID_BOLD, false, 1.0)
	_palette_row(panel.position.x + 10.0, top + 10.0, panel.size.x - 20.0, 66.0)
	_text_c(_tip_text(), Vector2(VW * 0.5, top + 98.0), 14, C_TEXT_DIM)
	_draw_nav_row(top + 122.0, 38.0, 14, true)
	_text_c(RULE_LINE, Vector2(VW * 0.5, top + 174.0), 13, C_TEXT_DONE)


func _chrome_bar() -> void:
	## Board first: one chip, and the controls come up only when asked for.
	if bar_open:
		var panel := Rect2(14.0, VH - 236.0, VW - 28.0, 166.0)
		draw_rect(panel, C_PANEL, true)
		draw_rect(panel, C_ACCENT, false, 1.0)
		_palette_row(panel.position.x + 10.0, panel.position.y + 10.0,
				panel.size.x - 20.0, 66.0)
		_draw_nav_row(panel.position.y + 88.0, 38.0, 14, true)
		_text_c(_tip_text(), Vector2(VW * 0.5, panel.position.y + 150.0), 13,
				C_TEXT_DIM)
	var chip := Rect2(20.0, VH - 58.0, VW - 40.0, 46.0)
	draw_rect(chip, C_BTN_HOT if chip.has_point(mouse) else C_BTN, true)
	draw_rect(chip, C_ACCENT, false, 1.0)
	_draw_mini(chip.position + Vector2(32.0, 23.0), 30.0, tool)
	_text_l(TOOL_NAMES[tool], chip.position + Vector2(60.0, 29.0), 17, C_TEXT)
	_text_r("close ⌄" if bar_open else "controls ⌃",
			Vector2(chip.end.x - 14.0, chip.position.y + 14.0), 15, C_TEXT_DIM)
	buttons.append({"rect": chip, "action": "bar"})


func _chrome_pad(top: float) -> void:
	## A thumb pad in the corner: the nine things you actually reach for, where
	## your thumb already is, and the board keeps everything above it.
	var sz := 72.0
	var gap := 6.0
	var pad := Vector2(VW - 20.0 - (sz * 3.0 + gap * 2.0), top + 6.0)
	var slots := [
		[TOOL_PIPE, ""], [TOOL_EMPTY, ""], [-1, "undo"],
		[-1, "hint"], [-1, "prev"], [-1, "next"],
		[-1, "reset"], [-1, "mode"], [-1, "layouts"],
	]
	var extra := ["undo", "hint", "prev", "next", "reset", "mode", "layouts"]
	var ei := 0
	for i in 9:
		var r := Rect2(pad + Vector2(float(i % 3) * (sz + gap),
				float(i / 3) * (sz + gap)), Vector2(sz, sz))
		var t: int = slots[i][0]
		if t >= 0:
			_tool_button(r, t, true, 30.0)
		else:
			var label := str(slots[i][1])
			_button(r, label, extra[ei], false, false, 14)
			ei += 1
	var left_w := pad.x - 30.0
	var items := _nav_items()
	for i in 4:
		var r := Rect2(20.0 + float(i % 2) * (left_w * 0.5 + 6.0),
				top + 6.0 + float(i / 2) * 62.0, left_w * 0.5 - 6.0, 56.0)
		_button(r, str(items[i][0]), str(items[i][1]), bool(items[i][2]), false, 15)
	_text_c(_tip_text(), Vector2(20.0 + left_w * 0.5, top + 156.0), 13, C_TEXT_DIM)


func _chrome_none(top: float) -> void:
	## No palette: a tap cycles the cell itself, so there is nothing to aim at.
	_text_c(_tip_text(), Vector2(VW * 0.5, top + 20.0), 15, C_TEXT_DIM)
	_draw_nav_row(VH - 58.0, 46.0, 16, false)


func _chrome_side() -> void:
	## Landscape: pipe and no-pipe under the left thumb, utilities under the
	## right, board in the middle where both can reach it.
	var y := head_h + 6.0
	var avail := VH - y - 54.0
	var nt := TOOL_NAMES.size()
	var hgt := avail / float(nt) - 6.0
	for i in nt:
		_tool_button(Rect2(14.0, y + float(i) * (hgt + 6.0), 144.0, hgt), i, true, 30.0)
	var items := _nav_items()
	var hgt2 := avail / float(items.size()) - 6.0
	for i in items.size():
		_button(Rect2(VW - 158.0, y + float(i) * (hgt2 + 6.0), 144.0, hgt2),
				str(items[i][0]), str(items[i][1]), bool(items[i][2]), false, 14)
	_text_c(_tip_text(), Vector2(VW * 0.5, VH - 30.0), 14, C_TEXT_DIM)
	_text_c(RULE_LINE, Vector2(VW * 0.5, VH - 10.0), 12, C_TEXT_DONE)


func _chrome_tray(top: float) -> void:
	## The workbench: a blueprint on a bench, the two marks lying in a parts
	## tray, and a pressure gauge instead of a progress bar.
	draw_rect(Rect2(0, top - 8.0, VW, 8.0), C_BENCH_DARK, true)
	var tray := Rect2(14.0, top + 4.0, VW - 28.0, 94.0)
	draw_rect(tray, C_BENCH_DARK, true)
	draw_rect(tray, Color(0, 0, 0, 0.4), false, 2.0)

	var g := tray.position + Vector2(52.0, 47.0)
	draw_circle(g, 37.0, C_BENCH)
	draw_circle(g, 31.0, Color("d9cfbd"))
	var frac := 1.0
	if mode == MODE_FLOW and not solved and not lost and grace_left <= 0.0:
		frac = clampf(pressure_left / PRESSURE_SECONDS, 0.0, 1.0)
	for i in 7:
		var a := PI * 0.75 + float(i) / 6.0 * PI * 1.5
		var dv := Vector2(cos(a), sin(a))
		draw_line(g + dv * 21.0, g + dv * 27.0, C_BENCH_DARK, 2.0, true)
	var ang := PI * 0.75 + (1.0 - frac) * PI * 1.5
	draw_line(g, g + Vector2(cos(ang), sin(ang)) * 25.0, C_BAD, 3.0, true)
	draw_circle(g, 4.0, C_BENCH_DARK)

	var sx := tray.position.x + 100.0
	var sw := (tray.size.x - 110.0) / float(TOOL_NAMES.size())
	for i in TOOL_NAMES.size():
		var r := Rect2(sx + float(i) * sw + 4.0, tray.position.y + 8.0,
				sw - 8.0, 78.0)
		draw_rect(r, Color(0, 0, 0, 0.35), true)
		var on: bool = tool == i
		if on or r.has_point(mouse):
			draw_rect(r, C_ACCENT if on else C_GRID_BOLD, false, 2.0)
		_draw_mini(r.position + Vector2(r.size.x * 0.5, 30.0), 34.0, i)
		_text_c(TOOL_NAMES[i], r.position + Vector2(r.size.x * 0.5, 68.0), 12,
				Color("d9cfbd") if on else C_TEXT_DIM)
		buttons.append({"rect": r, "action": TOOL_ACTIONS[i]})

	_draw_nav_row(top + 106.0, 38.0, 14, true)
	_text_c(_tip_text(), Vector2(VW * 0.5, top + 164.0), 13, Color("8a7c66"))


# ---- the layout picker -----------------------------------

func _draw_picker() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, 0.74), true)
	var panel := Rect2(20.0, 36.0, VW - 40.0, VH - 72.0)
	draw_rect(panel, C_PANEL, true)
	draw_rect(panel, C_ACCENT, false, 2.0)
	_text_c("LAYOUTS — tap one to play it", Vector2(VW * 0.5, panel.position.y + 34.0),
			22, C_ACCENT)
	_text_c("L closes this · [ and ] step through them while you play",
			Vector2(VW * 0.5, panel.position.y + 58.0), 14, C_TEXT_DIM)

	var cols := 2
	var rows := int(ceil(float(LAYOUTS.size()) / float(cols)))
	var gw := (panel.size.x - 50.0) / float(cols)
	var gh := minf(58.0, (panel.size.y - 180.0) / float(rows))
	for i in LAYOUTS.size():
		var r := Rect2(panel.position.x + 20.0 + float(i % cols) * (gw + 10.0),
				panel.position.y + 78.0 + float(i / cols) * (gh + 6.0), gw, gh)
		var on: bool = i == layout
		draw_rect(r, C_BTN_HOT if (on or r.has_point(mouse)) else C_BTN, true)
		draw_rect(r, C_ACCENT if on else C_GRID_BOLD, false, 2.0 if on else 1.0)
		_text_l("%d · %s" % [i, str(LAYOUTS[i].get("name", "?"))],
				r.position + Vector2(12.0, 24.0), 15, C_TEXT if on else C_TEXT_DIM)
		_text_l(str(LAYOUTS[i].get("tier", "")),
				r.position + Vector2(12.0, 44.0), 12, C_TEXT_DONE)
		buttons.append({"rect": r, "action": "pick_%d" % i})

	_text_c(str(LAYOUTS[layout].get("note", "")),
			Vector2(VW * 0.5, panel.end.y - 56.0), 14, C_TEXT)
	_button(Rect2(VW * 0.5 - 90.0, panel.end.y - 44.0, 180.0, 34.0),
			"Close", "layouts", false, false, 15)


func _draw_burst() -> void:
	if burst_cell.x < 0:
		return
	var ctr := _cell_centre(burst_cell)
	var r := Rect2(origin.x + burst_cell.x * cell, origin.y + burst_cell.y * cell,
			cell, cell)
	draw_rect(r, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.35), true)
	# a splash of spray out of the failed joint
	for i in 12:
		var a := TAU * float(i) / 12.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(ctr + dir * (cell * 0.16), ctr + dir * (cell * 0.46),
				C_WATER_HI, maxf(cell * 0.05, 2.0), true)
	draw_arc(ctr, cell * 0.30, 0, TAU, 24, C_BAD, maxf(cell * 0.06, 2.0), true)


func _draw_lost_banner() -> void:
	var r := _banner_rect()
	draw_rect(r, Color(C_BAD.r * 0.26, C_BAD.g * 0.12, C_BAD.b * 0.16, 0.95), true)
	draw_rect(r, C_BAD, false, 2.0)
	_text_c("BURST", r.position + Vector2(r.size.x * 0.5, 34.0), 28, C_BAD)
	var why := "the water caught up with your plumbing"
	if burst_leak:
		why = "you left pipe hanging off the route — the water escaped there"
	_text_c("%s — %d of %d cells carried water. Click to try again."
			% [why, route.size(), sol_walk.size()],
			r.position + Vector2(r.size.x * 0.5, 64.0), 16, C_TEXT)


func _draw_banner() -> void:
	var r := _banner_rect()
	draw_rect(r, Color(C_GOOD.r * 0.18, C_GOOD.g * 0.3, C_GOOD.b * 0.22, 0.95), true)
	draw_rect(r, C_GOOD, false, 2.0)
	_text_c("WATER'S ON", r.position + Vector2(r.size.x * 0.5, 34.0), 28, C_GOOD)
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	_text_c("%d cells of pipe in %d:%02d — click anywhere for the next one"
			% [solution.size(), mins, secs],
			r.position + Vector2(r.size.x * 0.5, 64.0), 16, C_TEXT)


# ---- text helpers --------------------------------------------------------

func _text_c(t: String, centre: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(centre.x - w * 0.5, centre.y), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_l(t: String, at: Vector2, size: int, col: Color) -> void:
	draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_r(t: String, right: Vector2, size: int, col: Color) -> void:
	var m := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_string(font, Vector2(right.x - m.x, right.y + size * 0.36), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---- screenshot mode -----------------------------------------------------

func _take_shot() -> void:
	if shot_solve:
		# through _set_fill, not straight into the arrays -- a screenshot that
		# skips the real editing path cannot be trusted as a check
		_lay_solution()
		for y in H:
			for x in W:
				if marks[y][x] == UNKNOWN:
					_set_fill(Vector2i(x, y), BLOCKED)
		_after_change()
		solved = true
		flow_pos = float(route.size() - 1) * 0.62
		elapsed = 184.0
	elif shot_press:
		# the water has caught up to the frontier and the clock is draining --
		# the only moment the pressure ring is meant to show at all
		grace_left = 0.0
		flowing = true
		var n2 := maxi(int(float(sol_walk.size()) * 0.45), 2)
		for i in range(1, n2):
			_set_fill(sol_walk[i], PIPE)
		_after_change()
		solved = false
		flow_pos = float(route.size() - 1)
		pressure_left = PRESSURE_SECONDS * 0.45
		elapsed = 63.0
		tool = TOOL_PIPE
	elif shot_flow:
		# mid-chase: part of the route laid, the water some way behind it
		grace_left = 0.0
		flowing = true
		var n := maxi(int(float(sol_walk.size()) * 0.62), 2)
		for i in range(1, n):
			_set_fill(sol_walk[i], PIPE)
		_after_change()
		solved = false
		flow_pos = float(route.size() - 1) * 0.62
		pressure_left = PRESSURE_SECONDS
		elapsed = 47.0
		tool = TOOL_PIPE
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	get_tree().quit()


# ---- layout audit --------------------------------------------------------
#  The faults a new layout actually produces are geometric: something off the
#  edge of the viewport, chrome sitting on top of the board, or cells shrunk
#  past the point where a thumb can hit them. Those are exactly the faults
#  that are tedious and unreliable to catch by eye in fifteen screenshots,
#  so the screenshot pass checks them itself.

func _inside(outer: Rect2, inner: Rect2) -> bool:
	return (inner.position.x >= outer.position.x - 0.5
			and inner.position.y >= outer.position.y - 0.5
			and inner.end.x <= outer.end.x + 0.5
			and inner.end.y <= outer.end.y + 0.5)


func _board_rect() -> Rect2:
	return Rect2(origin - Vector2(gutter_l, gutter_t),
			Vector2(cell * float(W) + gutter_l + gutter_r,
					cell * float(H) + gutter_t + gutter_b))


func _layout_audit(tag: String) -> Array:
	var bad: Array = []
	var view := Rect2(0.0, 0.0, VW, VH)
	var board := _board_rect()

	if not _inside(view, board):
		bad.append("board %.0f,%.0f %.0fx%.0f runs off the %.0fx%.0f viewport"
				% [board.position.x, board.position.y, board.size.x,
						board.size.y, VW, VH])
	if cell < 30.0:
		bad.append("cells are %.1fpx -- too small to hit with a thumb" % cell)

	# The grid proper, without the clue gutters -- the clues belong in the
	# gutters, so only the grid has to stay clear of the header and the
	# controls. A board allowed into either band gets text drawn across it.
	var grid := Rect2(origin, Vector2(cell * float(W), cell * float(H)))
	var head_band := Rect2(0.0, 0.0, VW, head_h)
	var foot_band := Rect2(0.0, VH - ctrl_h, VW, ctrl_h)
	if ctrl_h > 0.0 and grid.intersects(foot_band):
		bad.append("grid reaches y=%.0f, into the %.0fpx the controls reserve"
				% [grid.end.y, ctrl_h])
	if head_h > 0.0 and grid.intersects(head_band):
		bad.append("grid starts at y=%.0f, inside the %.0fpx header"
				% [grid.position.y, head_h])

	var banner := _banner_rect()
	if not _inside(view, banner):
		bad.append("banner %.0f,%.0f %.0fx%.0f runs off the viewport"
				% [banner.position.x, banner.position.y, banner.size.x,
						banner.size.y])

	for b in buttons:
		var r: Rect2 = b["rect"]
		var name := str(b.get("action", "?"))
		if not _inside(view, r):
			bad.append("'%s' at %.0f,%.0f %.0fx%.0f runs off the viewport"
					% [name, r.position.x, r.position.y, r.size.x, r.size.y])
		if r.size.x < 34.0 or r.size.y < 28.0:
			bad.append("'%s' is only %.0fx%.0f -- too small to hit"
					% [name, r.size.x, r.size.y])
		# The picker is a modal sheet; it is meant to cover the board.
		if not picking and board.intersects(r):
			bad.append("'%s' overlaps the board" % name)

	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a: Rect2 = buttons[i]["rect"]
			var c: Rect2 = buttons[j]["rect"]
			if a.intersects(c):
				bad.append("'%s' and '%s' overlap each other"
						% [str(buttons[i].get("action", "?")),
								str(buttons[j].get("action", "?"))])

	if bad.is_empty():
		print("  %-28s ok   (%d buttons, %.0fpx cells)" % [tag, buttons.size(), cell])
	else:
		for msg in bad:
			print("  %-28s FAULT  %s" % [tag, msg])
	return bad


func _audit_all() -> void:
	print("auditing %d layouts at puzzle %d (%dx%d)"
			% [LAYOUTS.size(), index + 1, W, H])
	var faults := 0
	for i in LAYOUTS.size():
		layout = i
		_apply_layout()
		var nm := str(LAYOUTS[i].get("name", str(i)))
		for open_picker in [false, true]:
			picking = open_picker
			queue_redraw()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var tag := "%d %s%s" % [i, nm, "  +picker" if open_picker else ""]
			faults += _layout_audit(tag).size()
	picking = false

	# An audit that cannot fail proves nothing, so plant two faults it must
	# catch -- one rect off the edge, one too small to hit -- and check it
	# reports them before trusting a clean run above.
	print("")
	var keep: Array = buttons.duplicate()
	buttons = [
		{"rect": Rect2(VW - 10.0, 10.0, 80.0, 40.0), "action": "planted off-edge"},
		{"rect": Rect2(12.0, 12.0, 12.0, 12.0), "action": "planted tiny"},
	]
	var probe: Array = _layout_audit("self-test (faults expected)")
	buttons = keep
	if probe.size() < 2:
		print("  SELF-TEST FAILED -- the audit missed its own planted faults, "
				+ "so the clean run above means nothing")
		faults += 1
	else:
		print("  self-test ok -- both planted faults were caught")

	print("")
	if faults == 0:
		print("%d layouts, no geometry faults" % LAYOUTS.size())
	else:
		print("%d geometry fault(s) over %d layouts" % [faults, LAYOUTS.size()])
	get_tree().quit(1 if faults > 0 else 0)
