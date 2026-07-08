extends Node3D
## Falling-cubes grid game.
##
## Pieces fall into the camera-facing front of a 2x2 grid. The player spins the
## whole grid with Q/E (90 degree snap turns) to choose which stacks land under
## the piece. Most pieces are a single cube; ~15% are rigid multi-cube shapes
## that fit within the 2x2 footprint and may overhang. Connected groups of >= 3
## same-colour cubes clear; blocks above fall to fill the gaps.

# ── Gameplay tunables ─────────────────────────────────────────────────────
const CELL := 1.0            # cube + cell footprint (world units)
const FALL_SPEED := 2.1      # descent speed (units / second)
const HARD_DROP_SPEED := 40.0 # space-bar slam speed (units / second)
const CUBE_SIZE := 0.9       # visible cube edge (< CELL leaves a tidy gap)
const SPIN_TIME := 0.133     # seconds for one 90 degree turn (50% faster than 0.2)
const ROTATE_TIME := 0.12    # seconds for a piece's R-rotation animation
const SPAWN_DELAY := 0.25    # pause between a lock and the next spawn
const BEAM_RADIUS := 0.1     # radius of the glowing landing beam
const SPAWN_MIN := 8.0       # spawn/hover height over an empty board (lower = camera closer)
const SPAWN_GAP := 4.0       # blocks always hover this far above the tallest tower
const MATCH_MIN := 3         # a connected same-colour group of this many clears
const MULTI_CHANCE := 0.25   # chance a spawned piece is a rigid multi-cube shape
const OBSIDIAN_CHANCE := 0.07 # chance a spawned piece is a single weighted obsidian block
const OBSIDIAN := 3          # 4th block type index (past the 3 colours): weighted obsidian
const OBSIDIAN_MIN_BLOCKS := 15 # obsidian can't spawn until this many blocks have landed
const OBSIDIAN_BREAK_INTERVAL := 0.13 # seconds between each block an obsidian breaks

# ── Scoring ───────────────────────────────────────────────────────────────
const POINTS_PER_BLOCK := 10 # score per cleared block, multiplied by the combo step
const OBSIDIAN_POINTS := 50  # awarded when an obsidian block reaches the floor
const FULL_CLEAR_POINTS := 1000  # bonus for wiping every block off the board
const START_SINGLES := 7     # single blocks seeded onto the board at the start of a match
const START_MULTIS := 3      # multi-blocks seeded onto the board at the start of a match
const START_FALL_OFFSET := 12.0  # height above its slot an intro block begins its drop
const START_FALL_TIME := 0.42    # intro block fall duration (seconds)
const START_DROP_GAP := 0.12     # pause between successive intro blocks
# The camera opens low and close to the grid, then helixes up-and-out, settling into
# its normal framing over exactly the time the opening blocks take to fall.
const INTRO_CAM_TIME := (START_SINGLES + START_MULTIS) * (START_FALL_TIME + START_DROP_GAP)
const INTRO_CAM_START_R := 2.5      # horizontal distance from the grid at the start
const INTRO_CAM_START_Y := 1.0      # camera height at the start (low, by the base)
const INTRO_CAM_START_FOCUS := 0.6  # look-at height at the start (base of the grid)
const INTRO_CAM_SWEEP := TAU * 1.25 # how far the helix spirals around before settling

# ── Match FX / feel ───────────────────────────────────────────────────────
const BLINK_COUNT := 6        # white emission on/off flashes before a group explodes
const BLINK_INTERVAL := 0.07  # seconds per blink flash
const EXPLODE_HOLD := 0.12    # pause after the burst before gravity settles
const CRACK_HOLD := 0.16      # beat between fresh cracks appearing and the shatter they cause
const CRACK_IMPACTS := 3      # impacts a block takes before it shatters (crack, worse crack, boom)
const CRACK_VARIANTS := 3     # distinct crack patterns generated per damage level
const SETTLE_HOLD := 0.24     # pause after gravity (lets the settle-fall land) before cascades
const SHAKE_MAX := 0.7        # cap on camera-shake offset (world units) — "within reason"
const SHAKE_PER_BLOCK := 0.045 # shake added per exploded block
const SHAKE_PER_COMBO := 0.14 # extra shake per cascade step in a chain
const SHAKE_DECAY := 1.8      # shake falloff (units / second)

# ── Audio ─────────────────────────────────────────────────────────────────
const PITCH_JITTER := 0.08    # +/- random pitch on every SFX so repeats don't sound stale
const MUSIC_VOL := -18.0      # background track volume in dB (well under the SFX so it never drowns them)
const SFX_VOL := {            # per-sound playback volume in dB
	"hard_drop": -6.0,
	"land_soft": -10.0,
	"land_hard": -4.0,
	"blink": -8.0,
	"explode": -3.0,
	"obsidian": -3.0,
	"spin_left": -9.0,
	"spin_right": -9.0,
	"rotate": -8.0,
}

# ── Camera tunables ───────────────────────────────────────────────────────
const CAM_DIR := Vector3(1.0, 0.3846, 1.0) # heading from focus point to camera (normalized in _ready)
const CAM_MIN_D := 8.0        # closest the camera ever sits (short towers)
const CAM_MAX_D := 12.0       # furthest the camera zooms out before it starts panning up
const CAM_TOP_MARGIN := 2.5   # headroom kept above the spawn point (also room for the tilt)
const CAM_FIT_MARGIN := 1.5   # >1 pads the framed span (higher = more zoomed out)
const CAM_SMOOTH_TIME := 0.65 # ~seconds to ease onto a new framing (critically damped)
const CAM_SCROLL_WHEEL := 2.4 # focus units moved per mouse-wheel notch
const CAM_SCROLL_PAN := 0.05  # focus units per trackpad two-finger-scroll unit
const CAM_SCROLL_UP := 3.0    # how far above the auto-framing the view can be nudged
const CAM_SCROLL_FLOOR := 1.5 # lowest point the view can pan down to (base of the tower)
const CAM_SCROLL_SMOOTH := 0.22 # ~seconds to ease a manual pan (and the auto-return on drop)
const CAM_TILT_DROP := 2.0    # how far the look-at point drops at the top view (a downward tilt)
const CAM_TILT_FADE := 5.0    # units of downward pan over which the tilt eases back out
const CAM_TILT_TOP_EXTRA := 2.0 # additional tilt as you scroll up to the very top of the range

# Three cube colors, chosen at random per cube.
const COLORS := [
	Color("#e0533d"), # red
	Color("#3dae5a"), # green
	Color("#3d7fe0"), # blue
]

# Local offsets of the 4 grid cells under GridPivot. Because GridPivot sits at
# the origin, at rest these also equal the 4 fixed world quadrants a cube can
# fall into.
const QUADRANTS := [
	Vector3(-0.5, 0.0, -0.5),
	Vector3( 0.5, 0.0, -0.5),
	Vector3(-0.5, 0.0,  0.5),
	Vector3( 0.5, 0.0,  0.5),
]

# Horizontal (edge) neighbours of each cell in the 2x2 ring, by index into
# QUADRANTS/cells. Each cell shares a face with two others; the diagonal cell is
# NOT a neighbour — so matches connect vertically and horizontally but never
# diagonally. Adjacency is preserved as the grid spins (a turn just cycles the
# ring), so it can be fixed here.
const ADJ := [[1, 2], [0, 3], [0, 3], [1, 2]]

# Rotation pivots, tried in order: the front/bottom-centre slot, then the slot on
# the side the piece turns toward (rightmost for CW / leftmost for CCW), then the
# 2x2 centre (which always keeps a piece in grid, e.g. the symmetric flat 2x2).
const ROT_PIVOTS_CW := [Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(0.5, 0.5)]
const ROT_PIVOTS_CCW := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 0.5)]

