class_name ALEManager
extends Node
# ============================================================================
#  GOLEM – ALE Manager (refactored)
#  * constant‑time spatial lookup via `occupancy` dictionary
#  * single‑pass shuffled spawning (no repeated RNG calls)
#  * strict typing to avoid Variant warnings
#  * respawn keeps the lookup tables consistent
#  * ready for SEAL component expansion
# ============================================================================

# ---------------------------------------------------------------------------
# External resources
# ---------------------------------------------------------------------------
const SEALSymbol := preload("res://scripts/seal/seal_symbol.gd")

@export var ale_scene      : PackedScene      # Scene that instantiates an ALE
@export var ale_definition : Resource         # Shared ALE definition (.tres)

# ---------------------------------------------------------------------------
# Cached references (injected from Main)
# ---------------------------------------------------------------------------
var map  : Map
var main : Main

# ---------------------------------------------------------------------------
# World & ALE parameters
# ---------------------------------------------------------------------------
var tile_size       : int
var ale_count       : int
var ale_body_color  : Color
var default_trail_color : Color

# Feature toggles
var enable_visited_cells      := true
var enable_trails             := true
var enable_collision_handling := true

# ---------------------------------------------------------------------------
# Lookup tables
# ---------------------------------------------------------------------------
var ales      : Dictionary = {}  # name → ALE
var occupancy : Dictionary = {}  # Vector2i → ALE  (spatial hash)

# ===========================================================================
#  PUBLIC API
# ===========================================================================
func initialize(
		map_node              : Map,
		ts_init               : int,
		ac_init               : int,
		body_color            : Color,
		trail_color           : Color,
		main_ref              : Main,
		visited_cells_toggle  : bool,
		trails_toggle         : bool,
		collision_toggle      : bool
	) -> void:
	"""
	Called once by Main.  Stores references and spawns all ALEs.
	"""
	# -- Checks ------------------------------------------------------
	if not map_node:
		push_error("ALEManager.initialize(): Map node is null")
		return
	if not ale_scene:
		push_error("ALEManager.initialize(): 'ale_scene' not assigned")
		return
	if not ale_definition:
		push_error("ALEManager.initialize(): 'ale_definition' missing")
		return

	# -- Cache references ---------------------------------------------------
	map                        = map_node
	main                       = main_ref
	tile_size                  = ts_init
	ale_count                  = ac_init
	ale_body_color             = body_color
	default_trail_color        = trail_color

	enable_visited_cells       = visited_cells_toggle
	enable_trails              = trails_toggle
	enable_collision_handling  = collision_toggle

	# -----------------------------------------------------------------------
	spawn_ales()


func get_ale_at(grid_pos: Vector2i) -> ALE:
	"""Constant‑time lookup for an ALE occupying *grid_pos* (or null)."""
	return occupancy.get(grid_pos, null)


# ===========================================================================
#  INTERNAL
# ===========================================================================
func spawn_ales() -> void:
	if map.walkable_positions.is_empty():
		push_error("ALEManager.spawn_ales(): no walkable positions")
		return

	var positions := map.walkable_positions.duplicate()
	positions.shuffle()

	var spawned := 0
	for grid_pos in positions:
		if spawned >= ale_count:
			break

		var world_pos := Grid.grid_to_world(grid_pos.x, grid_pos.y, tile_size) \
					   + Vector2(tile_size * 0.5, tile_size * 0.5)

		var ale : ALE = ale_scene.instantiate()
		ale.name     = "ALE_%d" % spawned
		ale.ale_id   = spawned
		ale.grid_pos = grid_pos
		add_child(ale)

		var seed_symbol := SEALSymbol.create_random(3)  # 3×3 starter symbol

		ale.initialize(
			spawned,
			ale_definition,
			ale_body_color,
			default_trail_color,
			tile_size,
			world_pos,
			map,
			main,
			enable_visited_cells,
			enable_trails,
			enable_collision_handling,
			seed_symbol
		)

		ales[ale.name]      = ale
		occupancy[grid_pos] = ale
		spawned += 1


func respawn_ale(old_ale: ALE) -> void:
	"""
	Removes *old_ale* and spawns a replacement at a new random tile,
	maintaining the same ID and node name.
	"""
	# -- remove from tables -------------------------------------------------
	occupancy.erase(old_ale.grid_pos)
	ales.erase(old_ale.name)

	var id_cache    := old_ale.ale_id
	var name_cache  := old_ale.name
	var body_col    := old_ale.body_color
	var trail_col   := old_ale.trail_color

	old_ale.queue_free()

	if map.walkable_positions.is_empty():
		push_error("ALEManager.respawn_ale(): no walkable positions")
		return

	var positions := map.walkable_positions.duplicate()
	positions.shuffle()
	var spawn_grid_pos : Vector2i = positions[0]

	var world_pos := Grid.grid_to_world(spawn_grid_pos.x, spawn_grid_pos.y, tile_size) \
				   + Vector2(tile_size * 0.5, tile_size * 0.5)

	var ale : ALE = ale_scene.instantiate()
	ale.name     = name_cache
	ale.ale_id   = id_cache
	ale.grid_pos = spawn_grid_pos
	add_child(ale)

	var seed_symbol := SEALSymbol.create_random(3)

	ale.initialize(
		id_cache,
		ale_definition,
		body_col,
		trail_col,
		tile_size,
		world_pos,
		map,
		main,
		enable_visited_cells,
		enable_trails,
		enable_collision_handling,
		seed_symbol
	)

	ales[ale.name]      = ale
	occupancy[spawn_grid_pos] = ale


# ---------------------------------------------------------------------------
# Collision signal hook (placeholder for future use)
# ---------------------------------------------------------------------------
func _on_ale_collision(ale_name: String, collision_position: Vector2) -> void:
	pass   # integrate with StatsPanel / SEAL resonance later
