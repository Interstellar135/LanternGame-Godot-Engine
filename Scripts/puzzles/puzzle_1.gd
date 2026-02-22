extends "puzzle.gd"

@export var rings :Array[TextureButton]


func _ready() -> void:
	for btn in rings:
		var mask := BitMap.new()
		mask.create_from_image_alpha(btn.texture_normal.get_image(), 0.01)
		btn.texture_click_mask = mask
		btn.pressed.connect(_on_btn_pressed.bind(btn))
		btn.rotation_degrees = fmod(90 * randi_range(1, 3), 360)


func is_solved() -> bool:
	return rings.all(func(btn: TextureButton)->bool: return is_zero_approx(btn.rotation_degrees))


func finish_async() -> void:
	%sucess_1.show()
	await get_tree().create_timer(1.0).timeout


func _on_btn_pressed(btn: TextureButton) -> void:
	btn.rotation_degrees += 90
	btn.rotation_degrees = fmod(btn.rotation_degrees, 360.0)
	
# [新增] 重置函数，供 PuzzleManager 调用
func reset_to_initial() -> void:
	print("正在重置 Puzzle 1 (旋转拼图)...")
	
	# 遍历所有圆环，重新随机打乱角度
	# 逻辑和 _ready() 里的一样，确保是 90 度的倍数，且不直接等于 0 (已解开状态)
	for btn in rings:
		# 重新随机旋转 1~3 次 90度 (即 90, 180, 270)
		btn.rotation_degrees = fmod(90 * randi_range(1, 3), 360)
		
		# 确保按钮可用 (万一有点了就禁用的逻辑)
		btn.disabled = false
		
	# 隐藏胜利 UI (如果有的话)
	if has_node("%sucess_1"):
		%sucess_1.hide()

	print("Puzzle 1 重置完成")
