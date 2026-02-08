extends Node

signal completed(success: bool)

@export var step_degrees: int = 45
@export var target_state: PackedInt32Array = PackedInt32Array([0, 0, 0])

const RING_COUNT := 3

var step_count: int = 8
var ring_state: PackedInt32Array = PackedInt32Array([0, 0, 0])

var _rings: Array[CanvasItem] = []


func _ready() -> void:
	_init_step_count()
	_collect_rings()
	if _rings.size() != RING_COUNT:
		return
	_validate_and_normalize_target_state()
	_connect_ring_inputs()
	reset_to_initial()


func _init_step_count() -> void:
	if step_degrees <= 0 or 360 % step_degrees != 0:
		push_error("step_degrees must be a positive divisor of 360. Fallback to 45.")
		step_degrees = 45
	step_count = 360 / step_degrees
	if step_count < 2:
		push_error("step_count must be >= 2 to guarantee all rings start incorrect. Fallback to 45.")
		step_degrees = 45
		step_count = 360 / step_degrees


func _collect_rings() -> void:
	_rings.clear()

	var rings_node := get_node_or_null("Rings")
	if rings_node == null:
		push_error("Missing node: Rings")
		return

	var expected_names := PackedStringArray(["Ring_00", "Ring_01", "Ring_02"])
	var fallback_names := PackedStringArray(["Ring_Outer", "Ring_Middle", "Ring_Inner"])
	var names_to_use := expected_names
	for ring_name in expected_names:
		if rings_node.get_node_or_null(ring_name) == null:
			names_to_use = fallback_names
			break

	for ring_name in names_to_use:
		var ring := rings_node.get_node_or_null(ring_name)
		if ring == null:
			push_error("Missing node: Rings/%s" % ring_name)
			return
		if not (ring is Control or ring is Sprite2D):
			push_error("Rings/%s must be Control or Sprite2D" % ring_name)
			return
		_rings.append(ring as CanvasItem)


func _validate_and_normalize_target_state() -> void:
	if target_state.size() != RING_COUNT:
		var fixed := PackedInt32Array()
		fixed.resize(RING_COUNT)
		for i in range(RING_COUNT):
			fixed[i] = 0
		target_state = fixed

	for i in range(RING_COUNT):
		var value := target_state[i]
		var normalized := posmod(value, step_count)
		target_state[i] = normalized


func _connect_ring_inputs() -> void:
	for i in range(_rings.size()):
		var ring := _rings[i]
		if ring is Sprite2D:
			var sprite := ring as Sprite2D
			if not sprite.input_event.is_connected(_on_ring_input_event.bind(i)):
				sprite.input_event.connect(_on_ring_input_event.bind(i))
		elif ring is Control:
			var ctrl := ring as Control
			if not ctrl.gui_input.is_connected(_on_ring_gui_input.bind(i)):
				ctrl.gui_input.connect(_on_ring_gui_input.bind(i))


func _on_ring_gui_input(event: InputEvent, ring_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_advance_ring(ring_index)


func _on_ring_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, ring_index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_advance_ring(ring_index)


func _advance_ring(ring_index: int) -> void:
	if ring_index < 0 or ring_index >= RING_COUNT:
		return
	ring_state[ring_index] = (ring_state[ring_index] + 1) % step_count
	_apply_visual()


func _apply_visual() -> void:
	for i in range(min(RING_COUNT, _rings.size())):
		_rings[i].rotation_degrees = float(ring_state[i] * step_degrees)


func is_solved() -> bool:
	for i in range(RING_COUNT):
		if ring_state[i] != target_state[i]:
			return false
	return true


func reset_to_initial() -> void:
	if ring_state.size() != RING_COUNT:
		ring_state.resize(RING_COUNT)

	for i in range(RING_COUNT):
		# offset fixed to 1 so every ring is guaranteed incorrect at start/reset.
		var offset_i := 1
		ring_state[i] = (target_state[i] + offset_i) % step_count

	_apply_visual()

