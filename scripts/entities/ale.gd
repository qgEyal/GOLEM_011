class_name ALE
extends Node2D

const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

@onready var sprite: Sprite2D = $Sprite
@onready var ale_definition: ALEdefinition = preload("res://assets/resources/ale_definition.tres")
#const SEALSymbol = preload("res://scripts/seal/seal_symbol.gd")
@onready var main: Main   # Get reference to Main scene


@onready var map: Map  # Reference to the game map
# **State Machine for ALE Behavior**
enum State {
	MOVING,    # Actively moving on the grid
	STOPPED,   # Paused after a collision
	COLLIDING, # In the process of colliding
	IDLE       # Inactive (not moving or interacting)
}

# **Movement & Grid Variables**
var stop_timer: float = 0.0  # Timer for tracking pause duration (frame-based)
var move_speed: float  # Speed assigned randomly within a user-defined range
var move_timer: float = 1.0  # Timer to control movement intervals
var tile_size: int  # Size of each grid tile
var grid_pos: Vector2i  # ALE's current position on the grid
var prev_grid_pos: Vector2i  # Stores previous grid position before movement

# **State & Collision Handling**
var state: State = State.MOVING  # Initial state is MOVING
var stop_turns: int = 0  # Number of turns ALE remains paused after a collision
var visited_cells: Dictionary = {}  # Dictionary to store previously visited grid positions

# New variable to track when ALE started stopping
var stop_turn_reference: int = -1


# **Appearance & Definition Variables**
var default_color: Color  # Stores the original color of the ALE
var body_color: Color
var trail_color: Color
var pending_definition: Resource  # Stores the ALE's definition in case `_ready()` is called before `initialize()`

# SEAL
@export var seal_symbol: SEALSymbol            # current SEAL token

var enable_visited_cells: bool
var enable_trails: bool
var enable_collision_handling: bool

## Assign ID to ALEs
var ale_id: int = -1  # Assigned during initialization


## Emitted when a collision is detected, passing the name of the colliding entity and its position.
#signal collision_detected(name: String, position: Vector2)
#signal ale_collision_reported(ale1: ALE, ale2: ALE, grid_position: Vector2i)



# ----------------------------------------
# **INITIALIZATION FUNCTIONS**
# ----------------------------------------

func initialize(
		id:int,
		definition:Resource,
		body_color_param:Color,
		trail_color_param:Color,
		size:int,
		start_pos:Vector2,
		map_ref:Map,
		main_ref:Main,
		visited_cells_toggle:bool,
		trails_toggle:bool,
		collision_toggle:bool,
		symbol:SEALSymbol)-> void:

	ale_id = id
	seal_symbol = symbol
	body_color = body_color_param
	trail_color = trail_color_param
#func initialize(definition: Resource, ale_color: Color, ale_trail_color: Color, size: int, start_pos: Vector2, map_ref: Map, main_ref: Main, visited_cells_toggle: bool, trails_toggle: bool, collision_toggle: bool):
	"""
	Initializes ALE and assigns a reference to `Main`.
	"""

	#print("STEP1")
	tile_size = size
	map = map_ref  # Store map reference
	main = main_ref  # Store main reference **before _ready() runs**

	enable_visited_cells = visited_cells_toggle
	enable_trails = trails_toggle
	enable_collision_handling = collision_toggle



	if not main:
		push_error("ERROR: ALE - Main reference is NULL at initialization!")

	grid_pos = Grid.world_to_grid(int(start_pos.x), int(start_pos.y), tile_size)
	if not map.is_in_bounds(grid_pos):
		get_parent().respawn_ale(self)
		return


	position = Vector2(Grid.grid_to_world(grid_pos.x, grid_pos.y, tile_size)) + Vector2(tile_size / 2.0, tile_size / 2.0)

	pending_definition = definition  # Store the definition
	self.trail_color = trail_color  # Assign trail color from Main
	if sprite:
		## removed the trail_color. Seems to work for now
		#apply_definition(ale_color, trail_color)
		if seal_symbol == null:
			push_error("SEAL symbol missing during ALE init!")
		apply_definition()

func _ready():
	"""
	Called when the ALE node is added to the scene.
	Ensures that the ALE's properties are applied correctly and sets the processing mode.
	"""

	#print("STEP2")
	#if pending_definition:
		#apply_definition()

	prev_grid_pos = grid_pos  # Ensure a valid previous position

	# **Wait until `main` is assigned**
	while not main:
		await get_tree().process_frame  # Wait one frame before checking again

	if not main:
		push_error("Main node not found! Check scene hierarchy.")
	else:
		#print("Main reference successfully assigned to ALE.")
		pass


	# Ensure the ALE stops processing when the simulation ends
	set_process_mode(PROCESS_MODE_PAUSABLE)  # Allows pausing but still updates when the simulation is active




