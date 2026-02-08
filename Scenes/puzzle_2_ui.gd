# res://Scripts/puzzles/puzzlez_2_ui.gd
extends Control
class_name Puzzle2UI

signal completed(success: bool)

const TILE_COUNT: int = 18
const FALLBACK_SUBMIT_PATHS: Array[NodePath] = [^"hud/submit"]
const FALLBACK_RESET_PATHS: Array[NodePath] = [^"hud/reset"]
const FALLBACK_TIP_PATHS: Array[NodePath] = [^"hud/tip", ^"hud/label"]

@export var slots_root_path: NodePath = ^"board/slots"
@export var tiles_root_path: NodePath = ^"tiles_layers"
@export var submit_btn_path: NodePath = ^"hud/btn_submit"
@export var reset_btn_path: NodePath = ^"hud/btn_reset"
@export var tip_label_path: NodePath = ^"hud/lbl_tip"
@export var success_layer_path: NodePath = ^"success_layer"
@export var scramble_swaps: int = 40
@export var debug_hotkey_enabled: bool = true

var _slots: Array[TextureButton] = []
var _tiles: Array[TextureRect] = []
var _slot_base_modulates: Array[Color] = []

# Discrete state: slot_index -> tile_id
var _slot_to_tile: PackedInt32Array = PackedInt32Array()
# Discrete state: tile_id -> correct_slot_index
var _tile_to_correct_slot: PackedInt32Array = PackedInt32Array()
# Discrete state: tile_id -> current_slot_index
var _tile_to_current_slot: PackedInt32Array = PackedInt32Array()
# Initial scrambled state of this round (for reset)
var _initial_slot_to_tile: PackedInt32Array = PackedInt32Array()

var _tiles_root: Control = null
var _submit_btn: Button = null
var _reset_btn: Button = null
var _tip_label: Label = null
var _success_layer: Control = null

var _active: bool = false
var _selected_slot: int = -1
var _selected_tile: int = -1
var _initialized: bool = false

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	print("[Puzzle2UI] _ready path=%s" % [get_path()])
	_rng.randomize()

	_collect_nodes()
	_resolve_ui_nodes()
	_wire_ui()
	_setup_mouse_passthrough()

	if not _validate_counts():
		return

	_allocate_state_arrays()
	_capture_correct_state_from_editor_layout()
	_start_new_round()

	_hide_success()
	_set_tip("")
	_active = false
	visible = false
	_initialized = true

	print("[Puzzle2UI] slots=%d tiles=%d" % [_slots.size(), _tiles.size()])
	print("[Puzzle2UI] slots_root=%s tiles_root=%s" % [slots_root_path, tiles_root_path])


func begin_new() -> void:
	if not _initialized:
		return
	visible = true
	_active = true
	_start_new_round()
	_set_tip("Left click: slot -> tile -> slot. Right click: submit.")


func close() -> void:
	_active = false
	visible = false
	_clear_selection()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_submit_global_right_click()
			return

	if not debug_hotkey_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		print(
			"[Puzzle2UI] DEBUG active=%s selected_slot=%d selected_tile=%d solved=%s"
			% [_active, _selected_slot, _selected_tile, _is_solved()]
		)
		print("[Puzzle2UI] DEBUG slot_to_tile=%s" % [_slot_to_tile])


func _collect_nodes() -> void:
	_slots.clear()
	_tiles.clear()
	_slot_base_modulates.clear()

	var slots_root := get_node_or_null(slots_root_path)
	_tiles_root = get_node_or_null(tiles_root_path) as Control

	if slots_root == null:
		push_error("Puzzle2UI: slots root not found: %s" % [slots_root_path])
		return
	if _tiles_root == null:
		push_error("Puzzle2UI: tiles root not found or not Control: %s" % [tiles_root_path])
		return

	for child in slots_root.get_children():
		if child is TextureButton and String(child.name).begins_with("slot_"):
			_slots.append(child as TextureButton)

	for child in _tiles_root.get_children():
		if child is TextureRect and String(child.name).begins_with("tile_"):
			_tiles.append(child as TextureRect)

	_slots.sort_custom(func(a: TextureButton, b: TextureButton) -> bool:
		return _extract_suffix_index(a.name) < _extract_suffix_index(b.name)
	)
	_tiles.sort_custom(func(a: TextureRect, b: TextureRect) -> bool:
		return _extract_suffix_index(a.name) < _extract_suffix_index(b.name)
	)

	for slot in _slots:
		_slot_base_modulates.append(slot.modulate)


