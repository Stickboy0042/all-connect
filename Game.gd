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
const SPAWN_DELAY := 0.25    # pause between a lock and the next spawn
const BEAM_RADIUS := 0.1     # radius of the glowing landing beam
const SPAWN_MIN := 16.0      # spawn height over an empty board
const SPAWN_GAP := 9.0       # blocks always appear this far above the tallest tower
const MATCH_MIN := 3         # a connected same-colour group of this many clears
const MULTI_CHANCE := 0.25   # chance a spawned piece is a rigid multi-cube shape
const OBSIDIAN_CHANCE := 0.07 # chance a spawned piece is a single weighted obsidian block
const OBSIDIAN := 3          # 4th block type index (past the 3 colours): weighted obsidian
const OBSIDIAN_MIN_BLOCKS := 15 # obsidian can't spawn until this many blocks have landed

# ── Scoring ───────────────────────────────────────────────────────────────
const POINTS_PER_BLOCK := 10 # score per cleared block, multiplied by the combo step
const OBSIDIAN_POINTS := 50  # awarded when an obsidian block reaches the floor

# ── Match FX / feel ───────────────────────────────────────────────────────
const BLINK_COUNT := 6        # white emission on/off flashes before a group explodes
const BLINK_INTERVAL := 0.07  # seconds per blink flash
const EXPLODE_HOLD := 0.12    # pause after the burst before gravity settles
const SETTLE_HOLD := 0.08     # pause after gravity before checking for cascades
const SHAKE_MAX := 0.7        # cap on camera-shake offset (world units) — "within reason"
const SHAKE_PER_BLOCK := 0.045 # shake added per exploded block
const SHAKE_PER_COMBO := 0.14 # extra shake per cascade step in a chain
const SHAKE_DECAY := 1.8      # shake falloff (units / second)

# ── Audio ─────────────────────────────────────────────────────────────────
const PITCH_JITTER := 0.08    # +/- random pitch on every SFX so repeats don't sound stale
const SFX_VOL := {            # per-sound playback volume in dB
	"hard_drop": -6.0,
	"land_soft": -10.0,
	"land_hard": -4.0,
	"blink": -13.0,
	"explode": -3.0,
	"obsidian": -3.0,
	"spin_left": -9.0,
	"spin_right": -9.0,
}

# ── Camera tunables ───────────────────────────────────────────────────────
const CAM_DIR := Vector3(1.0, 0.3846, 1.0) # heading from focus point to camera (normalized in _ready)
const CAM_MIN_D := 8.0        # closest the camera ever sits (short towers)
const CAM_MAX_D := 18.0       # furthest the camera zooms out before it starts panning up
const CAM_TOP_MARGIN := 1.5   # headroom kept above the spawn point
const CAM_FIT_MARGIN := 1.5   # >1 pads the framed span (higher = more zoomed out)
const CAM_SMOOTH := 5.0       # follow responsiveness (higher = snappier)

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
var pip_viewport: SubViewport = null
var pip_holder: Node3D = null      # holds the preview cubes inside the PIP viewport

var spinning := false
var hard_dropping := false      # true while the active piece is doing a space-bar slam
var resolving := false          # true while a match chain blinks/explodes (pauses falling)
var spawn_timer := 0.0

var cam_dir := Vector3.ONE      # normalized focus->camera heading
var cam_distance := 0.0         # current (smoothed) dolly distance
var cam_focus_y := 0.0          # current (smoothed) look-at height
var shake_strength := 0.0       # current camera-shake magnitude (decays each frame)