#func apply_definition(ale_color: Color, trail_color: Color):
'''
func apply_definition(ale_color: Color):
	"""
	Applies ALE properties, including sprite color, speed, and trail color.
	"""
	#print("STEP3")

	if not sprite:
		push_error("Sprite2D node not found in ALE.tscn!")
		return

	move_speed = randf_range(main.min_speed, main.max_speed)  # Assign random speed
	sprite.modulate = ale_color  # Apply ALE body color

	# **Ensure trail_color is correctly assigned**
	#self.trail_color = trail_color

	#print("trail color ", trail_color)
	sprite.modulate.a = 1.0  # Force full opacity
	default_color = sprite.modulate  # Store original color

	# **Correct Sprite Scaling**
	var texture_size = sprite.texture.get_size()
	if texture_size.x > 0 and texture_size.y > 0:
		sprite.scale = Vector2(tile_size / texture_size.x, tile_size / texture_size.y)
	else:
		push_error("Invalid texture size for ALE sprite!")

	#print("ALE sprite name:", sprite.name)  # Debugging output
'''
func apply_definition() -> void:
	if not sprite:
		push_error("Sprite2D node not found in ALE.tscn!")
		return

	# --   Colour ------------------------------------------------------------
	if body_color == Color():            #  failsafe: never allow null/0 colour
		body_color = main.ale_color
	sprite.modulate = body_color
	sprite.modulate.a = 1.0
	default_color   = sprite.modulate

	# --   Speed -------------------------------------------------------------
	move_speed = randf_range(main.min_speed, main.max_speed)

	# --   Scaling -----------------------------------------------------------
	var tex_size : Vector2 = sprite.texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		sprite.scale = Vector2(tile_size / tex_size.x, tile_size / tex_size.y)
	else:
		push_error("Invalid texture size for ALE sprite!")




# ----------------------------------------
# **MOVEMENT & PROCESSING**
# ----------------------------------------

func _process(delta):
	"""
	Handles frame-based movement, stopping logic, and collision recovery.
	"""
	if not main or not main.simulation_active:
		return  # Stop processing when the simulation is inactive

	# **Handle Stopping (Collision or Other Events)**
	if stop_turns > 0:
		stop_timer -= delta * main.simulation_speed  # Reduce pause time relative to simulation speed
		if stop_timer <= 0:
			stop_turns = 0  # Reset stop turns
			sprite.modulate = default_color  # Restore original color
			state = State.MOVING  # Resume movement
		return  # Skip movement while stopped

	# **Ensure ALE Stops Moving When Max Turns Are Reached**
	if main.max_turns > 0 and main.current_turn >= main.max_turns:
		return  # Stop movement when max turns are reached

	# **Move ALE Based on Frame Time & Random Speed**
	move_timer -= delta * move_speed * main.simulation_speed  # Adjusted for frame-based movement
	if move_timer <= 0:
		move_randomly()
		move_timer = 1.0  # Reset move timer


func move_randomly():
	"""
	Attempts to move the ALE in a random direction.
	"""
	if state == State.STOPPED:
		return  # Skip movement if currently paused

	#var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	#directions.shuffle()
	var directions := DIRECTIONS.duplicate() # cheap – 4 items
	directions.shuffle() # keeps original constant untouched

	for direction in directions:
		var new_pos = grid_pos + direction

		# **Collision Handling (If Enabled)**
		if enable_collision_handling and check_collision(new_pos):
			handle_collision(new_pos)
			return  # Stop movement if collision occurss


		if map.is_in_bounds(new_pos) and map.is_tile_walkable(new_pos):
			var last_pos = grid_pos  # Store the last valid position before moving

			# **Move the ALE**
			grid_pos = new_pos
			position = Vector2(Grid.grid_to_world(grid_pos.x, grid_pos.y, tile_size)) + Vector2(tile_size / 2.0, tile_size / 2.0)

			# **Visited Cells Tracking (If Enabled)**
			if enable_visited_cells:
				visited_cells[grid_pos] = true

			# **Leave a Trail (If Enabled)**
			if enable_trails:
				leave_trail(last_pos)

			return

	# If no movement is possible, the ALE stops
	state = State.STOPPED
	stop_turns = main.stop_turns


