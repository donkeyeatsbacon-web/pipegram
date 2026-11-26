extends Node2D
##
## PIPEGRAM -- prototype
##
## Pipe Dream's plumbing, a nonogram's clues.
##
## One pipe runs from the inlet to the outlet. The numbers down the side and
## across the top are nonogram run-length clues: how many pipe cells sit in a
## row, in order, with a gap between runs. The twist that makes it a plumbing
## puzzle rather than a picture puzzle: the pipe never runs alongside itself,
## so two pipe cells touch only where the pipe actually connects them. Work out
## which cells hold pipe and every elbow and straight is forced -- the pipework
## draws itself.
##
## Left click / drag  lay pipe   (start on pipe to rub it out)
## Right click / drag mark empty (start on a mark to rub it out)
##

const VW := 760.0          # design viewport
const VH := 1080.0

# cell marks
const UNKNOWN := 0
const PIPE := 1
const BLOCKED := 2

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

# modes
const MODE_ZEN := 0                # no clock, solve it in your own time
const MODE_FLOW := 1               # the water is coming

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
var solution: Dictionary = {}      # Vector2i -> true
var sol_path: Array = []           # ordered cells, inlet .. outlet

var marks: Array = []              # marks[y][x]
var undo_stack: Array = []

var solved := false
var water := 0.0                   # 0..1 animation along sol_path
var elapsed := 0.0

# --- flow mode -------------------------------------------------------------
# Pipe Dream's pressure, adapted to a route you deduce rather than build.
# After a thinking period the water sets off from the inlet and runs along the
# pipe you have actually laid. It can only travel cells of the real route, so
# it tells you nothing you have not earned. Two ways to drown:
#   * it catches up with your plumbing and the pressure builds until a joint
#     goes (you were not laying pipe fast enough);
#   * it reaches a cell with pipe hanging off it that is not on the route --
#     a leak. A wrong guess only bites once the water gets there.
var mode := MODE_FLOW
var lost := false
var zen_locked := false            # this puzzle has been dropped to Zen for good
var flowing := false               # grace is over, water is on the move
var grace_left := 0.0
var flow_pos := 0.0                # position along sol_path, in cells
var flow_spc := 4.0                # seconds per cell
var pressure_left := 0.0
var burst_cell := Vector2i(-1, -1)
# Off by default on purpose: flagging a wrong pipe the moment it is laid hands
# the player the deduction they came to make. Opt in with the button or M.
var show_errors := false
var hint_cells: Dictionary = {}    # cells given away by Hint

# geometry, recomputed per puzzle
var cell := 48.0
var origin := Vector2.ZERO
var gutter := 90.0
var gutter_l := 90.0
var gutter_t := 90.0
var clue_font := 18

# input
# What a plain drag paints. On a desktop the right button does the opposite, but
# a phone has no right button, so this toggle is the only way to reach both.
# Godot's emulate_mouse_from_touch is on, so a finger arrives as a left drag.
var paint_mode := PIPE
var dragging := false
var drag_to := UNKNOWN
var painted: Dictionary = {}
var hover := Vector2i(-1, -1)
var buttons: Array = []
var pipe_flanges: Array = []   # collars, drawn over the water
var mouse := Vector2.ZERO

# headless screenshot mode
var shot_path := ""
var shot_solve := false
var shot_flow := false
var logic_test := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	_parse_args()
	_load_puzzles()
	if puzzles.is_empty():
		push_error("No puzzles found at res://data/puzzles.json -- run tools/generate.py")
		return
	if logic_test:
		_logic_test()
		return
	_load_puzzle(index)
	if shot_path != "":
		await _take_shot()


