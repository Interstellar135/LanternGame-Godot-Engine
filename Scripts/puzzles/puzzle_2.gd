extends Control

signal completed(success: bool)

const SLOT_COUNT := 18
const EMPTY := -1

@export var success_nodes: Array[NodePath] = []

var slot_to_tile: PackedInt32Array = PackedInt32Array()
var tile_to_slot: PackedInt32Array = PackedInt32Array()
var tile_correct_slot: PackedInt32Array = PackedInt32Array()

var selected_tile_id := -1

var _tile_nodes: Array[TextureRect] = []
var _slot_nodes: Array[TextureRect] = []
var _slot_global_positions: Array[Vector2] = []

var _tiles_layer: Node
var _slots_layer: Node


func _ready() -> void:
	_tiles_layer = get_node("tiles_layer")
	_slots_layer = get_node("slots")

	_collect_tile_and_slot_nodes()
	if not _validate_required_nodes():
		return
	_build_correct_mapping()
	_capture_slot_global_positions()
	_connect_gui_input_handlers()
	reset_to_initial()


func _collect_tile_and_slot_nodes() -> void:
	_tile_nodes.resize(SLOT_COUNT)
	_slot_nodes.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_tile_nodes[i] = null
		_slot_nodes[i] = null

	for child in _tiles_layer.get_children():
		if child is TextureRect:
			var tile_node := child as TextureRect
			var tile_id := _parse_suffix_id(tile_node.name, "tile_")
			if tile_id >= 0 and tile_id < SLOT_COUNT:
				_tile_nodes[tile_id] = tile_node

	for child in _slots_layer.get_children():
		if child is TextureRect:
			var slot_node := child as TextureRect
			var slot_id := _parse_suffix_id(slot_node.name, "slot_")
			if slot_id >= 0 and slot_id < SLOT_COUNT:
				_slot_nodes[slot_id] = slot_node


func _validate_required_nodes() -> bool:
	var ok := true
	for i in range(SLOT_COUNT):
		if _tile_nodes[i] == null:
			push_error("Missing tile node: tile_%02d" % i)
			ok = false
		if _slot_nodes[i] == null:
			push_error("Missing slot node: slot_%02d" % i)
			ok = false
	return ok


func _build_correct_mapping() -> void:
	tile_correct_slot = PackedInt32Array()
	tile_correct_slot.resize(SLOT_COUNT)
	for tile_id in range(SLOT_COUNT):
		tile_correct_slot[tile_id] = tile_id


func _capture_slot_global_positions() -> void:
	_slot_global_positions.resize(SLOT_COUNT)
	for slot_id in range(SLOT_COUNT):
		var s := _slot_nodes[slot_id]
		if s == null:
			_slot_global_positions[slot_id] = Vector2.ZERO
			continue
		_slot_global_positions[slot_id] = s.global_position


func _connect_gui_input_handlers() -> void:
	for tile_id in range(SLOT_COUNT):
		var tile_node := _tile_nodes[tile_id]
		if tile_node == null:
			continue
		var tile_callable := Callable(self, "_on_tile_gui_input").bind(tile_id)
		if not tile_node.is_connected("gui_input", tile_callable):
			tile_node.connect("gui_input", tile_callable)

	for slot_id in range(SLOT_COUNT):
		var slot_node := _slot_nodes[slot_id]
		if slot_node == null:
			continue
		var slot_callable := Callable(self, "_on_slot_gui_input").bind(slot_id)
		if not slot_node.is_connected("gui_input", slot_callable):
			slot_node.connect("gui_input", slot_callable)


func _on_tile_gui_input(event: InputEvent, tile_id: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			selected_tile_id = tile_id


func _on_slot_gui_input(event: InputEvent, slot_id: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if selected_tile_id == -1:
				return
			place(selected_tile_id, slot_id)
			set_success_visual(is_solved())


func place(tile_id: int, slot_id: int) -> void:
	if tile_id < 0 or tile_id >= SLOT_COUNT:
		return
	if slot_id < 0 or slot_id >= SLOT_COUNT:
		return

	var old_slot := tile_to_slot[tile_id]
	if old_slot == slot_id:
		_move_tile_to_slot(tile_id, slot_id)
		return

	var tile_old := slot_to_tile[slot_id]

	if old_slot != EMPTY:
		slot_to_tile[old_slot] = EMPTY

	if tile_old != EMPTY:
		tile_to_slot[tile_old] = old_slot
		if old_slot != EMPTY:
			slot_to_tile[old_slot] = tile_old
			_move_tile_to_slot(tile_old, old_slot)

	slot_to_tile[slot_id] = tile_id
	tile_to_slot[tile_id] = slot_id
	_move_tile_to_slot(tile_id, slot_id)


func is_solved() -> bool:
	for slot_id in range(SLOT_COUNT):
		var tile_id := slot_to_tile[slot_id]
		if tile_id == EMPTY:
			return false
		if tile_correct_slot[tile_id] != slot_id:
			return false
	return true


func reset_to_initial() -> void:
	selected_tile_id = -1
	_rebuild_derangement_layout()
	set_success_visual(false)


func set_success_visual(visible: bool) -> void:
	for path in success_nodes:
		if path == NodePath():
			continue
		var n := get_node_or_null(path)
		if n is CanvasItem:
			(n as CanvasItem).visible = visible


func _rebuild_derangement_layout() -> void:
	slot_to_tile = PackedInt32Array()
	tile_to_slot = PackedInt32Array()
	slot_to_tile.resize(SLOT_COUNT)
	tile_to_slot.resize(SLOT_COUNT)

	for i in range(SLOT_COUNT):
		slot_to_tile[i] = EMPTY
		tile_to_slot[i] = EMPTY

	# Deterministic derangement: rotate by +1, so slot_to_tile[slot] != slot for all slot.
	for slot_id in range(SLOT_COUNT):
		var tile_id := (slot_id + 1) % SLOT_COUNT
		slot_to_tile[slot_id] = tile_id
		tile_to_slot[tile_id] = slot_id

	for slot_id in range(SLOT_COUNT):
		var tile_id := slot_to_tile[slot_id]
		_move_tile_to_slot(tile_id, slot_id)


func _move_tile_to_slot(tile_id: int, slot_id: int) -> void:
	if tile_id < 0 or tile_id >= _tile_nodes.size():
		return
	var tile_node := _tile_nodes[tile_id]
	if tile_node == null:
		return
	if slot_id < 0 or slot_id >= _slot_global_positions.size():
		return
	var dest := _slot_global_positions[slot_id]
	tile_node.global_position = dest


func _parse_suffix_id(node_name: String, prefix: String) -> int:
	if not node_name.begins_with(prefix):
		return -1
	var suffix := node_name.substr(prefix.length())
	if suffix.length() != 2:
		return -1
	if not suffix.is_valid_int():
		return -1
	return int(suffix)
