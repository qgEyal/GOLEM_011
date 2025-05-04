
class_name Main
extends Node2D

# Version number of the G.O.L.E.M framework
const GOLEM_VERSION: String = "0.2.4.6 - SEAL core"


## SUBVIEWPORT INFO
@onready var sub_viewport: SubViewport = $".."


# Initialization
@onready var map: Map = $Map
@onready var ale_manager: ALEManager = $ALEManager
@onready var nav_cam: Camera2D = $NavCam
@onready var grid_vis: Node2D = $GridVis
#@onready var stats_label: Label = $"../../../InfoBar/StatsPanel/VBoxContainer/StatsLabel"
#@onready var stats_label: StatsLabel = $"../../../InfoBar/StatsPanel/VBoxContainer/StatsLabel"
@onready var stats_panel: StatsPanel = $"../../../InfoBar/StatsPanelContainer/StatsPanel"

@onready var simulation_menu: SimulationMenu = $"../SimulationMenu"



# Set World Parameters and pass them to Map
@export_category("World")
@export var world_width: int = 60
@export var world_height: int = 40
@export var tile_size: int = 16
#@export var show_tile_borders: bool = true
var grid_visible: bool = true  # Track current visibility state

@export_category("ALE Setup")
@export var ale_count: int = 10
@export var ale_color: Color = Color.WHITE
@export var trail_color: Color = Color.BEIGE
@export var collision_color: Color = Color.CHARTREUSE


@export_category("ALE Movement")
@export var min_speed: float = 0.5  # Slowest possible ALE speed
@export var max_speed: float = 2.0  # Fastest possible ALE speed
@export var stop_turns: int = 10  # Number of turns an ALE should stop when colliding

@export_category("Stigmergy")
@export var trail_duration: float = 5.0  # How long the trail lasts
@export var trail_fade: float = 3.0  # How quickly the trail fades

@export_category("Simulation")
@export var simulation_speed: float = 1.0
@export var max_turns: int = 0  # Maximum number of simulation turns (0 = infinite)

@export var ENABLE_VISITED_CELLS: bool = true
@export var ENABLE_TRAILS: bool = true
@export var ENABLE_COLLISION_HANDLING: bool = true

var ale_definition: ALEdefinition = preload("res://assets/resources/ale_definition.tres")
var stored_trail_color: Color

# Time tracking variables
var time_accumulator: float = 0.0  # Tracks elapsed time for frame updates
var current_turn: int = 0  # Tracks the number of simulation turns completed

var simulation_active: bool = true  # Controls whether the simulation is running

@onready var pause_label: Label = $"../CanvasLayer/PauseLabel"  # Reference to the pause label

func _ready():

	add_to_group("MainNode")  # Ensures ALE can find Main
	Engine.max_fps = 0
	pause_label.visible = false  # Hide pause label initially

	grid_visible = false
	if grid_vis:
		grid_vis.visible = grid_visible
	else:
		push_error("GridVis node not found!")

	# Get info from UI menu
	#if simulation_menu:
		#simulation_menu.simulation_parameters_set.connect(apply_simulation_settings)
	#else:
		#push_error("SimulationMenu node not found!")

	if simulation_menu:
		# Send Main’s current exported values to the menu
		simulation_menu.populate_from_params({
			"world_width":  world_width,
			"world_height": world_height,
			"max_turns":    max_turns,
			"ale_count":    ale_count
		})
		simulation_menu.simulation_parameters_set.connect(apply_simulation_settings)
	else:
		push_error("SimulationMenu node not found!")

	# Optionally disable simulation until setup is complete
	simulation_active = false

	## WITHOUT SIMULATION_MENU
	#print("Initialize Map")
	#initialize_map()
#
	#print("Initialize ALE Manager")
	#initialize_ale_manager()
#
	#_center_camera()


	# Dynamic StatsPanel
	if stats_panel:
		stats_panel.update_stat("G.O.L.E.M. Framework\nVERSION", GOLEM_VERSION, GameColors.TEXT_BLUE)
		#stats_panel.update_stat("Number of ALES:", ale_count, GameColors.TEXT_INFO)
		#stats_panel.update_stat("G.O.L.E.M. Framework\nVERSION %s\nALEs: %d" % [GOLEM_VERSION, ale_count], GameColors.TEXT_BLUE)