func _flow_test(i: int) -> Array[String]:
	## Drive flow mode through its three endings: water reaches the outlet,
	## water catches up and bursts, water finds a wrong joint and bursts.
	var errs: Array[String] = []
	var step := 0.25
	mode = MODE_FLOW

	# 1. the whole route laid -- the water should get home
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	for c in solution:
		_set_mark(c, PIPE)
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

	# 3. a wrong cell touching the inlet -- the water should find the leak
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	var wrong := Vector2i(-1, -1)
	for d in DIRS:
		var n: Vector2i = inlet + d
		if _in_grid(n) and not solution.has(n):
			wrong = n
			break
	if wrong.x >= 0:
		_set_mark(wrong, PIPE)
		_flow_step(step)
		if not lost:
			errs.append("water ignored a leak at " + str(wrong))
		elif burst_cell != wrong:
			errs.append("burst reported at " + str(burst_cell)
					+ " not " + str(wrong))

	# 4. dropping to Zen must not hand back a fresh clock
	_load_puzzle(i)
	grace_left = 0.0
	flowing = true
	for k in mini(6, sol_path.size()):
		_set_mark(sol_path[k], PIPE)
	for _n in 8:
		_flow_step(step)
	var pos_before := flow_pos
	var laid_before := _laid_prefix()
	_do_action("mode")
	if mode != MODE_ZEN or not zen_locked:
		errs.append("Flow did not drop to Zen")
	if _laid_prefix() != laid_before:
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


func _logic_test() -> void:
	## Play every puzzle through the same calls the mouse uses. The screenshot
	## path writes `marks` directly, so it cannot catch anything _set_mark gets
	## wrong -- which is how the unlaid-taps bug survived a visual check.
	var fails := 0
	for i in puzzles.size():
		_load_puzzle(i)
		var pname: String = str(puzzles[index].get("name", "?"))
		var errs: Array[String] = []

		# the taps have to be real pipe in the grid, not just drawn on top
		if _mark_at(inlet) != PIPE:
			errs.append("inlet not laid as pipe")
		if _mark_at(outlet) != PIPE:
			errs.append("outlet not laid as pipe")

		# lay the pipe the way a player does, through _set_mark
		for c in solution:
			_set_mark(c, PIPE)
		_check_solved()
		if not solved:
			errs.append("never registers as solved")

		# each tap must end up joined to exactly one neighbour
		for tap in [inlet, outlet]:
			var n := _connections(tap).size()
			if n != 1:
				errs.append("tap " + str(tap) + " has " + str(n) + " connections")

		# and the pipe has to read as one unbroken run of the right length
		if sol_path.size() != solution.size():
			errs.append("pipe traces " + str(sol_path.size()) + " of "
					+ str(solution.size()) + " cells")

		errs.append_array(_flow_test(i))

		if errs.is_empty():
			print("  " + pname + ": OK")
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
			"--flow":
				shot_flow = true
			"--zen":
				mode = MODE_ZEN