func _resolve_ui_nodes() -> void:
	_submit_btn = _find_button(submit_btn_path, FALLBACK_SUBMIT_PATHS)
	_reset_btn = _find_button(reset_btn_path, FALLBACK_RESET_PATHS)
	_tip_label = _find_label(tip_label_path, FALLBACK_TIP_PATHS)
	_success_layer = get_node_or_null(success_layer_path) as Control

	if _success_layer == null:
		push_warning("Puzzle2UI: success layer not found: %s" % [success_layer_path])


func _find_button(primary_path: NodePath, fallback_paths: Array[NodePath]) -> Button:
	var btn := get_node_or_null(primary_path) as Button
	if btn != null:
		return btn
	for p in fallback_paths:
		btn = get_node_or_null(p) as Button
		if btn != null:
			return btn
	return null


func _find_label(primary_path: NodePath, fallback_paths: Array[NodePath]) -> Label:
	var label := get_node_or_null(primary_path) as Label
	if label != null:
		return label
	for p in fallback_paths:
		label = get_node_or_null(p) as Label
		if label != null:
			return label
	return null


func _wire_ui() -> void:
	for i in range(_slots.size()):
		var slot_index := i
		var slot_cb := _on_slot_pressed.bind(slot_index)
		if not _slots[i].pressed.is_connected(slot_cb):
			_slots[i].pressed.connect(slot_cb)
		var slot_gui_cb := _on_slot_gui_input.bind(slot_index)
		if not _slots[i].gui_input.is_connected(slot_gui_cb):
			_slots[i].gui_input.connect(slot_gui_cb)

	for i in range(_tiles.size()):
		var tile_id := i
		var tile_cb := _on_tile_gui_input.bind(tile_id)
		if not _tiles[i].gui_input.is_connected(tile_cb):
			_tiles[i].gui_input.connect(tile_cb)

	if _submit_btn != null and not _submit_btn.pressed.is_connected(_on_submit_pressed):
		_submit_btn.pressed.connect(_on_submit_pressed)
	if _reset_btn != null and not _reset_btn.pressed.is_connected(_on_reset_pressed):
		_reset_btn.pressed.connect(_on_reset_pressed)


func _setup_mouse_passthrough() -> void:
	if _tiles_root == null:
		return
	# tiles_layer itself should not block, child tile filtering is switched by state.
	_tiles_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_refresh_tile_click_state()


func _refresh_tile_click_state() -> void:
	var tile_click_phase := _active and _selected_slot != -1 and _selected_tile == -1
	for tile in _tiles:
		tile.mouse_filter = Control.MOUSE_FILTER_STOP if tile_click_phase else Control.MOUSE_FILTER_IGNORE


func _validate_counts() -> bool:
	if _slots.size() != TILE_COUNT or _tiles.size() != TILE_COUNT:
		push_error(
			"Puzzle2UI: count mismatch, slots=%d tiles=%d expected=%d"
			% [_slots.size(), _tiles.size(), TILE_COUNT]
		)
		print(
			"[Puzzle2UI] count mismatch details: slots=%d tiles=%d expected=%d"
			% [_slots.size(), _tiles.size(), TILE_COUNT]
		)
		return false
	return true


func _allocate_state_arrays() -> void:
	_slot_to_tile.resize(TILE_COUNT)
	_tile_to_correct_slot.resize(TILE_COUNT)
	_tile_to_current_slot.resize(TILE_COUNT)