# Multi-cube piece shapes as [footprint_x, footprint_z, layer] offsets. Footprint
# x/z stay in {0,1} so every shape fits the 2x2; layer is the vertical level.
# All anchor at [0,0,0] (the front, camera-facing quadrant). A mix of horizontal
# and vertical shapes of 2, 3 and 4 cubes.
const SHAPES := [
	[[0, 0, 0], [0, 0, 1]],                             # vertical domino
	[[0, 0, 0], [1, 0, 0]],                             # horizontal domino (X)
	[[0, 0, 0], [0, 1, 0]],                             # horizontal domino (Z)
	[[0, 0, 0], [0, 0, 1], [0, 0, 2]],                  # vertical I3
	[[0, 0, 0], [1, 0, 0], [0, 1, 0]],                  # flat corner (L) over 3 quadrants
	[[0, 0, 0], [0, 0, 1], [1, 0, 1]],                  # standing L (2 up + 1 across the top)
	[[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]],       # flat 2x2 square
	[[0, 0, 0], [0, 0, 1], [0, 0, 2], [0, 0, 3]],       # vertical I4
	[[0, 0, 0], [1, 0, 0], [0, 0, 1], [1, 0, 1]],       # standing 2x2 wall
	[[0, 0, 0], [0, 0, 1], [0, 0, 2], [1, 0, 2]],       # vertical L4 (3 up + 1 across the top)
]

@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var grid_pivot: Node3D = $GridPivot

var cells: Array[Node3D] = []   # the 4 Cell nodes (index matches QUADRANTS/columns)
var columns: Array = []         # per cell: Dictionary height(int) -> {node, color, group}

var cube_mesh: BoxMesh = null   # one shared box mesh for every cube (size never varies)
var cam_half_fit := 0.0         # cached world-half-height-per-distance (fov/heading are fixed)

var piece_root: Node3D = null   # container for the active falling piece
var piece_cubes: Array = []     # entries {node, fx, fz, layer, color}
var piece_group := -1           # group id of the active piece (-1 for a single cube)
var piece_yp := 0.0             # current world y of the piece's layer-0 cubes
var beams: Array = []           # active landing beams (one per footprint column)
var next_group_id := 0          # hands out unique ids to multi-cube pieces
var sfx := {}                   # sound name -> AudioStreamPlayer
var score := 0
var blocks_dropped := 0         # total cubes landed (gates obsidian spawns)
var score_label: Label = null
var next_piece: Dictionary = {}   # spec for the upcoming piece (shape / types / obsidian)
var intro := false                # true while the opening blocks drop in; blocks player input
var intro_elapsed := 0.0          # seconds into the opening helix camera move
var crack_mats: Array = []        # [level-1 variants, level-2 variants] of crack overlay materials
var pip_viewport: SubViewport = null
var pip_holder: Node3D = null      # holds the preview cubes inside the PIP viewport

var spinning := false
var hard_dropping := false      # true while the active piece is doing a space-bar slam
var rotating := false           # true while the active piece plays its R-rotation animation
var resolving := false          # true while a match chain blinks/explodes (pauses falling)
var spawn_timer := 0.0

var cam_dir := Vector3.ONE      # normalized focus->camera heading
var cam_distance := 0.0         # current (smoothed) dolly distance
var cam_focus_y := 0.0          # current (smoothed) look-at height
var cam_dist_vel := 0.0         # smooth-damp velocity for the dolly distance
var cam_focus_vel := 0.0        # smooth-damp velocity for the look-at height
var cam_scroll := 0.0           # current manual vertical view offset (scroll to pan)
var cam_scroll_target := 0.0    # where the scroll offset is easing toward
var cam_scroll_vel := 0.0       # smooth-damp velocity for the scroll offset
var shake_strength := 0.0       # current camera-shake magnitude (decays each frame)