func _load_puzzles() -> void:
	var f := FileAccess.open("res://data/puzzles.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("puzzles"):
		puzzles = parsed["puzzles"]


func _load_puzzle(i: int) -> void:
	index = wrapi(i, 0, puzzles.size())
	var p: Dictionary = puzzles[index]

	W = int(p["w"])
	H = int(p["h"])
	row_clues = p["row_clues"]
	col_clues = p["col_clues"]
	inlet = Vector2i(int(p["inlet"][1]), int(p["inlet"][0]))    # json is [row, col]
	outlet = Vector2i(int(p["outlet"][1]), int(p["outlet"][0]))

	solution.clear()
	var rows: Array = p["solution"]
	for y in H:
		var line: String = rows[y]
		for x in W:
			if line[x] == "1":
				solution[Vector2i(x, y)] = true

	sol_path = _trace_solution()

	marks = []
	for y in H:
		var row := []
		row.resize(W)
		row.fill(UNKNOWN)
		marks.append(row)

	undo_stack.clear()
	hint_cells.clear()
	solved = false
	water = 0.0
	elapsed = 0.0

	lost = false
	zen_locked = false             # the lock is per puzzle, not for the session
	flowing = false
	flow_pos = 0.0
	burst_cell = Vector2i(-1, -1)
	pressure_left = PRESSURE_SECONDS
	grace_left = GRACE_BASE + GRACE_PER_CELL * float(sol_path.size())
	flow_spc = FLOW_SPC

	# the inlet and outlet are given -- they are the taps you can see
	# Written straight in: _set_mark refuses cells that _is_given() covers, and
	# that includes the taps. Going through it here left them unlaid, so nothing
	# could ever join onto them and no puzzle could be completed.
	marks[inlet.y][inlet.x] = PIPE
	marks[outlet.y][outlet.x] = PIPE

	_layout()
	queue_redraw()


func _trace_solution() -> Array:
	## Walk the solution from the inlet to get the pipe in order.
	var out := [inlet]
	var seen := {inlet: true}
	var cur := inlet
	while true:
		var nxt := Vector2i(-1, -1)
		for d in DIRS:
			var n: Vector2i = cur + d
			if solution.has(n) and not seen.has(n):
				nxt = n
				break
		if nxt.x < 0:
			break
		seen[nxt] = true
		out.append(nxt)
		cur = nxt
	return out


func _layout() -> void:
	var avail_w := VW - 40.0
	# board bottom lands at 196 + avail_h, which must stay clear of the banner
	var avail_h := 620.0

	# The gutters have to hold the longest clue in either direction, so size
	# the cells and the gutters together: two passes settle it.
	gutter_l = 86.0
	gutter_t = 86.0
	if font == null:          # headless logic runs have no font to measure
		cell = min((avail_w - gutter_l) / float(W), (avail_h - gutter_t) / float(H))
		origin = Vector2((VW - (cell * W + gutter_l)) * 0.5 + gutter_l, 196.0 + gutter_t)
		gutter = gutter_l
		return
	for _pass in 2:
		cell = min((avail_w - gutter_l) / float(W), (avail_h - gutter_t) / float(H))
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

	var board_w := cell * W
	origin = Vector2((VW - (board_w + gutter_l)) * 0.5 + gutter_l, 196.0 + gutter_t)
	gutter = gutter_l


# =========================================================================
#  marks
# =========================================================================

func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func _mark_at(c: Vector2i) -> int:
	if not _in_grid(c):
		return BLOCKED       # outside the grid counts as "no pipe"
	return marks[c.y][c.x]


func _other_mark(m: int) -> int:
	return BLOCKED if m == PIPE else PIPE


func _is_given(c: Vector2i) -> bool:
	return c == inlet or c == outlet or hint_cells.has(c)


func _set_mark(c: Vector2i, v: int, record := true) -> void:
	if not _in_grid(c) or _is_given(c):
		return
	if marks[c.y][c.x] == v:
		return
	if record:
		undo_stack.push_back([c, marks[c.y][c.x]])
		if undo_stack.size() > 600:
			undo_stack.pop_front()
	marks[c.y][c.x] = v


func _undo() -> void:
	if undo_stack.is_empty() or solved:
		return
	var e: Array = undo_stack.pop_back()
	var c: Vector2i = e[0]
	marks[c.y][c.x] = e[1]
	queue_redraw()


func _connections(c: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		if _mark_at(c + d) == PIPE:
			out.append(d)
	return out


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


# =========================================================================
#  flow mode
# =========================================================================

func _laid_prefix() -> int:
	## How many cells of the real route, from the inlet, are laid as pipe.
	## The water can travel exactly this far and no further.
	var n := 0
	for c in sol_path:
		if _mark_at(c) == PIPE:
			n += 1
		else:
			break
	return n


func _find_leak(upto: int) -> Vector2i:
	## Pipe hanging off the wetted line that is not part of the route. Correct
	## pipe can never do this -- the route never runs alongside itself -- so
	## anything found here is a mistake the water has just reached.
	for i in range(mini(upto + 1, sol_path.size())):
		var c: Vector2i = sol_path[i]
		for d in DIRS:
			var n: Vector2i = c + d
			if _mark_at(n) != PIPE:
				continue
			if i > 0 and n == sol_path[i - 1]:
				continue
			if i + 1 < sol_path.size() and n == sol_path[i + 1]:
				continue
			return n
	return Vector2i(-1, -1)


func _burst(c: Vector2i) -> void:
	lost = true
	burst_cell = c
	queue_redraw()


func _flow_step(delta: float) -> void:
	if mode != MODE_FLOW or solved or lost or sol_path.is_empty():
		return

	if grace_left > 0.0:
		grace_left -= delta
		if grace_left > 0.0:
			return
		flowing = true

	# a wrong joint on the stretch the water has already reached
	var leak := _find_leak(int(flow_pos))
	if leak.x >= 0:
		_burst(leak)
		return

	var laid := _laid_prefix()
	var target := float(laid - 1)
	var last := float(sol_path.size() - 1)

	if flow_pos < target:
		flow_pos = minf(flow_pos + delta / flow_spc, target)
		pressure_left = PRESSURE_SECONDS
		if flow_pos >= last:
			solved = true
	else:
		# caught up with the plumbing -- the pressure starts to tell
		pressure_left -= delta
		if pressure_left <= 0.0:
			_burst(sol_path[mini(laid, sol_path.size() - 1)])
			return

	water = flow_pos / maxf(last, 1.0)


func _check_solved() -> void:
	## The generator guarantees one solution, so matching the pipe set is
	## exactly equivalent to satisfying every clue and the pipe rule.
	var count := 0
	for y in H:
		for x in W:
			if marks[y][x] == PIPE:
				count += 1
				if not solution.has(Vector2i(x, y)):
					return
	if count == solution.size():
		solved = true
		# In flow mode the water is already part way along; restarting it at
		# the inlet would look like a glitch.
		if mode == MODE_ZEN:
			water = 0.0


# =========================================================================
#  input
# =========================================================================

func _cell_from_point(p: Vector2) -> Vector2i:
	var rel := p - origin
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)
	var c := Vector2i(int(rel.x / cell), int(rel.y / cell))
	return c if _in_grid(c) else Vector2i(-1, -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = get_global_mouse_position()
		var c := _cell_from_point(mouse)
		if c != hover:
			hover = c
			queue_redraw()
		if dragging and _in_grid(c) and not painted.has(c):
			painted[c] = true
			_set_mark(c, drag_to)
			_after_change()
		elif dragging:
			pass
		else:
			for b in buttons:
				if (b["rect"] as Rect2).has_point(mouse):
					queue_redraw()
					break

	elif event is InputEventMouseButton:
		mouse = get_global_mouse_position()
		var mb := event as InputEventMouseButton
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
			var cur: int = marks[c.y][c.x]
			var left := mb.button_index == MOUSE_BUTTON_LEFT
			if not left and mb.button_index != MOUSE_BUTTON_RIGHT:
				return
			var want: int = paint_mode if left else _other_mark(paint_mode)
			if _is_given(c):
				# A tap is fixed pipe, so taking its mark as the drag mode would
				# turn the gesture into an eraser. Starting a drag at the inlet
				# is how you naturally begin, so make it paint outwards.
				drag_to = want
			else:
				# dragging off a cell that already has this mark rubs it out
				drag_to = UNKNOWN if cur == want else want
			dragging = true
			painted = {c: true}
			_set_mark(c, drag_to)
			_after_change()
		elif not mb.pressed:
			dragging = false
			painted.clear()

	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_R: _do_action("reset")
			KEY_N, KEY_RIGHT: _do_action("next")
			KEY_P, KEY_LEFT: _do_action("prev")
			KEY_H: _do_action("hint")
			KEY_M: _do_action("errors")
			KEY_F: _do_action("mode")
			KEY_SPACE, KEY_TAB: _do_action("tap")
			KEY_Z: _undo()
			KEY_ESCAPE: get_tree().quit()


func _after_change() -> void:
	if not solved:
		_check_solved()
	queue_redraw()


func _do_action(a: String) -> void:
	match a:
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
				water = 0.0
				queue_redraw()
			elif not zen_locked:
				# opting into the chase part way through: keep the board, start
				# the water's clock from now
				mode = MODE_FLOW
				flowing = false
				flow_pos = 0.0
				water = 0.0
				pressure_left = PRESSURE_SECONDS
				grace_left = GRACE_BASE + GRACE_PER_CELL * float(sol_path.size())
				queue_redraw()
		"tap":
			paint_mode = _other_mark(paint_mode)
			queue_redraw()
		"hint": _give_hint()


func _give_hint() -> void:
	if solved:
		return
	## Hand over one cell the player has not got right yet.
	var wrong := []
	var blank := []
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if _is_given(c):
				continue
			var want: int = PIPE if solution.has(c) else BLOCKED
			if marks[y][x] == UNKNOWN:
				blank.append(c)
			elif marks[y][x] != want:
				wrong.append(c)
	var pool: Array = wrong if not wrong.is_empty() else blank
	if pool.is_empty():
		return
	var c: Vector2i = pool[randi() % pool.size()]
	marks[c.y][c.x] = PIPE if solution.has(c) else BLOCKED
	hint_cells[c] = true
	_after_change()


# =========================================================================
#  process
# =========================================================================

func _process(delta: float) -> void:
	if puzzles.is_empty() or lost:
		return
	if solved:
		if water < 1.0:
			water = minf(water + delta * 0.55, 1.0)
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

func _draw() -> void:
	draw_rect(Rect2(0, 0, VW, VH), C_BG, true)
	if puzzles.is_empty():
		_text_c("No puzzles. Run: heavy python3 tools/generate.py", Vector2(VW * 0.5, VH * 0.5), 20, C_BAD)
		return

	_draw_header()
	_draw_clues()
	_draw_cells()
	_draw_pipes()
	if solved or flowing:
		_draw_water()
	_draw_flanges()
	_draw_taps()
	if lost:
		_draw_burst()
	_draw_footer()
	if solved:
		_draw_banner()
	elif lost:
		_draw_lost_banner()


# ---- header --------------------------------------------------------------

func _draw_header() -> void:
	var p: Dictionary = puzzles[index]
	_text_c("PIPEGRAM", Vector2(VW * 0.5, 56), 38, C_ACCENT)
	_text_c("lay the pipe by the numbers", Vector2(VW * 0.5, 84), 17, C_TEXT_DIM)

	var label := "%s  ·  %d×%d  ·  puzzle %d/%d" % [
		str(p.get("name", "?")), W, H, index + 1, puzzles.size()]
	_text_c(label, Vector2(VW * 0.5, 128), 19, C_TEXT)

	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	var t := "%d:%02d" % [mins, secs]
	_text_c(t, Vector2(VW * 0.5, 160), 17, C_GOOD if solved else C_TEXT_DIM)

	# flow status: how long until the water starts, or how close it is behind you
	if mode != MODE_FLOW or solved or lost:
		return
	if grace_left > 0.0:
		_text_c("water in %d s" % int(ceil(grace_left)),
				Vector2(VW * 0.5, 182), 17, C_ACCENT)
		return

	var laid := _laid_prefix()
	var ahead := float(laid - 1) - flow_pos
	if ahead > 0.35:
		_text_c("water rising — %d cells of pipe ahead of it" % int(ahead),
				Vector2(VW * 0.5, 182), 17, C_WATER)
	else:
		# the water has caught up; this is the countdown that kills you
		var frac := clampf(pressure_left / PRESSURE_SECONDS, 0.0, 1.0)
		_text_c("PRESSURE BUILDING — %.1f s" % pressure_left,
				Vector2(VW * 0.5, 182), 18, C_BAD)
		var bw := 300.0
		var br := Rect2(VW * 0.5 - bw * 0.5, 190.0, bw, 6.0)
		draw_rect(br, C_PANEL, true)
		draw_rect(Rect2(br.position, Vector2(bw * frac, br.size.y)), C_BAD, true)


# ---- clues ---------------------------------------------------------------

func _draw_clues() -> void:
	var board_w := cell * W
	var board_h := cell * H

	# panel behind the clue gutters
	draw_rect(Rect2(origin.x - gutter_l, origin.y - gutter_t,
			board_w + gutter_l, board_h + gutter_t), C_PANEL, true)

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


# ---- cells ---------------------------------------------------------------

func _draw_cells() -> void:
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			var r := Rect2(origin.x + x * cell, origin.y + y * cell, cell, cell)
			var base := C_CELL if (x + y) % 2 == 0 else C_CELL_ALT
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

			if show_errors and not solved and m == PIPE and not solution.has(c):
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


func _draw_pipes() -> void:
	## Drawn as a lit tube rather than a flat line: a dark rim, a body, a lit
	## side and a specular streak, all offset towards a light up and to the
	## left. Collars go on at the section joins afterwards, over the water, the
	## way a real coupling wraps the outside of the pipe.
	var w := cell * 0.36
	pipe_flanges.clear()

	var legs: Array = []          # [centre, outer end, direction]
	var joints: Array = []        # cell centres, where legs meet
	for y in H:
		for x in W:
			if marks[y][x] != PIPE:
				continue
			var c := Vector2i(x, y)
			var ctr := _cell_centre(c)
			var conns := _connections(c)
			joints.append(ctr)
			for d in conns:
				var dv := Vector2(d)
				# overshoot slightly so neighbouring cells meet with no seam
				legs.append([ctr, ctr + dv * (cell * 0.5 + 0.7), dv])
				pipe_flanges.append([ctr + dv * (cell * 0.5), dv])

	# light from the upper left: for a horizontal run that is upwards, for a
	# vertical run it is to the left
	var lit := func(d: Vector2, amount: float) -> Vector2:
		return Vector2(-absf(d.y), -absf(d.x)) * amount

	# Each layer is drawn across every leg before the next starts, so one
	# cell's rim can never land on top of a neighbour's body.
	var layers := [
		[C_PIPE_SHADOW, 1.10, 0.00],
		[C_PIPE_DARK,   0.94, 0.00],
		[C_PIPE,        0.74, 0.08],
		[C_PIPE_LIGHT,  0.40, 0.20],
		[C_PIPE_HI,     0.15, 0.29],
	]
	for layer in layers:
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


func _draw_water() -> void:
	if sol_path.is_empty():
		return
	var thick := cell * 0.36 * 0.50
	var last := float(sol_path.size() - 1)

	# `water` is 0..1 across the route, so the front sits exactly at
	# water * (cells - 1) -- the same units flow_pos counts in.
	var front := clampf(water, 0.0, 1.0) * last
	var full := clampi(int(floor(front)), 0, sol_path.size() - 1)
	var frac := clampf(front - float(full), 0.0, 1.0)

	# One continuous run of water ending at the exact front, rather than
	# per-cell halves -- drawing a cell's inbound half as soon as the front
	# entered it made the water lurch half a cell at every boundary.
	var pts := PackedVector2Array()
	for i in range(full + 1):
		pts.append(_cell_centre(sol_path[i]))
	var head: Vector2 = pts[pts.size() - 1]
	if full < sol_path.size() - 1 and frac > 0.0:
		head = _cell_centre(sol_path[full]).lerp(_cell_centre(sol_path[full + 1]), frac)
		pts.append(head)

	# shaded channel, brighter core, then a sheen along the top: it has to read
	# as liquid sitting inside the bore, not a line painted over the pipe
	# Each colour finishes before the next starts. Painting the shaded circles
	# after the bright core left a ring at every cell centre.
	if pts.size() >= 2:
		draw_polyline(pts, C_WATER_DEEP, thick, true)
	for i in range(pts.size() - 1):
		draw_circle(pts[i], thick * 0.5, C_WATER_DEEP)
	if pts.size() >= 2:
		draw_polyline(pts, C_WATER, thick * 0.64, true)
	for i in range(pts.size() - 1):
		draw_circle(pts[i], thick * 0.32, C_WATER)
	if pts.size() >= 2:
		var sheen := PackedVector2Array()
		for p in pts:
			sheen.append(p + Vector2(-thick * 0.15, -thick * 0.21))
		draw_polyline(sheen, Color(C_WATER_HI.r, C_WATER_HI.g, C_WATER_HI.b, 0.45),
				thick * 0.20, true)
	draw_circle(head, thick * 0.58, C_WATER_HI)


func _draw_taps() -> void:
	for c in [inlet, outlet]:
		var ctr := _cell_centre(c)
		var is_in: bool = c == inlet
		var col := C_GOOD if is_in else C_WATER
		draw_arc(ctr, cell * 0.30, 0, TAU, 28, col, maxf(cell * 0.055, 2.0), true)

		# an arrowhead just inside the board edge, showing which way water goes.
		# kept inside the cell so it never collides with the clue numbers.
		var d := _outward(c)
		if d == Vector2i.ZERO:
			continue
		var dv := Vector2(d)
		var side := Vector2(-dv.y, dv.x)
		var tip_out := ctr + dv * (cell * 0.5 - cell * 0.04)
		var tip_in := ctr + dv * (cell * 0.5 - cell * 0.30)
		# inlet points inward (water arriving), outlet points outward (leaving)
		var tip := tip_out if not is_in else tip_in
		var back := tip_in if not is_in else tip_out
		var wing := cell * 0.15
		draw_colored_polygon(PackedVector2Array([
			tip, back + side * wing, back - side * wing]), col)


func _outward(c: Vector2i) -> Vector2i:
	if c.y == 0:
		return Vector2i(0, -1)
	if c.y == H - 1:
		return Vector2i(0, 1)
	if c.x == 0:
		return Vector2i(-1, 0)
	if c.x == W - 1:
		return Vector2i(1, 0)
	return Vector2i.ZERO


# ---- footer / buttons ----------------------------------------------------

func _draw_footer() -> void:
	buttons.clear()
	var mode_label := "Mode: Flow"
	var mode_off := false
	if mode == MODE_ZEN:
		if zen_locked:
			mode_label = "Zen (locked)"
			mode_off = true
		else:
			mode_label = "Mode: Zen"
	var labels := [
		["‹ Prev", "prev", false], ["Reset", "reset", false], ["Hint", "hint", false],
		[mode_label, "mode", mode_off], ["Next ›", "next", false],
	]
	# --- what a tap does: the primary control once there is no right button --
	var tr := Rect2(20.0, 908.0, VW - 40.0, 64.0)
	var laying := paint_mode == PIPE
	var tint := C_PIPE if laying else C_BLOCK
	draw_rect(tr, C_BTN_HOT if tr.has_point(mouse) else C_BTN, true)
	draw_rect(tr, tint, false, 2.0)

	# a swatch of what a tap puts down
	var sw := Rect2(tr.position + Vector2(16.0, 12.0), Vector2(40.0, 40.0))
	draw_rect(sw, C_CELL, true)
	var sc := sw.position + sw.size * 0.5
	if laying:
		draw_line(sc - Vector2(20, 0), sc + Vector2(20, 0), C_PIPE_DARK, 17.0, true)
		draw_line(sc - Vector2(20, 0), sc + Vector2(20, 0), C_PIPE, 11.0, true)
	else:
		draw_line(sc + Vector2(-11, -11), sc + Vector2(11, 11), C_BLOCK, 4.0, true)
		draw_line(sc + Vector2(-11, 11), sc + Vector2(11, -11), C_BLOCK, 4.0, true)

	_text_c("tap lays PIPE" if laying else "tap marks EMPTY",
			Vector2(VW * 0.5, 938), 21, tint)
	_text_c("tap here to switch   ·   on a mouse, right-drag does the other",
			Vector2(VW * 0.5, 961), 14, C_TEXT_DIM)
	buttons.append({"rect": tr, "action": "tap"})

	var total := VW - 40.0
	var gap := 8.0
	var bw := (total - gap * (labels.size() - 1)) / labels.size()
	var by := 982.0
	var bh := 48.0
	for i in labels.size():
		var r := Rect2(20.0 + i * (bw + gap), by, bw, bh)
		var off: bool = labels[i][2]
		var hot := r.has_point(mouse) and not off
		draw_rect(r, C_BTN_HOT if hot else C_BTN, true)
		draw_rect(r, C_GRID_BOLD, false, 1.0)
		var lc := C_TEXT_DONE if off else (C_TEXT if hot else C_TEXT_DIM)
		_text_c(labels[i][0], r.position + Vector2(r.size.x * 0.5, bh * 0.5 + 6.0),
				17, lc)
		buttons.append({"rect": r, "action": labels[i][1]})

	# legend for the two taps
	var ly := 1048.0
	draw_circle(Vector2(254, ly - 5), 6.0, C_GOOD)
	_text_c("inlet", Vector2(290, ly), 15, C_TEXT_DIM)
	draw_circle(Vector2(430, ly - 5), 6.0, C_WATER)
	_text_c("outlet", Vector2(470, ly), 15, C_TEXT_DIM)

	_text_c("the pipe never runs alongside itself — touching pipe cells are always joined",
			Vector2(VW * 0.5, 1070), 15, C_TEXT_DONE)


func _draw_burst() -> void:
	if burst_cell.x < 0:
		return
	var ctr := _cell_centre(burst_cell)
	var r := Rect2(origin.x + burst_cell.x * cell, origin.y + burst_cell.y * cell, cell, cell)
	draw_rect(r, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.35), true)
	# a splash of spray out of the failed joint
	for i in 12:
		var a := TAU * float(i) / 12.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(ctr + dir * (cell * 0.16), ctr + dir * (cell * 0.46),
				C_WATER_HI, maxf(cell * 0.05, 2.0), true)
	draw_arc(ctr, cell * 0.30, 0, TAU, 24, C_BAD, maxf(cell * 0.06, 2.0), true)


func _draw_lost_banner() -> void:
	var r := Rect2(20.0, 820.0, VW - 40.0, 80.0)
	draw_rect(r, Color(C_BAD.r * 0.26, C_BAD.g * 0.12, C_BAD.b * 0.16, 0.95), true)
	draw_rect(r, C_BAD, false, 2.0)
	_text_c("BURST", Vector2(VW * 0.5, 854), 28, C_BAD)
	var laid := _laid_prefix()
	var why := "the water caught up with your plumbing"
	if _find_leak(int(flow_pos)).x >= 0:
		why = "the water found pipe that was never on the route"
	_text_c("%s — %d of %d cells laid. Click to try again."
			% [why, laid, sol_path.size()],
			Vector2(VW * 0.5, 884), 16, C_TEXT)


func _draw_banner() -> void:
	var r := Rect2(20.0, 820.0, VW - 40.0, 80.0)
	draw_rect(r, Color(C_GOOD.r * 0.18, C_GOOD.g * 0.3, C_GOOD.b * 0.22, 0.95), true)
	draw_rect(r, C_GOOD, false, 2.0)
	_text_c("WATER'S ON", Vector2(VW * 0.5, 854), 28, C_GOOD)
	var mins := int(elapsed) / 60
	var secs := int(elapsed) % 60
	_text_c("%d cells of pipe in %d:%02d — click anywhere for the next one"
			% [solution.size(), mins, secs],
			Vector2(VW * 0.5, 884), 16, C_TEXT)


# ---- text helpers --------------------------------------------------------

func _text_c(t: String, centre: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(centre.x - w * 0.5, centre.y), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_r(t: String, right: Vector2, size: int, col: Color) -> void:
	var m := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	draw_string(font, Vector2(right.x - m.x, right.y + size * 0.36), t,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ---- screenshot mode -----------------------------------------------------

func _take_shot() -> void:
	if shot_solve:
		# through _set_mark, not straight into `marks` -- a screenshot that
		# skips the real editing path cannot be trusted as a check
		for c in solution:
			_set_mark(c, PIPE)
		for y in H:
			for x in W:
				if marks[y][x] == UNKNOWN:
					_set_mark(Vector2i(x, y), BLOCKED)
		_check_solved()
		solved = true
		water = 0.62
		elapsed = 184.0
	elif shot_flow:
		# mid-chase: part of the route laid, the water some way behind it
		grace_left = 0.0
		flowing = true
		var n := maxi(int(float(sol_path.size()) * 0.62), 2)
		for i in n:
			_set_mark(sol_path[i], PIPE)
		flow_pos = float(n) * 0.55
		water = flow_pos / maxf(float(sol_path.size() - 1), 1.0)
		pressure_left = PRESSURE_SECONDS
		elapsed = 47.0
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_path)
	get_tree().quit()