func _capture_correct_state_from_editor_layout() -> void:
	var nearest_map: PackedInt32Array = PackedInt32Array()
	nearest_map.resize(TILE_COUNT)

	var nearest_used := {}
	var nearest_unique := true

	for tile_id in range(TILE_COUNT):
		var slot_idx := _find_nearest_slot_for_tile(_tiles[tile_id])
		nearest_map[tile_id] = slot_idx
		if nearest_used.has(slot_idx):
			nearest_unique = false
		nearest_used[slot_idx] = true

	if nearest_unique and nearest_used.size() == TILE_COUNT:
		_tile_to_correct_slot = nearest_map
		print("[Puzzle2UI] correct state captured by nearest-position mapping.")
		return

	print("Puzzle2UI: nearest-position mapping is not one-to-one; fallback to name mapping.")
	if _capture_correct_state_by_name():
		print("[Puzzle2UI] correct state captured by name mapping.")
		return

	print("Puzzle2UI: name mapping failed; fallback to index mapping tile_i -> slot_i.")
	for tile_id in range(TILE_COUNT):
		_tile_to_correct_slot[tile_id] = tile_id


func _capture_correct_state_by_name() -> bool:
	var slot_idx_by_suffix := {}
	for slot_index in range(TILE_COUNT):
		var suffix := _extract_suffix_index(_slots[slot_index].name)
		if suffix < 0:
			continue
		slot_idx_by_suffix[suffix] = slot_index

	for tile_id in range(TILE_COUNT):
		var suffix := _extract_suffix_index(_tiles[tile_id].name)
		if suffix < 0 or not slot_idx_by_suffix.has(suffix):
			return false
		_tile_to_correct_slot[tile_id] = int(slot_idx_by_suffix[suffix])

	var used := {}
	for tile_id in range(TILE_COUNT):
		var slot_idx := _tile_to_correct_slot[tile_id]
		if used.has(slot_idx):
			return false
		used[slot_idx] = true
	return used.size() == TILE_COUNT


func _find_nearest_slot_for_tile(tile: TextureRect) -> int:
	var tile_center := tile.global_position + tile.size * 0.5
	var best_slot := 0
	var best_dist := INF

	for slot_idx in range(TILE_COUNT):
		var slot := _slots[slot_idx]
		var slot_center := slot.global_position + slot.size * 0.5
		var d := tile_center.distance_squared_to(slot_center)
		if d < best_dist:
			best_dist = d
			best_slot = slot_idx
	return best_slot


func _start_new_round() -> void:
	_clear_selection()
	_hide_success()

	# Fill solved mapping first.
	for tile_id in range(TILE_COUNT):
		var solved_slot := _tile_to_correct_slot[tile_id]
		_slot_to_tile[solved_slot] = tile_id

	_scramble_from_correct_state()
	_initial_slot_to_tile = _slot_to_tile.duplicate()
	_rebuild_tile_to_current_slot()
	_apply_tile_positions()


func _scramble_from_correct_state() -> void:
	var k := maxi(0, scramble_swaps)
	for _i in range(k):
		_swap_random_two_slots()

	if _is_solved():
		_swap_random_two_slots()
		if _is_solved():
			_force_swap_first_two_different()


func _swap_random_two_slots() -> void:
	var a := _rng.randi_range(0, TILE_COUNT - 1)
	var b := _rng.randi_range(0, TILE_COUNT - 1)
	while b == a:
		b = _rng.randi_range(0, TILE_COUNT - 1)
	_swap_slot_mapping(a, b)


func _force_swap_first_two_different() -> void:
	for i in range(TILE_COUNT):
		for j in range(i + 1, TILE_COUNT):
			if _slot_to_tile[i] != _slot_to_tile[j]:
				_swap_slot_mapping(i, j)
				return


func _swap_slot_mapping(a: int, b: int) -> void:
	var t := _slot_to_tile[a]
	_slot_to_tile[a] = _slot_to_tile[b]
	_slot_to_tile[b] = t


func _rebuild_tile_to_current_slot() -> void:
	for slot_idx in range(TILE_COUNT):
		var tile_id := _slot_to_tile[slot_idx]
		_tile_to_current_slot[tile_id] = slot_idx