func _ready() -> void:
	cam_dir = CAM_DIR.normalized()
	camera.fov = 62.0
	camera.current = true
	_setup_light()
	_setup_environment()
	_build_grid()
	# Snap the camera straight to its framing target so the first frame is right.
	var target := _camera_target()
	cam_distance = target.x
	cam_focus_y = target.y
	_apply_camera()
	_setup_sfx()
	_setup_ui()
	_spawn_piece()


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
	var mesh := BoxMesh.new()
	mesh.size = Vector3(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	cube.mesh = mesh
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
		var tps: Array = []
		for _i in shp.size():
			tps.append(randi() % COLORS.size())   # multi-cube pieces mix colours
		return {"shape": shp, "types": tps, "obsidian": false}
	return {"shape": [[0, 0, 0]], "types": [randi() % COLORS.size()], "obsidian": false}


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
	_make_beams()

	# Roll the following piece and refresh its preview.
	next_piece = _roll_piece()
	_update_pip()


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

func _process(delta: float) -> void:
	_handle_spin_input()
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
		if Input.is_action_just_pressed("hard_drop"):
			hard_dropping = true
			_play("hard_drop")
		else:
			_update_beams()
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
	var weight_cols := {}   # columns that received a weighted obsidian block
	var is_obsidian := false
	var obsidian_ci := -1
	var obsidian_h := -1
	var obsidian_node: MeshInstance3D = null
	for c in piece_cubes:
		var ci := _column_under(_footprint_world(c["fx"], c["fz"]))
		var h: int = base + c["layer"]
		var cube: MeshInstance3D = c["node"]
		# Re-home each cube into its cell so it now rotates with the grid.
		cube.reparent(cells[ci], false)
		cube.position = Vector3(0.0, 0.5 + float(h) * CELL, 0.0)
		cube.rotation = Vector3.ZERO
		columns[ci][h] = {"node": cube, "color": c["color"], "group": piece_group}
		_bounce_cube(cube, landing_speed)
		if c["color"] == OBSIDIAN:
			weight_cols[ci] = true
			is_obsidian = true
			obsidian_ci = ci
			obsidian_h = h
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

	# Weighted obsidian squeezes the gaps out of the column(s) it lands in.
	var weighted := false
	for wci in weight_cols.keys():
		if _apply_weight(wci):
			weighted = true
	if weighted:
		_settle_gravity()   # drop any blocks loosened when a rigid group was broken

	# An obsidian block that reached the ground floor pays out and pops.
	if obsidian_node != null and obsidian_h == 0:
		columns[obsidian_ci].erase(0)
		_spawn_explosion(obsidian_node.global_position, _type_color(OBSIDIAN))
		obsidian_node.queue_free()
		_play("explode")
		_add_score(OBSIDIAN_POINTS)

	spawn_timer = SPAWN_DELAY
	_resolve_matches()


func _apply_weight(ci: int) -> bool:
	# A weighted (obsidian) block forces its whole column to settle, squeezing out
	# any gaps and overriding rigidity. Any block pulled down breaks out of its
	# rigid group. Returns true if anything moved.
	var col: Dictionary = columns[ci]
	var heights := col.keys()
	heights.sort()
	var has_gap := false
	for idx in heights.size():
		if heights[idx] != idx:
			has_gap = true
			break
	if not has_gap:
		return false
	var moved_groups := {}
	var compact := {}
	var target := 0
	for h in heights:
		var entry: Dictionary = col[h]
		if target != h:
			entry["node"].position = Vector3(0.0, 0.5 + float(target) * CELL, 0.0)
			_bounce_cube(entry["node"], FALL_SPEED + float(h - target) * 4.0)
			if entry["group"] != -1:
				moved_groups[entry["group"]] = true
		compact[target] = entry
		target += 1
	columns[ci] = compact
	if not moved_groups.is_empty():
		for c2 in columns.size():
			for hh in columns[c2].keys():
				if moved_groups.has(columns[c2][hh]["group"]):
					columns[c2][hh]["group"] = -1
	return true


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
	var doomed := _find_matches()
	if doomed.is_empty():
		return
	resolving = true
	var combo := 0
	while not doomed.is_empty():
		combo += 1
		await _blink(doomed)
		_explode(doomed, combo)
		await get_tree().create_timer(EXPLODE_HOLD).timeout
		_settle_gravity()
		await get_tree().create_timer(SETTLE_HOLD).timeout
		doomed = _find_matches()
	resolving = false


func _blink(doomed: Array) -> void:
	# Flash the doomed cubes white a few times as a telegraph before they shatter.
	_play("blink")
	var mats: Array = []
	for pos in doomed:
		var mat := columns[pos.x][pos.y]["node"].material_override as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mats.append(mat)
	for i in BLINK_COUNT:
		var energy := 5.0 if i % 2 == 0 else 0.0
		for mat in mats:
			mat.emission_energy_multiplier = energy
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
				entry["node"].position = Vector3(0.0, 0.5 + float(new_h) * CELL, 0.0)
				# A block that dropped further lands harder.
				_bounce_cube(entry["node"], FALL_SPEED + float(h - new_h) * 4.0)
		columns[ci] = settled


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
	var half_fit := _world_half_height_per_distance()
	var d_fit := (top * 0.5) / half_fit
	if d_fit > CAM_MAX_D:
		# Maxed out: pan up so the spawn area stays visible; floor scrolls off.
		return Vector2(CAM_MAX_D, top - CAM_MAX_D * half_fit)
	if d_fit < CAM_MIN_D:
		# Very short tower: hold the closest distance, floor anchored at bottom.
		return Vector2(CAM_MIN_D, CAM_MIN_D * half_fit)
	# Comfortable range: frame exactly floor..top.
	return Vector2(d_fit, top * 0.5)


func _apply_camera() -> void:
	var focus := Vector3(0.0, cam_focus_y, 0.0)
	var pos := focus + cam_dir * cam_distance
	if shake_strength > 0.0:
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength
	camera.position = pos
	camera.look_at(focus, Vector3.UP)


func _update_camera(delta: float) -> void:
	var target := _camera_target()
	var k := 1.0 - exp(-CAM_SMOOTH * delta)   # frame-rate independent smoothing
	cam_distance = lerp(cam_distance, target.x, k)
	cam_focus_y = lerp(cam_focus_y, target.y, k)
	shake_strength = maxf(shake_strength - SHAKE_DECAY * delta, 0.0)
	_apply_camera()


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
	controls.text = "CONTROLS\nQ / E  —  Spin grid\nSpace  —  Drop"
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
	pip_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