# ----------------------------------------
# **COLLISION HANDLING**
# ----------------------------------------
'''
func check_collision(new_pos: Vector2i) -> bool:
	"""
	Checks if another ALE occupies the given grid position.
	Returns `true` if a collision is detected.
	"""
	for child in get_parent().get_children():
		if child is ALE and child != self and child.grid_pos == new_pos:
			return true
	return false
'''

func check_collision(new_pos: Vector2i) -> ALE:
	for child in get_parent().get_children():
		if child is ALE and child != self and child.grid_pos == new_pos:
			return child
	return null



func handle_collision(_collision_pos: Vector2i):
	state = State.STOPPED
	sprite.modulate = main.collision_color

	# Reset sprite scale
	sprite.scale = Vector2(tile_size / sprite.texture.get_size().x, tile_size / sprite.texture.get_size().y)

	# Check validity
	if not map:
		push_error("handle_collision(): Map reference is null.")
		return

	if not map.is_in_bounds(grid_pos):
		#push_error("handle_collision(): Invalid grid position: " + str(grid_pos))
		main.ale_manager.respawn_ale(self)
		return

	if sprite.modulate == Color(0,0,0):     #  defensive
		push_warning("ALE %d received black colour – resetting to default" % ale_id)
		sprite.modulate = body_color


	# Get the other ALE if possible
	#var other = get_colliding_ale(grid_pos)


	# Set stop_turns dynamically based on terrain   <==============
	var base_stop_turns = randi_range(5, 15)

	if map.is_high_energy_zone(grid_pos):
		stop_turns = base_stop_turns + 5
	elif map.is_stable_zone(grid_pos):
		stop_turns = max(3, base_stop_turns - 5)
	else:
		stop_turns = base_stop_turns

	stop_timer = stop_turns
	#print("Collision at:", grid_pos, "Stopping for:", stop_turns, "turns")

	var other = get_colliding_ale(_collision_pos)
	if other:
		var msg := "Collision: ALE %d ↔ ALE %d at %s" % [ale_id, other.ale_id, str(grid_pos)]
		#print("ALE %d collided with %s" % [ale_id, other if other else "nothing"])
		SignalBus.message_sent.emit(msg, main.collision_color)
		var turns_stopped := "Stopping for: %d turns" % [stop_turns]
		SignalBus.message_sent.emit(turns_stopped,main.collision_color)
	else:
		var fallback_msg := "Collision: ALE %d at %s" % [ale_id, str(grid_pos)]
		#print("ALE %d collided with %s" % [ale_id, other if other else "nothing"])
		print("ALE %d collided with %s" % [ale_id, str(other) if other else "nothing"])
		SignalBus.message_sent.emit(fallback_msg, main.collision_color)


func get_colliding_ale(target_pos: Vector2i) -> ALE:
	for ale in get_parent().get_children():
		if ale is ALE and ale != self and ale.grid_pos == target_pos:
			return ale
	return null



func move_to(new_pos: Vector2i):
	"""
	Moves ALE to a specific grid position.
	Used for controlled movement logic.
	"""
	grid_pos = new_pos
	position = Vector2(Grid.grid_to_world(grid_pos.x, grid_pos.y, tile_size)) + Vector2(tile_size / 2.0, tile_size / 2.0)

	#if ENABLE_VISITED_CELLS:
		#visited_cells[grid_pos] = true

	#if ENABLE_TRAILS:
		#map.add_trail(grid_pos)

func leave_trail(prev_pos: Vector2i):
	"""
	Leaves a trail at the ALE’s previous position using the dynamically assigned trail color.
	Trail duration and fade effect are controlled by values in main.gd.
	"""
	if not map or prev_pos == Vector2i.ZERO:
		return  # Ensure the map exists and prev_pos is valid

	if not map.is_in_bounds(prev_pos):
		return  # Ensure the previous position is inside bounds

	# **Ensure trail color is properly assigned from `main.gd`**
	if not trail_color:
		trail_color = main.trail_color  # Assign trail color from Main if not set

	# **Ensure only the trail is affected, not the ALE itself**
	var adjusted_trail_color = trail_color
	adjusted_trail_color.a = 1.0  # Ensure full opacity for the trail

	# **Pass the correct color and duration values to TrailManager**
	map.trail_manager.add_trail(prev_pos, adjusted_trail_color, main.trail_duration, main.trail_fade)