func _on_slot_pressed(slot_idx: int) -> void:
	print("[Puzzle2UI] SLOT PRESSED: %d" % [slot_idx])
	if not _active:
		return

	# Step1: choose source slot.
	if _selected_slot == -1 and _selected_tile == -1:
		_selected_slot = slot_idx
		_refresh_tile_click_state()
		return

	# Step3: tile already chosen, place tile to destination slot.
	if _selected_tile != -1:
		_place_selected_tile_to_slot(slot_idx)
		_clear_selection()
		return

	# Only slot selected and no tile yet: update chosen slot.
	_selected_slot = slot_idx
	_refresh_tile_click_state()


func _on_tile_gui_input(event: InputEvent, tile_id: int) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb0 := event as InputEventMouseButton
		if mb0.pressed and mb0.button_index == MOUSE_BUTTON_RIGHT:
			_submit_global_right_click()
			return
	if _selected_slot == -1:
		return
	if not (event is InputEventMouseButton):
		return

	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		print("[Puzzle2UI] TILE PRESSED: %d" % [tile_id])
		_selected_tile = tile_id
		_refresh_tile_click_state()


func _on_slot_gui_input(event: InputEvent, _slot_idx: int) -> void:
	if not _active:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_submit_global_right_click()


func _place_selected_tile_to_slot(dst_slot: int) -> void:
	var t := _selected_tile
	if t < 0 or t >= TILE_COUNT:
		return
	if dst_slot < 0 or dst_slot >= TILE_COUNT:
		return

	var src_slot := _tile_to_current_slot[t]
	var u := _slot_to_tile[dst_slot]

	_slot_to_tile[dst_slot] = t
	_slot_to_tile[src_slot] = u

	_rebuild_tile_to_current_slot()
	_apply_tile_positions()


func _submit_global_right_click() -> void:
	if not _active:
		return

	if _is_solved():
		_show_success()
		completed.emit(true)
	else:
		_reset_to_initial_scramble()
		completed.emit(false)


func _reset_to_initial_scramble() -> void:
	if _initial_slot_to_tile.size() != TILE_COUNT:
		return
	_hide_success()
	_slot_to_tile = _initial_slot_to_tile.duplicate()
	_rebuild_tile_to_current_slot()
	_apply_tile_positions()
	_clear_selection()


func _on_submit_pressed() -> void:
	_submit_global_right_click()


func _on_reset_pressed() -> void:
	_reset_to_initial_scramble()


func _is_solved() -> bool:
	for tile_id in range(TILE_COUNT):
		if _tile_to_current_slot[tile_id] != _tile_to_correct_slot[tile_id]:
			return false
	return true


func _apply_tile_positions() -> void:
	if _tiles_root == null:
		return
	var inv: Transform2D = _tiles_root.get_global_transform_with_canvas().affine_inverse()
	for slot_idx in range(TILE_COUNT):
		var tile_id := _slot_to_tile[slot_idx]
		var slot := _slots[slot_idx]
		var tile := _tiles[tile_id]

		var slot_center_global := slot.global_position + slot.size * 0.5
		var slot_center_local: Vector2 = inv * slot_center_global
		tile.position = (slot_center_local - tile.size * 0.5).round()
		tile.z_index = 10


func _set_slot_highlight(slot_idx: int, highlighted: bool) -> void:
	if slot_idx < 0 or slot_idx >= _slots.size():
		return
	var slot := _slots[slot_idx]
	var base := _slot_base_modulates[slot_idx]
	slot.modulate = base * Color(1.25, 1.25, 0.75, 1.0) if highlighted else base


func _clear_selection() -> void:
	_selected_slot = -1
	_selected_tile = -1
	_refresh_tile_click_state()


func _show_success() -> void:
	if _success_layer != null:
		_success_layer.visible = true


func _hide_success() -> void:
	if _success_layer != null:
		_success_layer.visible = false


func _set_tip(text: String) -> void:
	if _tip_label != null:
		_tip_label.text = text


func _extract_suffix_index(node_name: StringName) -> int:
	var s := String(node_name)
	var split := s.split("_")
	if split.size() < 2:
		return -1
	var suffix := split[split.size() - 1]
	return int(suffix) if suffix.is_valid_int() else -1