func _process(delta: float) -> void:
	"""
	Handles simulation timing, turn tracking, and stops simulation when max_turns is reached.
	"""
	# Get FPS
	#get_window().title = "FPS: " + str(Engine.get_frames_per_second())

	if pause_label.visible:
		pause_label.visible = false  # Ensure pause label hides when running

	if not simulation_active:
		return  # Stop processing when the simulation is complete

	time_accumulator += delta * simulation_speed

	if time_accumulator >= 1.0:
		time_accumulator = 0.0
		current_turn += 1
		#print("Turn:", current_turn)

		# **Ensure Simulation Ends at max_turns**
		if max_turns > 0 and current_turn >= max_turns:
			var simulation_complete: String = "Simulation complete. Reached max turns (%d)" % max_turns
			MessageLog.send_message(simulation_complete, GameColors.TEXT_DEFAULT)
			end_simulation()

	# Dynaic StatsPanel
	if stats_panel:
		stats_panel.update_stat("FPS", str(Engine.get_frames_per_second()), GameColors.TEXT_INFO)
		stats_panel.update_stat("Turn", str(current_turn), GameColors.TEXT_DEFAULT)
		#stats_panel.update_stat("Simulation", simulation_active ? "Active" : "Paused", GameColors.TEXT_DEFAULT)

func apply_simulation_settings(params: Dictionary):
	world_width = params.get("world_width", world_width)
	world_height = params.get("world_height", world_height)
	#tile_size = params.get("tile_size", tile_size)
	max_turns = params.get("max_turns" ,max_turns)
	ale_count = params.get("ale_count", ale_count)

	print("Simulation Parameters Received: ", params)

	initialize_map()
	initialize_ale_manager()
	await get_tree().process_frame
	_center_camera()

	# Now activate the simulation
	simulation_active = true

	var summary := "Map: %dx%d  |  ALEs: %d" % [world_width, world_height, ale_count]
	MessageLog.send_message("G.O.L.E.M. Framework\nVERSION %s" % GOLEM_VERSION, GameColors.TEXT_DEFAULT)
	MessageLog.send_message(summary, GameColors.TEXT_BLUE)

	# populate UI from params
	if simulation_menu:
		simulation_menu.populate_from_params(params)



func end_simulation():
	"""
	Ends the simulation when the maximum number of turns is reached.
	Disables processing for all ALEs to completely stop their movement.
	"""
	simulation_active = false
	print("Simulation completed after ", max_turns, " turns.")

	# Disable processing for all ALEs
	for ale in ale_manager.get_children():
		if ale is ALE:
			ale.set_process_mode(PROCESS_MODE_DISABLED)  # Completely stop ALE updates

func initialize_map() -> void:
	map.initialize(world_width, world_height, tile_size, self)


func initialize_ale_manager():

	ale_manager.initialize(map, tile_size, ale_count, ale_color, trail_color, self, ENABLE_VISITED_CELLS, ENABLE_TRAILS, ENABLE_COLLISION_HANDLING)
	#ale_manager.ale_definition.trail_color = trail_color  # Apply user-defined trail color


func _center_camera():
	await get_tree().process_frame  # Ensure nodes are fully initialized
	#if nav_cam and nav_cam.has_method("center_on_map"):
	if nav_cam and nav_cam.has_method("update_bounds"):
		#nav_cam.center_on_map()
		nav_cam.update_bounds()
	else:
		print("Error: Camera script is missing or method not found!")

func _input(event):
	if event.is_action_pressed("ui_up"):
		simulation_speed = min(simulation_speed + 0.1, 5.0)
		print("Simulation Speed:", simulation_speed)
	elif event.is_action_pressed("ui_down"):
		simulation_speed = max(simulation_speed - 0.1, 0.1)
		print("Simulation Speed:", simulation_speed)
	#if event.is_action_pressed("reset"):
		#get_tree().reload_current_scene()
	if event.is_action_pressed("reset"):
		await get_tree().process_frame  # Ensures input is fully processed
		get_tree().reload_current_scene()

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_grid"):  # G key action
		toggle_grid_visibility()

	if Input.is_action_just_pressed("pause_simulation"):
		pause_game()  # Pause the simulation

func toggle_grid_visibility():
	"""
	Toggles the visibility of the GridVis layer on and off.
	"""
	grid_visible = !grid_visible  # Flip the state

	grid_vis.visible = grid_visible
	print("Grid Visibility:", "ON" if grid_visible else "OFF")

#func update_stats(text: String):
	#if stats_label:
		#stats_label.text = text


func _on_pause_toggled(paused: bool):
	"""
	Handles the simulation pause and resume functionality.
	"""
	print("Pause state updated in Main:", paused)

# Pauses the simulation and displays the pause label
func pause_game():
	"""
	Pauses the simulation and displays the pause message.
	"""
	pause_label.visible = true
	get_tree().paused = true  # Pause the entire simulation
