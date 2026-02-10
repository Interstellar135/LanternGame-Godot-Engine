extends Node2D

signal puzzle_opened(puzzle_id: StringName)
signal puzzle_closed(puzzle_id: StringName, reason: StringName)
signal puzzle_resolved(puzzle_id: StringName, success: bool)
signal request_level_change(next_level_path: String)

const PUZZLE_1_ID: StringName = &"puzzle_1"
const PUZZLE_2_ID: StringName = &"puzzle_2"
const PUZZLE_1_SCENE_PATH := "res://Scenes/Puzzle_1.tscn"
const PUZZLE_2_SCENE_PATH := "res://Scenes/Puzzle_2.tscn"

@export var next_level_path_by_puzzle_id: Dictionary = {}
@export var hud_hint_label_path: NodePath

var active_puzzle: Node = null
var active_puzzle_id: StringName = &""
var puzzle_mode: bool = false
var current_interactable_id: StringName = &""

@onready var _puzzle_layer: CanvasItem = get_node_or_null("../PuzzleLayer") as CanvasItem
@onready var _puzzle_root: Node = get_node_or_null("../PuzzleLayer/PuzzleRoot")
@onready var _puzzle_hud: CanvasItem = get_node_or_null("../PuzzleLayer/puzzle_hud") as CanvasItem
@onready var _esc_button: Button = get_node_or_null("../PuzzleLayer/puzzle_hud/esc") as Button
@onready var _submit_button: Button = get_node_or_null("../PuzzleLayer/puzzle_hud/submit") as Button
@onready var _reset_button: Button = get_node_or_null("../PuzzleLayer/puzzle_hud/reset") as Button
@onready var _player: Node = get_node_or_null("../Player")

var _hint_label: Label = null
var _puzzle_1_scene: PackedScene = null
var _puzzle_2_scene: PackedScene = null


func _ready() -> void:
	_load_puzzle_scenes()
	_self_check_paths()
	_connect_hud_buttons_once()
	_cache_hint_label()
	_set_puzzle_ui_visible(false)
	_debug("ready done - PuzzleManager initialized")


func _unhandled_input(event: InputEvent) -> void:
	if puzzle_mode:
		return
	if current_interactable_id == &"":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			open_puzzle(current_interactable_id)
			get_viewport().set_input_as_handled()


func open_puzzle(puzzle_id: StringName) -> void:
	if puzzle_id == &"":
		push_error("[PuzzleManager] open_puzzle failed: empty puzzle_id")
		return

	if _puzzle_root == null:
		push_error("[PuzzleManager] open_puzzle failed: missing ../PuzzleLayer/PuzzleRoot")
		return

	# Strategy required by contract: close first, then open, to avoid multi-instance reentry issues.
	if active_puzzle != null:
		close_puzzle(&"reopen")

	var scene := _get_scene_by_id(puzzle_id)
	if scene == null:
		push_error("[PuzzleManager] open_puzzle failed: unknown puzzle_id = %s" % String(puzzle_id))
		return

	active_puzzle = scene.instantiate()
	active_puzzle_id = puzzle_id
	_puzzle_root.add_child(active_puzzle)
	_set_puzzle_ui_visible(true)
	_set_player_input_enabled(false)
	puzzle_mode = true
	_set_hud_hint("Puzzle opened: %s" % String(puzzle_id))
	_debug("opened %s" % String(puzzle_id))
	emit_signal("puzzle_opened", puzzle_id)


func close_puzzle(reason: StringName = &"cancel") -> void:
	var closed_id := active_puzzle_id

	if active_puzzle != null and is_instance_valid(active_puzzle):
		active_puzzle.queue_free()

	active_puzzle = null
	active_puzzle_id = &""
	_set_puzzle_ui_visible(false)
	_set_player_input_enabled(true)
	puzzle_mode = false
	_set_hud_hint("")
	_debug("closed puzzle=%s reason=%s" % [String(closed_id), String(reason)])
	emit_signal("puzzle_closed", closed_id, reason)


func submit_puzzle() -> void:
	if active_puzzle == null:
		_debug("submit ignored: no active puzzle")
		return

	if not active_puzzle.has_method("is_solved"):
		push_error("[PuzzleManager] submit failed: active puzzle missing is_solved()")
		return

	var solved_variant: Variant = active_puzzle.call("is_solved")
	if typeof(solved_variant) != TYPE_BOOL:
		push_error("[PuzzleManager] submit failed: is_solved() must return bool")
		return

	var solved := solved_variant as bool
	if solved:
		_set_hud_hint("Solved")
		_debug("submit success: %s" % String(active_puzzle_id))
		emit_signal("puzzle_resolved", active_puzzle_id, true)
		_emit_level_change_if_configured(active_puzzle_id)
		close_puzzle(&"success")
		return

	if active_puzzle_id == PUZZLE_2_ID:
		# Contract: Puzzle2 submit fail is NOT a failure state. Keep puzzle open, no close, no respawn.
		_set_hud_hint("Puzzle 2 not complete")
		_debug("submit fail on puzzle_2: keep open")
		return

	if active_puzzle_id == PUZZLE_1_ID:
		# Selected policy: Option A. Show not-complete hint and DO NOT reset.
		_set_hud_hint("Puzzle 1 not complete")
		_debug("submit fail on puzzle_1: keep open, no reset")
		return

	_set_hud_hint("Not complete")
	_debug("submit fail on unknown puzzle id: %s" % String(active_puzzle_id))


func cancel_puzzle() -> void:
	close_puzzle(&"cancel")


