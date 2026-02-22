@tool
extends "puzzle.gd"

# 在文件头部定义信号
signal solved

## 是否在编辑器中启用编辑模式（NOTE: 需要关闭编辑模式才能保存编辑结果）
@export var edit_mode := false:
	set(v):
		edit_mode = v
		if not Engine.is_editor_hint():
			return

		if edit_mode:
			for btn in %tiles_layer.get_children():
				btn.global_position = tile_initial_positions.get(btn.name, Vector2.ZERO)
		else:
			if not is_node_ready():
				return

			for btn : TextureButton in %tiles_layer.get_children():
				if btn.global_position.is_zero_approx():
					continue
				tile_initial_positions.set(btn.name, btn.global_position)
				btn.global_position = Vector2.ZERO

@export_storage var tile_initial_positions :Dictionary[StringName, Vector2] = {}

var _selected_tile: TextureButton = null:
	set(v):
		if _selected_tile:
			_selected_tile.self_modulate = Color.WHITE
		_selected_tile = v
		if _selected_tile:
			_selected_tile.self_modulate = Color.AQUA

var _selected_slot: Button = null:
	set(v):
		_selected_slot = v
		for slot in %slots.get_children():
			slot = slot as Button
			slot.set_pressed_no_signal(slot == _selected_slot)


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	for btn in %tiles_layer.get_children():
		btn = btn as TextureButton
		var mask := BitMap.new()
		mask.create_from_image_alpha(btn.texture_normal.get_image(), 0.01)
		btn.texture_click_mask = mask
		btn.pressed.connect(_on_tile_pressed.bind(btn))
		btn.global_position = tile_initial_positions.get(btn.name, Vector2.ZERO)

	for btn in %slots.get_children():
		btn = btn as Button
		btn.toggled.connect(_on_slot_toggled.bind(btn))

	# TEST
	#await get_tree().create_timer(3.0).timeout
	#var tween := create_tween()
	#tween.set_parallel()
	#for btn in %tiles_layer.get_children():
		#tween.tween_property(btn, ^"global_position", Vector2.ZERO, 0.5).set_ease(Tween.EASE_OUT)


func is_solved() -> bool:
	return %tiles_layer.get_children().all(func(btn: TextureButton)-> bool: return btn.global_position.is_zero_approx())


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if is_instance_valid(mb):
		if mb.is_echo() or mb.button_index != MOUSE_BUTTON_RIGHT or not mb.is_pressed():
			return

		if _selected_tile and _selected_slot:
			get_tree().root.set_input_as_handled()

			if _selected_tile.name == _selected_slot.name:
				_selected_tile.disabled = true
				_selected_slot.disabled = true
				# 2. 播放归位动画
				var tween = create_tween()
				tween.tween_property(_selected_tile, ^"global_position", Vector2.ZERO, 0.5).set_ease(Tween.EASE_OUT)
				
				# 3. [关键] 动画结束后检查胜利
				tween.tween_callback(func():
					if is_solved():
						print("✅ Puzzle_2 全部归位！发出 solved 信号...")
						# ❌ 这一行删掉！不要在这里 emit 信号！
						# solved.emit()
				)
				
				_selected_tile = null
				_selected_slot = null
			else:
				_selected_tile = null
				_selected_slot = null


func finish_async() -> void:
	%sucess_2.show()
	await get_tree().create_timer(1.0).timeout


func _on_tile_pressed(btn: TextureButton) -> void:
	_selected_tile = btn


func _on_slot_toggled(toggle_on: bool, btn: Button) -> void:
	if toggle_on:
		_selected_slot = btn
	else:
		_selected_slot = null
		
# [新增] 重置函数，供 PuzzleManager 调用
func reset_to_initial() -> void:
	print("正在重置 Puzzle 2...")
	
	# 1. 清除当前选中的状态
	_selected_tile = null
	_selected_slot = null
	
	# 2. 停止所有正在运行的动画 (防止重置时还有方块在飘)
	# 遍历所有 Tile，如果有 Tween 正在跑，虽然没法直接杀特定的 tween，
	# 但我们可以直接重置位置，覆盖掉动画结果。
	
	# 3. 遍历所有方块 (Tiles)
	for btn in %tiles_layer.get_children():
		btn = btn as TextureButton
		
		# 恢复点击交互 (防止之前匹配成功后被 disable 了)
		btn.disabled = false
		btn.self_modulate = Color.WHITE # 恢复颜色
		
		# [关键] 归位到初始坐标
		# 既然你本来就有 tile_initial_positions 字典，直接读它！
		if tile_initial_positions.has(btn.name):
			# 这里可以直接瞬移，不用播动画，重置要快
			btn.global_position = tile_initial_positions[btn.name]
			
	# 4. 遍历所有插槽 (Slots)
	for slot in %slots.get_children():
		slot = slot as Button
		# 恢复交互
		slot.disabled = false
		# 取消按下状态
		slot.set_pressed_no_signal(false)

	print("Puzzle 2 重置完成")