func _ready() -> void:
	cam_dir = CAM_DIR.normalized()
	camera.fov = 62.0
	camera.current = true
	cube_mesh = BoxMesh.new()
	cube_mesh.size = Vector3(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	cam_half_fit = _world_half_height_per_distance()   # constant during play; compute once
	_setup_light()
	_setup_environment()
	_build_grid()
	_setup_sfx()
	_setup_music()
	_setup_cracks()
	_setup_ui()
	# Snap the camera to its framing target so the first frame is right; it lerps to
	# follow as the opening blocks build the tower.
	var target := _camera_target()
	cam_distance = target.x
	cam_focus_y = target.y
	_apply_camera()
	# Drop the opening blocks in one at a time (blocks player input); the first
	# playable piece spawns on its own once the intro finishes.
	_populate_start()


func _setup_light() -> void:
	sun.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#12141c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5a6072")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Bloom so the emissive landing beams actually glow.
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.15
	world_env.environment = env


func _build_grid() -> void:
	for i in QUADRANTS.size():
		var q: Vector3 = QUADRANTS[i]

		# Thin floor tile, checkerboard-shaded so the 4 quadrants read clearly.
		var tile := MeshInstance3D.new()
		var tile_mesh := BoxMesh.new()
		tile_mesh.size = Vector3(CELL, 0.1, CELL)
		tile.mesh = tile_mesh
		var tile_mat := StandardMaterial3D.new()
		var is_light := (int(q.x > 0.0) + int(q.z > 0.0)) % 2 == 0
		tile_mat.albedo_color = Color("#3a3f4b") if is_light else Color("#2b2f39")
		tile.material_override = tile_mat
		tile.position = Vector3(q.x, -0.05, q.z)
		grid_pivot.add_child(tile)

		# Cell = stack anchor. Landed cubes are parented here so they rotate with
		# the grid; columns[i] maps each occupied height to its block.
		var cell := Node3D.new()
		cell.name = "Cell%d" % i
		cell.position = Vector3(q.x, 0.0, q.z)
		grid_pivot.add_child(cell)
		cells.append(cell)
		columns.append({})


# ── Column helpers ────────────────────────────────────────────────────────

func _occupied(ci: int, h: int) -> bool:
	return ci >= 0 and ci < columns.size() and columns[ci].has(h)


func _column_top(ci: int) -> int:
	# One above the highest occupied cell (a new piece rests here); 0 if empty.
	var top := 0
	for h in columns[ci].keys():
		if h + 1 > top:
			top = h + 1
	return top


func _tallest_top() -> float:
	var top := 0.0
	for ci in columns.size():
		var t := float(_column_top(ci)) * CELL
		if t > top:
			top = t
	return top


func _spawn_height() -> float:
	# Always keep a consistent fall above the tallest tower so pieces are never
	# born inside a stack, and there is always something to watch fall.
	return maxf(SPAWN_MIN, _tallest_top() + SPAWN_GAP)


func _column_under(world_q: Vector3) -> int:
	# The cell currently sitting under a fixed world quadrant (changes as the grid
	# spins). At rest the mapping is a clean bijection of the 4 quadrants.
	var best := 0
	var best_d := INF
	for i in cells.size():
		var gp := cells[i].global_position
		var d := Vector2(gp.x - world_q.x, gp.z - world_q.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


# ── Spawning & piece geometry ─────────────────────────────────────────────

func _make_cube(type: int) -> MeshInstance3D:
	var cube := MeshInstance3D.new()
	cube.mesh = cube_mesh   # shared geometry; per-cube look lives in material_override
	cube.material_override = _make_material(type)
	return cube


func _make_material(type: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if type == OBSIDIAN:
		# Dark volcanic glass, tuned to read as shiny in BOTH renderers. FULL
		# metallic relies on environment reflections the Compatibility (WebGL)
		# renderer lacks, so we use PARTIAL metallic + strong specular for a sharp
		# sun glint, a non-black albedo so it catches diffuse light, and a faint
		# emission so it never goes dead-flat against the dark background.
		mat.albedo_color = Color("#241d38")
		mat.metallic = 0.45
		mat.metallic_specular = 0.9
		mat.roughness = 0.14
		mat.emission_enabled = true
		mat.emission = Color("#6a4ad0")
		mat.emission_energy_multiplier = 0.55
	else:
		mat.albedo_color = COLORS[type]
	return mat


func _type_color(type: int) -> Color:
	# Glow colour used for a type's landing beam and shatter particles.
	if type == OBSIDIAN:
		return Color("#9a6cff")
	return COLORS[type]


func _roll_piece() -> Dictionary:
	# Decide a piece spec up front (shape + per-cube types) so the NEXT preview can
	# show exactly what will spawn.
	var roll := randf()
	if blocks_dropped >= OBSIDIAN_MIN_BLOCKS and roll < OBSIDIAN_CHANCE:
		return {"shape": [[0, 0, 0]], "types": [OBSIDIAN], "obsidian": true}
	if roll < OBSIDIAN_CHANCE + MULTI_CHANCE:
		var shp: Array = SHAPES[randi() % SHAPES.size()]
		return {"shape": shp, "types": _roll_multi_colors(shp), "obsidian": false}
	return {"shape": [[0, 0, 0]], "types": [randi() % COLORS.size()], "obsidian": false}


func _roll_multi_colors(shape: Array) -> Array:
	# Colour a multi-cube piece so it never contains its OWN connected group of
	# MATCH_MIN same-colour cubes — that would auto-clear the instant it lands.
	# Random colouring keeps variety (adjacent same-colour PAIRS are fine); only
	# the rare self-matching assignment is re-rolled.
	for _attempt in 50:
		var tps: Array = []
		for _i in shape.size():
			tps.append(randi() % COLORS.size())
		if not _has_internal_match(shape, tps):
			return tps
	return _two_color_piece(shape)   # guaranteed-safe fallback (never adjacent-same)


func _cubes_adjacent(a: Array, b: Array) -> bool:
	# The same face-adjacency the board uses once the piece lands: vertical within a
	# column, or same layer in an edge-adjacent footprint (never diagonal).
	if a[0] == b[0] and a[1] == b[1] and abs(a[2] - b[2]) == 1:
		return true
	if a[2] == b[2] and abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1:
		return true
	return false


func _has_internal_match(shape: Array, types: Array) -> bool:
	# True if any same-colour connected group within the piece reaches MATCH_MIN.
	var n := shape.size()
	var visited := {}
	for i in n:
		if visited.has(i):
			continue
		var comp := 0
		var frontier := [i]
		visited[i] = true
		while not frontier.is_empty():
			var cur: int = frontier.pop_back()
			comp += 1
			for j in n:
				if not visited.has(j) and types[j] == types[cur] and _cubes_adjacent(shape[cur], shape[j]):
					visited[j] = true
					frontier.append(j)
		if comp >= MATCH_MIN:
			return true
	return false


func _two_color_piece(shape: Array) -> Array:
	# Proper 2-colouring (adjacent cubes differ) so no same-colour group exceeds 1.
	# Every shape here is bipartite, so this always yields a self-match-free piece.
	var n := shape.size()
	var col: Array = []
	col.resize(n)
	col.fill(-1)
	for start in n:
		if col[start] != -1:
			continue
		col[start] = 0
		var frontier := [start]
		while not frontier.is_empty():
			var cur: int = frontier.pop_back()
			for j in n:
				if col[j] == -1 and _cubes_adjacent(shape[cur], shape[j]):
					col[j] = 1 - col[cur]
					frontier.append(j)
	return col


func _spawn_piece() -> void:
	if next_piece.is_empty():
		next_piece = _roll_piece()
	var spec: Dictionary = next_piece
	var shape: Array = spec["shape"]
	var types: Array = spec["types"]
	if not spec["obsidian"] and shape.size() > 1:
		piece_group = next_group_id
		next_group_id += 1
	else:
		piece_group = -1

	# All cubes ride a container in world space (they do NOT rotate with the grid
	# while hovering). Footprint x/z map to fixed world quadrants; layer sets y.
	piece_root = Node3D.new()
	add_child(piece_root)
	piece_cubes = []
	for i in shape.size():
		var off: Array = shape[i]
		var type: int = types[i]
		var cube := _make_cube(type)
		var wq := _footprint_world(off[0], off[1])
		cube.position = Vector3(wq.x, float(off[2]) * CELL, wq.z)
		piece_root.add_child(cube)
		piece_cubes.append({"node": cube, "fx": off[0], "fz": off[1], "layer": off[2], "color": type})

	piece_yp = _spawn_height()
	piece_root.position = Vector3(0.0, piece_yp, 0.0)
	hard_dropping = false
	rotating = false
	_make_beams()

	# Roll the following piece and refresh its preview.
	next_piece = _roll_piece()
	_update_pip()


# ── Match start: seed the board ───────────────────────────────────────────

func _populate_start() -> void:
	# Every match opens with blocks dropping onto the board one after another, in full
	# view, before the player takes control: START_SINGLES singles and START_MULTIS
	# multi-blocks into random squares in random order. Nothing seeded is obsidian,
	# and no placement is allowed to form a match.
	intro = true
	intro_elapsed = 0.0
	_update_intro_camera(0.0)   # snap to the low starting pose before the first frame
	var kinds: Array = []
	for _i in START_SINGLES:
		kinds.append(false)
	for _i in START_MULTIS:
		kinds.append(true)
	kinds.shuffle()
	for is_multi in kinds:
		if is_multi:
			await _drop_start_multi()
		else:
			await _drop_start_single()
	intro = false
	spawn_timer = SPAWN_DELAY   # a short beat, then the first playable piece spawns


func _animate_start_drop(cubes: Array, heights: Array) -> void:
	# Fall the piece's cubes from above into their resting slots, together, so a
	# multi-block drops as a rigid unit. Bounce and land-sound on arrival, then a
	# short gap before the next opening block.
	var tween := create_tween().set_parallel(true)
	for i in cubes.size():
		var final_y := 0.5 + float(heights[i]) * CELL
		cubes[i].position = Vector3(0.0, final_y + START_FALL_OFFSET, 0.0)
		tween.tween_property(cubes[i], "position:y", final_y, START_FALL_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	for cube in cubes:
		_bounce_cube(cube, HARD_DROP_SPEED * 0.6)
	_play("land_soft")
	await get_tree().create_timer(START_DROP_GAP).timeout


func _drop_start_single() -> void:
	# Pick a random column/colour that does not complete a match (tentative entries
	# carry a null node so _find_matches can vet the colour), then drop it in.
	for _attempt in 40:
		var ci := randi() % cells.size()
		var h := _column_top(ci)
		var color := randi() % COLORS.size()
		columns[ci][h] = {"node": null, "color": color, "group": -1, "cracks": 0}
		if _find_matches().is_empty():
			var cube := _make_cube(color)
			cells[ci].add_child(cube)
			columns[ci][h]["node"] = cube
			await _animate_start_drop([cube], [h])
			return
		columns[ci].erase(h)
	# Extremely unlikely: 40 random spots all matched. Drop nothing this round.


func _drop_start_multi() -> void:
	# A random shape at a random in-grid rotation, resting on the current column tops,
	# coloured so it neither self-matches nor completes a match against the board.
	# Falls back to a single if nothing fits.
	for _attempt in 60:
		var shape: Array = SHAPES[randi() % SHAPES.size()]
		var turns := randi() % 4
		# Rotate each footprint about the 2x2 centre so the piece stays in the grid.
		var placements: Array = []   # per cube: {ci, layer}
		var min_layer := {}          # cell index -> lowest layer landing there
		for off in shape:
			var f := Vector2i(off[0], off[1])
			for _t in turns:
				f = _cw_cell(f, Vector2(0.5, 0.5))
			var fcell := _column_under(_footprint_world(f.x, f.y))
			placements.append({"ci": fcell, "layer": off[2]})
			if not min_layer.has(fcell) or off[2] < min_layer[fcell]:
				min_layer[fcell] = off[2]
		# Rigid rest: the base height where the whole piece settles onto the tops.
		var base := 0
		for ck in min_layer.keys():
			base = maxi(base, _column_top(ck) - min_layer[ck])
		var types: Array = _roll_multi_colors(shape)
		# Tentatively occupy the cells (null nodes) and check for a match.
		var placed: Array = []
		var ok := true
		for i in placements.size():
			var pci: int = placements[i]["ci"]
			var h: int = base + placements[i]["layer"]
			if columns[pci].has(h):
				ok = false
				break
			columns[pci][h] = {"node": null, "color": types[i], "group": next_group_id, "cracks": 0}
			placed.append({"ci": pci, "h": h, "color": types[i]})
		if ok and _find_matches().is_empty():
			next_group_id += 1
			var cubes: Array = []
			var heights: Array = []
			for p in placed:
				var cube := _make_cube(p["color"])
				cells[p["ci"]].add_child(cube)
				columns[p["ci"]][p["h"]]["node"] = cube
				cubes.append(cube)
				heights.append(p["h"])
			await _animate_start_drop(cubes, heights)
			return
		for p in placed:
			columns[p["ci"]].erase(p["h"])
	# Couldn't seat a multi cleanly; a single always fits.
	await _drop_start_single()


func _check_full_clear() -> void:
	# Wiping every block off the board is worth a big one-time bonus. Called at the
	# end of a resolve chain, so it only fires when a clear actually emptied things.
	for col in columns:
		if not col.is_empty():
			return
	_add_score(FULL_CLEAR_POINTS)
	shake_strength = SHAKE_MAX
	_play("explode", 1.5)


func _footprint_world(fx: int, fz: int) -> Vector3:
	# Footprint (0,0) is the front (camera-facing) quadrant; (1,*)/(*, 1) step back.
	return Vector3(0.5 - float(fx), 0.0, 0.5 - float(fz))


func _piece_footprints() -> Array:
	# Unique footprint columns (Vector2i(fx, fz)) the piece occupies.
	var seen := {}
	var out: Array = []
	for c in piece_cubes:
		var key := Vector2i(c["fx"], c["fz"])
		if not seen.has(key):
			seen[key] = true
			out.append(key)
	return out


func _piece_min_layer(fx: int, fz: int) -> int:
	var m := 1 << 30
	for c in piece_cubes:
		if c["fx"] == fx and c["fz"] == fz:
			m = mini(m, c["layer"])
	return m


func _footprint_bottom_color(fx: int, fz: int) -> int:
	var best_layer := 1 << 30
	var color := 0
	for c in piece_cubes:
		if c["fx"] == fx and c["fz"] == fz and c["layer"] < best_layer:
			best_layer = c["layer"]
			color = c["color"]
	return color


# ── Falling & landing ─────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Two-finger trackpad scroll (pan gesture) and mouse wheel both pan the camera up
	# and down the tower. The offset auto-returns to the top whenever a block is dropped.
	if intro:
		return
	if event is InputEventPanGesture:
		# delta.y > 0 is a downward scroll (matches WHEEL_DOWN), so subtract to pan down.
		cam_scroll_target -= event.delta.y * CAM_SCROLL_PAN
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_scroll_target += CAM_SCROLL_WHEEL
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_scroll_target -= CAM_SCROLL_WHEEL


func _process(delta: float) -> void:
	if intro:
		_update_intro_camera(delta)   # helix from the base up into the normal framing
		return
	_handle_spin_input()
	_handle_rotate_input()
	_update_falling(delta)
	_update_camera(delta)


func _update_falling(delta: float) -> void:
	if resolving:
		return   # a match chain is playing out; hold all falling/spawning
	if piece_root == null:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_piece()
		return

	# The piece HOVERS above the tower until the player commits to a drop with
	# Space. Until then it just holds position while they spin to aim.
	if not hard_dropping:
		if not rotating and Input.is_action_just_pressed("hard_drop"):
			hard_dropping = true
			_play("hard_drop")
			cam_scroll_target = 0.0   # dropping snaps the view back up to the top
		else:
			if not rotating:
				_update_beams()   # beams are tweened by _rotate_piece during a rotation
			return

	# Dropping: descend fast until the piece lands on its first support.
	var rest := _piece_rest_yp()
	var next_yp := piece_yp - HARD_DROP_SPEED * delta
	if next_yp <= rest:
		if spinning:
			# Grid is mid-turn: hover at rest until it settles so it lands cleanly.
			piece_yp = rest
		else:
			_lock_piece(rest)
			return
	else:
		piece_yp = next_yp
	piece_root.position.y = piece_yp
	_update_beams()


func _piece_rest_yp() -> float:
	# Lowest layer-0 y at which some footprint column's lowest cube rests on its
	# current support. The binding column is whichever forces the highest stop.
	var rest := -INF
	for fp in _piece_footprints():
		var ci := _column_under(_footprint_world(fp.x, fp.y))
		var need := float(_column_top(ci)) + 0.5 - float(_piece_min_layer(fp.x, fp.y))
		if need > rest:
			rest = need
	return rest


func _lock_piece(rest_yp: float) -> void:
	var landing_speed := HARD_DROP_SPEED if hard_dropping else FALL_SPEED
	var base := int(round(rest_yp - 0.5))
	var is_obsidian := false
	var obsidian_ci := -1
	var obsidian_node: MeshInstance3D = null
	for c in piece_cubes:
		var ci := _column_under(_footprint_world(c["fx"], c["fz"]))
		var h: int = base + c["layer"]
		var cube: MeshInstance3D = c["node"]
		# Re-home each cube into its cell so it now rotates with the grid.
		cube.reparent(cells[ci], false)
		cube.position = Vector3(0.0, 0.5 + float(h) * CELL, 0.0)
		cube.rotation = Vector3.ZERO
		columns[ci][h] = {"node": cube, "color": c["color"], "group": piece_group, "cracks": 0}
		_bounce_cube(cube, landing_speed)
		if c["color"] == OBSIDIAN:
			is_obsidian = true
			obsidian_ci = ci
			obsidian_node = cube

	if is_obsidian:
		_play("obsidian")
	elif landing_speed >= HARD_DROP_SPEED:
		_play("land_hard")
	else:
		_play("land_soft")

	blocks_dropped += piece_cubes.size()

	piece_root.queue_free()
	piece_root = null
	piece_cubes = []
	hard_dropping = false
	_clear_beams()
	spawn_timer = SPAWN_DELAY

	if is_obsidian:
		_resolve_obsidian(obsidian_ci, obsidian_node)
	else:
		_resolve_matches()


func _resolve_obsidian(ci: int, ob_node: MeshInstance3D) -> void:
	# Obsidian is a colour bomb: it breaks every block of the colour it landed on
	# within its column, one after another. Then, if it has settled onto the floor,
	# it pays out and pops. Finally, any colour-3 matches from the settling resolve.
	resolving = true
	await _obsidian_break(ci, ob_node)
	if _obsidian_height(ci, ob_node) == 0:
		columns[ci].erase(0)
		_spawn_explosion(ob_node.global_position, _type_color(OBSIDIAN))
		ob_node.queue_free()
		_play("explode")
		_add_score(OBSIDIAN_POINTS)
	await _run_match_chain()
	resolving = false


func _obsidian_height(ci: int, ob_node: MeshInstance3D) -> int:
	for h in columns[ci].keys():
		if columns[ci][h]["node"] == ob_node:
			return h
	return -1


func _obsidian_break(ci: int, ob_node: MeshInstance3D) -> void:
	# Break every block of the colour directly beneath the obsidian, one at a time,
	# settling (and letting the obsidian sink) between each.
	var ob_h := _obsidian_height(ci, ob_node)
	if ob_h <= 0 or not columns[ci].has(ob_h - 1):
		return   # landed on the floor / nothing beneath — nothing to break
	var target: int = columns[ci][ob_h - 1]["color"]
	while true:
		var target_h := -1
		var hs: Array = columns[ci].keys()
		hs.sort()
		for h in hs:
			var e: Dictionary = columns[ci][h]
			if e["node"] != ob_node and e["color"] == target:
				target_h = h
				break
		if target_h == -1:
			break
		var entry: Dictionary = columns[ci][target_h]
		if entry["group"] != -1:
			_dissolve_group(entry["group"])
		_spawn_explosion(entry["node"].global_position, _type_color(target))
		entry["node"].queue_free()
		columns[ci].erase(target_h)
		_play("explode")
		shake_strength = minf(shake_strength + SHAKE_PER_BLOCK, SHAKE_MAX)
		_add_score(POINTS_PER_BLOCK)
		# The broken block cracks its neighbours too; detonate any chain it triggers.
		var chain := _apply_cracks([Vector2i(ci, target_h)])
		if not chain.is_empty():
			await _explode_wave(chain, 1)
		_settle_gravity()   # the obsidian and blocks above sink into the gap
		await get_tree().create_timer(OBSIDIAN_BREAK_INTERVAL).timeout


func _dissolve_group(g: int) -> void:
	for c2 in columns.size():
		for h in columns[c2].keys():
			if columns[c2][h]["group"] == g:
				columns[c2][h]["group"] = -1


func _bounce_cube(cube: MeshInstance3D, speed: float) -> void:
	# Squash-and-stretch impact that springs back to normal size. Scale (not
	# position) is animated so it can never fight the block's logical placement,
	# and a faster landing squashes harder. Purely cosmetic.
	var s := clampf(speed / HARD_DROP_SPEED, 0.0, 1.0)
	# A normal fall already lands at the old hard-drop intensity; slams push higher.
	var amt := lerpf(0.38, 0.58, s)
	cube.scale = Vector3(1.0 + amt * 0.6, 1.0 - amt, 1.0 + amt * 0.6)
	var tween := create_tween()
	tween.tween_property(cube, "scale", Vector3.ONE, lerpf(0.38, 0.52, s)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ── Landing beams ─────────────────────────────────────────────────────────

func _make_beams() -> void:
	_clear_beams()
	for fp in _piece_footprints():
		var color: Color = _type_color(_footprint_bottom_color(fp.x, fp.y))
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = BEAM_RADIUS
		bm.bottom_radius = BEAM_RADIUS
		bm.height = 1.0
		beam.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(color.r, color.g, color.b, 0.25)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		beam.material_override = mat
		beam.set_meta("fx", fp.x)
		beam.set_meta("fz", fp.y)
		add_child(beam)
		beams.append(beam)
	_update_beams()


func _update_beams() -> void:
	for beam in beams:
		var fx: int = beam.get_meta("fx")
		var fz: int = beam.get_meta("fz")
		var wq := _footprint_world(fx, fz)
		var bottom_y := piece_yp + float(_piece_min_layer(fx, fz)) - CUBE_SIZE * 0.5
		var height := maxf(bottom_y, 0.01)
		beam.scale.y = height
		beam.position = Vector3(wq.x, height * 0.5, wq.z)


func _clear_beams() -> void:
	for beam in beams:
		beam.queue_free()
	beams = []


# ── Matching, breaking & gravity ──────────────────────────────────────────
# After each landing, clear every connected group of >= MATCH_MIN same-colour
# cubes (vertical + horizontal face adjacency, never diagonal). Clearing a cube
# that belongs to a rigid multi-cube group breaks that group: its survivors
# become loose single cubes. Then gravity settles loose cubes (intact groups
# stay frozen in place, overhangs and all), and we repeat to handle cascades.

func _resolve_matches() -> void:
	# A match chain plays out over time: blink the doomed cubes, shatter them
	# (with a camera kick), let gravity settle, then look for cascades. Falling is
	# paused for the whole chain via `resolving`, and each successive cascade adds
	# more shake.
	if _find_matches().is_empty():
		return
	resolving = true
	await _run_match_chain()
	resolving = false


func _run_match_chain() -> void:
	# The blink -> shatter -> settle -> cascade loop. Assumes `resolving` is already
	# set by the caller (so it can be chained after an obsidian break).
	var combo := 0
	var doomed := _find_matches()
	while not doomed.is_empty():
		combo += 1
		await _blink(doomed)
		await _explode_wave(doomed, combo)   # shatter + crack neighbours + chain react
		_settle_gravity()
		await get_tree().create_timer(SETTLE_HOLD).timeout
		doomed = _find_matches()
	_check_full_clear()


func _blink(doomed: Array) -> void:
	# Flash the doomed cubes white a few times as a telegraph before they shatter,
	# with a tick on each flash (pitch rising) so the blink is heard as well as seen.
	var mats: Array = []
	for pos in doomed:
		var mat := columns[pos.x][pos.y]["node"].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mats.append(mat)
	for i in BLINK_COUNT:
		var on := i % 2 == 0
		for mat in mats:
			mat.emission_energy_multiplier = 5.0 if on else 0.0
		if on:
			_play("blink", 1.0 + float(i) * 0.05)   # tick on each white flash
		await get_tree().create_timer(BLINK_INTERVAL).timeout


func _explode(doomed: Array, combo: int) -> void:
	# Shatter each doomed cube into a particle burst, remove it, break any rigid
	# group it belonged to, and kick the camera harder the longer the chain runs.
	var broken := {}
	for pos in doomed:
		var entry: Dictionary = columns[pos.x][pos.y]
		if entry["group"] != -1:
			broken[entry["group"]] = true
		var node: MeshInstance3D = entry["node"]
		_spawn_explosion(node.global_position, _type_color(entry["color"]))
		node.queue_free()
		columns[pos.x].erase(pos.y)

	# A group with any member cleared is broken: its survivors become loose.
	if not broken.is_empty():
		for ci in columns.size():
			for h in columns[ci].keys():
				if broken.has(columns[ci][h]["group"]):
					columns[ci][h]["group"] = -1

	var add := SHAKE_PER_BLOCK * float(doomed.size()) + SHAKE_PER_COMBO * float(combo - 1)
	shake_strength = minf(shake_strength + add, SHAKE_MAX)
	_play("explode", minf(1.0 + float(combo - 1) * 0.12, 1.9))
	# Base points per block, multiplied by the combo step (cascades score bigger).
	_add_score(doomed.size() * POINTS_PER_BLOCK * combo)


func _explode_wave(initial: Array, combo: int) -> void:
	# Shatter `initial`, then crack the survivors touching them; any block driven to
	# its impact threshold detonates in the next pass, cracking ITS neighbours — a
	# chain reaction that plays out until it dies down.
	var wave := initial
	while not wave.is_empty():
		_explode(wave, combo)
		await get_tree().create_timer(EXPLODE_HOLD).timeout
		var nxt := _apply_cracks(wave)
		if not nxt.is_empty():
			_play("blink", 1.3)   # tick as the fresh cracks reach their breaking point
			await get_tree().create_timer(CRACK_HOLD).timeout
		wave = nxt


func _apply_cracks(exploded: Array) -> Array:
	# Every block that just exploded cracks each surviving face-neighbour by one
	# impact. Returns the blocks that have now taken enough impacts to shatter.
	var impacts := {}
	for pos in exploded:
		for nb in _neighbors(pos):
			if _occupied(nb.x, nb.y):
				impacts[nb] = int(impacts.get(nb, 0)) + 1
	var shattered: Array = []
	for nb in impacts.keys():
		var broke := false
		for _k in impacts[nb]:
			if _crack_block(nb.x, nb.y):
				broke = true
				break   # already at the threshold; further impacts are moot
		if broke:
			shattered.append(nb)
	return shattered


func _crack_block(ci: int, h: int) -> bool:
	# Register one impact on a block, deepening its visible cracks. Returns true once
	# it has taken CRACK_IMPACTS hits and should shatter. Obsidian never cracks.
	var entry: Dictionary = columns[ci][h]
	if int(entry["color"]) == OBSIDIAN:
		return false
	var lvl: int = int(entry.get("cracks", 0)) + 1
	entry["cracks"] = lvl
	if lvl >= CRACK_IMPACTS:
		return true
	var mat := entry["node"].material_override as StandardMaterial3D
	if mat != null:
		var pool: Array = crack_mats[lvl - 1]
		mat.next_pass = pool[randi() % pool.size()]
	return false


func _spawn_explosion(pos: Vector3, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.6
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.5
	p.gravity = Vector3(0.0, -14.0, 0.0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.30
	var shard := BoxMesh.new()
	shard.size = Vector3(0.22, 0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	shard.material = mat
	p.mesh = shard
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


# ── Cracks ────────────────────────────────────────────────────────────────
# Crack visuals are dark, jagged line patterns baked into small textures and
# laid over a block as a transparent overlay (its material's next_pass). Level 1
# is a light fracture; level 2 is a heavier shatter. A few variants per level are
# generated up front and reused so cracked blocks don't all look identical.

func _setup_cracks() -> void:
	crack_mats = [[], []]
	for level in [1, 2]:
		for _v in CRACK_VARIANTS:
			crack_mats[level - 1].append(_make_crack_material(_make_crack_texture(level)))


func _make_crack_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return m


func _make_crack_texture(level: int) -> ImageTexture:
	# Dark cracks radiating from an off-centre impact point, jittering as they run.
	# Level 2 has more/longer branches, thicker lines, and the odd side-splinter.
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	# Level 2 also darkens the whole block (a bruised tint) so heavier damage reads
	# clearly even when a cube is small on screen; level 1 is cracks alone.
	img.fill(Color(0.0, 0.0, 0.0, 0.0) if level == 1 else Color(0.0, 0.0, 0.0, 0.32))
	var col := Color(0.02, 0.02, 0.03, 1.0)
	var branches := (4 if level == 1 else 6)
	var segs := (5 if level == 1 else 8)
	var thick := (2 if level == 1 else 4)
	var ox := randf_range(0.4, 0.6) * float(s)
	var oy := randf_range(0.4, 0.6) * float(s)
	for b in branches:
		var ang := TAU * float(b) / float(branches) + randf_range(-0.4, 0.4)
		var x := ox
		var y := oy
		for _seg in segs:
			var seglen := randf_range(9.0, 19.0)
			var nx := x + cos(ang) * seglen
			var ny := y + sin(ang) * seglen
			_plot_line(img, int(x), int(y), int(nx), int(ny), col, thick)
			x = nx
			y = ny
			ang += randf_range(-0.5, 0.5)
			if level == 2 and randf() < 0.35:
				var ba := ang + randf_range(-1.3, 1.3)
				var bl := randf_range(5.0, 11.0)
				_plot_line(img, int(x), int(y), int(x + cos(ba) * bl), int(y + sin(ba) * bl), col, 1)
	return ImageTexture.create_from_image(img)


func _plot_line(img: Image, x0: int, y0: int, x1: int, y1: int, col: Color, r: int) -> void:
	# Bresenham line with a square brush of radius r.
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		_plot_dot(img, x0, y0, col, r)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


func _plot_dot(img: Image, cx: int, cy: int, col: Color, r: int) -> void:
	var w := img.get_width()
	var hgt := img.get_height()
	for ix in range(cx - r + 1, cx + r):
		for iy in range(cy - r + 1, cy + r):
			if ix >= 0 and iy >= 0 and ix < w and iy < hgt:
				img.set_pixel(ix, iy, col)


func _find_matches() -> Array:
	# Flood-fill same-colour connected components; return every cell (as
	# Vector2i(column, height)) in a component of size >= MATCH_MIN.
	var doomed: Array = []
	var visited := {}
	for ci in columns.size():
		for h in columns[ci].keys():
			var start := Vector2i(ci, h)
			if visited.has(start):
				continue
			var color: int = columns[ci][h]["color"]
			var comp: Array = []
			var frontier: Array = [start]
			visited[start] = true
			while not frontier.is_empty():
				var cur: Vector2i = frontier.pop_back()
				comp.append(cur)
				for nb in _neighbors(cur):
					if visited.has(nb):
						continue
					if _occupied(nb.x, nb.y) and columns[nb.x][nb.y]["color"] == color:
						visited[nb] = true
						frontier.append(nb)
			if comp.size() >= MATCH_MIN:
				doomed.append_array(comp)
	return doomed


func _neighbors(cur: Vector2i) -> Array:
	# Orthogonal neighbours only: up/down within the column, plus the same height
	# in each edge-adjacent column. No diagonals.
	var out: Array = [Vector2i(cur.x, cur.y - 1), Vector2i(cur.x, cur.y + 1)]
	for k in ADJ[cur.x]:
		out.append(Vector2i(k, cur.y))
	return out


func _settle_gravity() -> void:
	# Per column, drop loose (group == -1) cubes down to fill gaps. Cubes still in
	# an intact rigid group are frozen anchors: they keep their height (overhangs
	# included) and loose cubes rest on top of them.
	for ci in columns.size():
		var col: Dictionary = columns[ci]
		if col.is_empty():
			continue
		var heights := col.keys()
		heights.sort()
		var settled := {}
		var next_free := 0
		for h in heights:
			var entry: Dictionary = col[h]
			var new_h: int
			if entry["group"] != -1:
				new_h = h                 # frozen anchor stays put
				next_free = h + 1
			else:
				new_h = next_free         # loose cube falls to the next open slot
				next_free += 1
			settled[new_h] = entry
			if new_h != h:
				# Animate the fall into the gap rather than teleporting down.
				_drop_cube(entry["node"], new_h, h - new_h)
		columns[ci] = settled


func _drop_cube(cube: MeshInstance3D, new_h: int, drop: int) -> void:
	# Tween a settling block down to its new slot (accelerating like a fall), then
	# bounce on landing — a block that dropped further lands harder.
	var target_y := 0.5 + float(new_h) * CELL
	var dur := clampf(0.10 + float(drop) * 0.05, 0.10, 0.28)
	var tween := create_tween()
	tween.tween_property(cube, "position:y", target_y, dur) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_bounce_cube.bind(cube, FALL_SPEED + float(drop) * 4.0))


# ── Camera framing ────────────────────────────────────────────────────────
# The camera orbits a vertical focus line at a fixed heading. To frame taller
# play, it dollies back (zoom out) up to CAM_MAX_D; once maxed, it pans its
# focus upward instead, keeping the spawn/top of the tower in view.

func _world_half_height_per_distance() -> float:
	# How much world-height (half of it) each unit of dolly distance buys us,
	# given the current FOV and viewing angle. Derived from how much of world-up
	# lands perpendicular to the view direction.
	var view_dir := -cam_dir
	var perp_len := (Vector3.UP - Vector3.UP.dot(view_dir) * view_dir).length()
	return tan(deg_to_rad(camera.fov) * 0.5) / (perp_len * CAM_FIT_MARGIN)


func _camera_target() -> Vector2:
	# Returns (distance, focus_y) needed to keep floor..top framed, or, once
	# zoomed out to the limit, to keep the top edge pinned at `top`.
	var top := _spawn_height() + CAM_TOP_MARGIN
	var half_fit := cam_half_fit
	var d_fit := (top * 0.5) / half_fit
	var out: Vector2
	if d_fit > CAM_MAX_D:
		# Maxed out: pan up so the spawn area stays visible; floor scrolls off.
		out = Vector2(CAM_MAX_D, top - CAM_MAX_D * half_fit)
	elif d_fit < CAM_MIN_D:
		# Very short tower: hold the closest distance, floor anchored at bottom.
		out = Vector2(CAM_MIN_D, CAM_MIN_D * half_fit)
	else:
		# Comfortable range: frame exactly floor..top.
		out = Vector2(d_fit, top * 0.5)
	return out


func _apply_camera() -> void:
	var focus := Vector3(0.0, cam_focus_y + cam_scroll, 0.0)
	var pos := focus + cam_dir * cam_distance
	if shake_strength > 0.0:
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength
	camera.position = pos
	camera.look_at(focus - Vector3(0.0, _tilt_drop(), 0.0), Vector3.UP)


func _tilt_drop() -> float:
	# Base tilt at the top framing, easing to zero over the first CAM_TILT_FADE of
	# downward pan; plus an extra tilt as you scroll up toward the very top of the range.
	var base := clampf(cam_scroll / CAM_TILT_FADE + 1.0, 0.0, 1.0)   # 1 at/above 0, 0 fully panned down
	var extra := clampf(cam_scroll / CAM_SCROLL_UP, 0.0, 1.0)        # 0 at the default, 1 at the very top
	return CAM_TILT_DROP * base + CAM_TILT_TOP_EXTRA * extra


func _update_camera(delta: float) -> void:
	# The framing target steps up a whole cube at a time as the tower grows. A plain
	# lerp reacts to each step with a velocity spike (a visible jerk); a critically
	# damped smooth-damp ramps velocity in and out, so the stepped target reads as one
	# continuous glide with no overshoot.
	var target := _camera_target()
	var d := _smooth_damp(cam_distance, target.x, cam_dist_vel, CAM_SMOOTH_TIME, delta)
	cam_distance = d.x
	cam_dist_vel = d.y
	var f := _smooth_damp(cam_focus_y, target.y, cam_focus_vel, CAM_SMOOTH_TIME, delta)
	cam_focus_y = f.x
	cam_focus_vel = f.y
	# Manual scroll pan: clamp so the view stays between the tower's base and a little
	# above the auto-framing, then ease toward it (this also drives the drop auto-return).
	cam_scroll_target = clampf(cam_scroll_target, minf(CAM_SCROLL_FLOOR - cam_focus_y, 0.0), CAM_SCROLL_UP)
	var sc := _smooth_damp(cam_scroll, cam_scroll_target, cam_scroll_vel, CAM_SCROLL_SMOOTH, delta)
	cam_scroll = sc.x
	cam_scroll_vel = sc.y
	shake_strength = maxf(shake_strength - SHAKE_DECAY * delta, 0.0)
	_apply_camera()


func _smooth_damp(current: float, target: float, vel: float, smooth_time: float, delta: float) -> Vector2:
	# Critically damped spring toward `target` (Game Programming Gems 4, 1.10).
	# Returns the new value in .x and the carried-over velocity in .y.
	var omega := 2.0 / maxf(smooth_time, 0.0001)
	var x := omega * delta
	var ex := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (vel + omega * change) * delta
	var new_vel := (vel - omega * temp) * ex
	var new_val := target + (change + temp) * ex
	return Vector2(new_val, new_vel)


func _update_intro_camera(delta: float) -> void:
	# Spiral the camera from a low, close start up and out into the normal framing.
	# The settled pose (where regular play begins) is derived from the live framing
	# target, so the helix lands exactly on it — a seamless hand-off to _update_camera.
	intro_elapsed += delta
	var t := smoothstep(0.0, 1.0, clampf(intro_elapsed / INTRO_CAM_TIME, 0.0, 1.0))
	# Smooth-damp the framing target (same as normal play) so the helix's settle point
	# glides as the opening blocks grow the tower instead of snapping with each landing.
	# The carried velocity also makes the hand-off to _update_camera seamless.
	var target := _camera_target()
	var d := _smooth_damp(cam_distance, target.x, cam_dist_vel, CAM_SMOOTH_TIME, delta)
	cam_distance = d.x
	cam_dist_vel = d.y
	var f := _smooth_damp(cam_focus_y, target.y, cam_focus_vel, CAM_SMOOTH_TIME, delta)
	cam_focus_y = f.x
	cam_focus_vel = f.y
	var settled_focus := Vector3(0.0, cam_focus_y, 0.0)
	var settled_pos := settled_focus + cam_dir * cam_distance
	# Settled pose expressed in cylindrical terms around the grid's vertical axis.
	var az_end := atan2(settled_pos.z, settled_pos.x)
	var r_end := Vector2(settled_pos.x, settled_pos.z).length()
	var az := lerpf(az_end - INTRO_CAM_SWEEP, az_end, t)
	var r := lerpf(INTRO_CAM_START_R, r_end, t)
	var y := lerpf(INTRO_CAM_START_Y, settled_pos.y, t)
	# Land on the same downward-tilted look the play camera uses at the top (cam_scroll
	# is 0 through the intro, so that's a full CAM_TILT_DROP) — a seamless hand-off.
	var settled_look := settled_focus - Vector3(0.0, CAM_TILT_DROP, 0.0)
	var focus := Vector3(0.0, INTRO_CAM_START_FOCUS, 0.0).lerp(settled_look, t)
	camera.position = Vector3(cos(az) * r, y, sin(az) * r)
	camera.look_at(focus, Vector3.UP)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	score_label.add_theme_constant_override("outline_size", 6)
	score_label.position = Vector2(24.0, 16.0)
	layer.add_child(score_label)
	_update_score_label()

	# Controls hint, pinned to the top-right (stays there as the canvas resizes).
	var controls := Label.new()
	controls.text = "CONTROLS\nQ / E  —  Spin grid\nR / F  —  Rotate CW / CCW\nSpace  —  Drop"
	controls.add_theme_font_size_override("font_size", 22)
	controls.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	controls.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	controls.add_theme_constant_override("outline_size", 6)
	controls.add_theme_constant_override("line_spacing", 4)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls.offset_left = -24.0
	controls.offset_right = -24.0
	controls.offset_top = 16.0
	controls.offset_bottom = 16.0
	layer.add_child(controls)

	_setup_pip(layer)


func _setup_pip(layer: CanvasLayer) -> void:
	# A small picture-in-picture 3D preview of the next piece (top-left, under the
	# score). It renders in its own world with the exact in-game cube materials.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.45)
	bg.position = Vector2(16.0, 68.0)
	bg.size = Vector2(206.0, 196.0)
	layer.add_child(bg)

	var next_label := Label.new()
	next_label.text = "NEXT"
	next_label.add_theme_font_size_override("font_size", 20)
	next_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	next_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	next_label.add_theme_constant_override("outline_size", 6)
	next_label.position = Vector2(24.0, 72.0)
	layer.add_child(next_label)

	var container := SubViewportContainer.new()
	container.stretch = false
	container.position = Vector2(24.0, 104.0)
	layer.add_child(container)

	pip_viewport = SubViewport.new()
	pip_viewport.size = Vector2i(190, 150)
	pip_viewport.transparent_bg = true
	pip_viewport.own_world_3d = true
	pip_viewport.msaa_3d = Viewport.MSAA_4X
	# The preview is static between pieces, so render on demand (in _update_pip) rather
	# than every frame — this SubViewport was a full extra scene render each frame.
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(pip_viewport)

	# One key light from the camera side lights every visible face — no ambient
	# needed, which keeps the viewport background transparent.
	var light := DirectionalLight3D.new()
	light.light_energy = 1.6
	pip_viewport.add_child(light)
	light.look_at_from_position(Vector3(4.0, 8.0, 5.0), Vector3.ZERO, Vector3.UP)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.2
	cam.position = Vector3(6.0, 6.0, 6.0)
	cam.current = true
	pip_viewport.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	pip_holder = Node3D.new()
	pip_viewport.add_child(pip_holder)


func _update_pip() -> void:
	if pip_holder == null or next_piece.is_empty():
		return
	for child in pip_holder.get_children():
		child.queue_free()
	var shape: Array = next_piece["shape"]
	var types: Array = next_piece["types"]
	# Centre the piece on the origin so the fixed camera frames it consistently.
	var centroid := Vector3.ZERO
	var pts: Array = []
	for off in shape:
		var p := Vector3(0.5 - float(off[0]), float(off[2]), 0.5 - float(off[1]))
		pts.append(p)
		centroid += p
	centroid /= float(shape.size())
	for i in shape.size():
		var cube := _make_cube(types[i])
		cube.position = pts[i] - centroid
		pip_holder.add_child(cube)
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE   # redraw the new piece


func _update_score_label() -> void:
	if score_label != null:
		score_label.text = "Score: %d" % score


func _add_score(amount: int) -> void:
	score += amount
	_update_score_label()


func _setup_sfx() -> void:
	for snd in SFX_VOL.keys():
		var p := AudioStreamPlayer.new()
		p.stream = load("res://sfx/%s.wav" % snd)
		p.volume_db = SFX_VOL[snd]
		add_child(p)
		sfx[snd] = p


func _setup_music() -> void:
	# Quiet looping background track (the .ogg is imported with loop=true).
	var player := AudioStreamPlayer.new()
	player.stream = load("res://music/forgotten_biomes.ogg")
	player.volume_db = MUSIC_VOL
	add_child(player)
	player.play()


func _play(sound: String, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = sfx.get(sound)
	if p != null:
		# Random jitter layered on top of the caller's pitch (e.g. the combo ramp).
		p.pitch_scale = pitch * randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
		p.play()


func _handle_spin_input() -> void:
	if spinning:
		return
	var dir := 0
	if Input.is_action_just_pressed("spin_left"):
		dir += 1
	if Input.is_action_just_pressed("spin_right"):
		dir -= 1
	if dir != 0:
		_spin(dir)


func _handle_rotate_input() -> void:
	if Input.is_action_just_pressed("rotate_piece"):
		_rotate_piece(true)    # R = clockwise
	elif Input.is_action_just_pressed("rotate_ccw"):
		_rotate_piece(false)   # F = counter-clockwise


func _cw_cell(cell: Vector2i, pivot: Vector2) -> Vector2i:
	# 90-degree CLOCKWISE rotation of a grid cell around a pivot (which may be a
	# 0.5 half-cell for the 2x2 centre). Rounds back to an integer grid cell.
	var dx := float(cell.x) - pivot.x
	var dz := float(cell.y) - pivot.y
	return Vector2i(int(round(pivot.x - dz)), int(round(pivot.y + dx)))


func _ccw_cell(cell: Vector2i, pivot: Vector2) -> Vector2i:
	# 90-degree COUNTER-CLOCKWISE rotation of a grid cell (inverse of _cw_cell).
	var dx := float(cell.x) - pivot.x
	var dz := float(cell.y) - pivot.y
	return Vector2i(int(round(pivot.x + dz)), int(round(pivot.y - dx)))


func _rotate_piece(cw: bool) -> void:
	# Rotate the hovering piece 90 degrees about the vertical axis — R = clockwise,
	# F = counter-clockwise — keeping it inside the 2x2 grid. Pivot around the
	# bottom-centre slot; if that would push a cube out, fall back to the slot it
	# turns toward (rightmost for CW / leftmost for CCW), then the centre. A
	# single-column piece keeps its cells, so it simply spins in place. New
	# footprints apply at once (landing stays correct) while cubes AND beams
	# animate to their new spots.
	if piece_root == null or resolving or hard_dropping or rotating:
		return
	var pivots: Array = ROT_PIVOTS_CW if cw else ROT_PIVOTS_CCW
	var fmap := {}          # old footprint Vector2i -> new footprint Vector2i
	var found := false
	for pivot in pivots:
		fmap.clear()
		var ok := true
		for c in piece_cubes:
			var of := Vector2i(int(c["fx"]), int(c["fz"]))
			if fmap.has(of):
				continue
			var nf: Vector2i = _cw_cell(of, pivot) if cw else _ccw_cell(of, pivot)
			if nf.x < 0 or nf.x > 1 or nf.y < 0 or nf.y > 1:
				ok = false
				break
			fmap[of] = nf
		if ok:
			found = true
			break
	if not found:
		return   # unreachable: the centre pivot always keeps a piece in grid

	rotating = true
	_play("rotate")
	var spin := (-PI * 0.5) if cw else (PI * 0.5)
	var tween := create_tween().set_parallel(true)
	for c in piece_cubes:
		var nf: Vector2i = fmap[Vector2i(int(c["fx"]), int(c["fz"]))]
		c["fx"] = nf.x
		c["fz"] = nf.y
		var wq := _footprint_world(nf.x, nf.y)
		var cube: MeshInstance3D = c["node"]
		tween.tween_property(cube, "position", Vector3(wq.x, float(c["layer"]) * CELL, wq.z), ROTATE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(cube, "rotation:y", cube.rotation.y + spin, ROTATE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Beams slide with the rotation (their heights are unchanged — rotation keeps
	# each column's layers).
	for beam in beams:
		var of := Vector2i(int(beam.get_meta("fx")), int(beam.get_meta("fz")))
		if not fmap.has(of):
			continue
		var nf: Vector2i = fmap[of]
		beam.set_meta("fx", nf.x)
		beam.set_meta("fz", nf.y)
		var wq := _footprint_world(nf.x, nf.y)
		tween.tween_property(beam, "position", Vector3(wq.x, beam.position.y, wq.z), ROTATE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		rotating = false
	)


func _spin(dir: int) -> void:
	spinning = true
	_play("spin_left" if dir > 0 else "spin_right")   # dir +1 = Q (left), -1 = E (right)
	var quarter := PI / 2.0
	var target := grid_pivot.rotation.y + dir * quarter
	var tween := create_tween()
	tween.tween_property(grid_pivot, "rotation:y", target, SPIN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void:
		# Snap to an exact quarter turn to keep cells axis-aligned over time.
		grid_pivot.rotation.y = round(grid_pivot.rotation.y / quarter) * quarter
		spinning = false
	)