func reset_puzzle() -> void:
	if active_puzzle == null:
		_debug("reset ignored: no active puzzle")
		return
	if active_puzzle.has_method("reset_to_initial"):
		active_puzzle.call("reset_to_initial")
		_set_hud_hint("Puzzle reset")
		_debug("reset active puzzle: %s" % String(active_puzzle_id))
	else:
		push_error("[PuzzleManager] reset failed: active puzzle missing reset_to_initial()")


func respawn_to_spawn() -> void:
	# Reserved generic API for future death/penalty systems.
	# Not used by Puzzle2 submit fail, because Puzzle2 has no failure state by contract.
	if _player == null:
		push_error("[PuzzleManager] respawn failed: missing ../Player")
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		push_error("[PuzzleManager] respawn failed: current_scene is null")
		return

	var spawn := _find_spawn_marker(current_scene)
	if spawn == null:
		push_error("[PuzzleManager] respawn failed: no Marker2D named 'Spawn' in current scene")
		return

	if _player is Node2D:
		(_player as Node2D).global_position = spawn.global_position
		_debug("respawned player to Spawn")
	else:
		push_error("[PuzzleManager] respawn failed: Player is not Node2D")


func set_interactable(puzzle_id: StringName) -> void:
	if puzzle_id == &"":
		return
	current_interactable_id = puzzle_id
	_debug("set_interactable: %s" % String(puzzle_id))


func clear_interactable(puzzle_id: StringName = &"") -> void:
	if puzzle_id == &"" or current_interactable_id == puzzle_id:
		_debug("clear_interactable: %s" % String(current_interactable_id))
		current_interactable_id = &""


func _load_puzzle_scenes() -> void:
	if ResourceLoader.exists(PUZZLE_1_SCENE_PATH):
		_puzzle_1_scene = load(PUZZLE_1_SCENE_PATH) as PackedScene
	else:
		push_error("[PuzzleManager] missing puzzle scene: %s" % PUZZLE_1_SCENE_PATH)

	if ResourceLoader.exists(PUZZLE_2_SCENE_PATH):
		_puzzle_2_scene = load(PUZZLE_2_SCENE_PATH) as PackedScene
	else:
		push_error("[PuzzleManager] missing puzzle scene: %s" % PUZZLE_2_SCENE_PATH)


func _self_check_paths() -> void:
	if _puzzle_layer == null:
		push_error("[PuzzleManager] missing node: ../PuzzleLayer")
	if _puzzle_root == null:
		push_error("[PuzzleManager] missing node: ../PuzzleLayer/PuzzleRoot")
	if _esc_button == null:
		push_error("[PuzzleManager] missing node: ../PuzzleLayer/puzzle_hud/esc")
	if _submit_button == null:
		push_error("[PuzzleManager] missing node: ../PuzzleLayer/puzzle_hud/submit")
	if _reset_button == null:
		push_warning("[PuzzleManager] missing optional node: ../PuzzleLayer/puzzle_hud/reset (add this button)")
	if _player == null:
		push_error("[PuzzleManager] missing node: ../Player")


func _connect_hud_buttons_once() -> void:
	if _esc_button != null and not _esc_button.pressed.is_connected(cancel_puzzle):
		_esc_button.pressed.connect(cancel_puzzle)
	if _submit_button != null and not _submit_button.pressed.is_connected(submit_puzzle):
		_submit_button.pressed.connect(submit_puzzle)
	if _reset_button != null and not _reset_button.pressed.is_connected(reset_puzzle):
		_reset_button.pressed.connect(reset_puzzle)


func _cache_hint_label() -> void:
	if hud_hint_label_path == NodePath():
		return
	var node := get_node_or_null(hud_hint_label_path)
	if node is Label:
		_hint_label = node as Label
	else:
		push_warning("[PuzzleManager] hud_hint_label_path is not a Label")


func _set_hud_hint(text: String) -> void:
	if _hint_label != null:
		_hint_label.text = text
	if text != "":
		_debug("HUD: %s" % text)


func _set_puzzle_ui_visible(visible: bool) -> void:
	if _puzzle_layer != null:
		_puzzle_layer.visible = visible
	if _puzzle_hud != null:
		_puzzle_hud.visible = visible


func _set_player_input_enabled(enabled: bool) -> void:
	if _player == null:
		return
	_player.set_process_input(enabled)
	_player.set_physics_process(enabled)
	_player.set_process_unhandled_input(enabled)


func _get_scene_by_id(puzzle_id: StringName) -> PackedScene:
	if puzzle_id == PUZZLE_1_ID:
		return _puzzle_1_scene
	if puzzle_id == PUZZLE_2_ID:
		return _puzzle_2_scene
	return null


func _emit_level_change_if_configured(puzzle_id: StringName) -> void:
	if not next_level_path_by_puzzle_id.has(String(puzzle_id)):
		return
	var next_path_variant: Variant = next_level_path_by_puzzle_id[String(puzzle_id)]
	if typeof(next_path_variant) != TYPE_STRING:
		push_error("[PuzzleManager] next_level_path_by_puzzle_id[%s] must be String" % String(puzzle_id))
		return
	var next_path := next_path_variant as String
	if next_path == "":
		return
	_debug("request_level_change: %s" % next_path)
	emit_signal("request_level_change", next_path)


func _find_spawn_marker(root: Node) -> Marker2D:
	if root is Marker2D and root.name == "Spawn":
		return root as Marker2D
	for child in root.get_children():
		var result := _find_spawn_marker(child)
		if result != null:
			return result
	return null


func _debug(msg: String) -> void:
	print("[PuzzleManager] %s" % msg)



func _on_reset_pressed() -> void:
	pass # Replace with function body.

func _on_submit_pressed() -> void:
	pass # Replace with function body.
