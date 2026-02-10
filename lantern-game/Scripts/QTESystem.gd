extends Node2D

signal qte_success
signal qte_failed

const QTE_KEYS = {"L": "qte_l", "I": "qte_i", "N": "qte_n", "K": "qte_k"}
var keys_list = ["L", "I", "N", "K"]
var current_sequence = []
var input_index = 0
var is_active = false

# --- 布局参数 ---
var layout_radius = 50.0  # 半径：根据你的法阵图片大小调整！(比如法阵宽150，这里设50)
var lantern_offset = Vector2.ZERO # 记录提灯相对于主角中心的偏移量

@onready var magic_circle = $MagicCircleSprite
@onready var letters_root = $LettersRoot
@onready var labels = [$LettersRoot/Label1, $LettersRoot/Label2, $LettersRoot/Label3]
@onready var arrows = [$LettersRoot/Arrow1, $LettersRoot/Arrow2]

func _ready():
	visible = false
	set_process_unhandled_input(false)
	for arrow in arrows: arrow.visible = false

# 启动QTE (接收提灯的位置偏移，以及主角是否朝右)
func start_qte(offset_pos: Vector2, is_facing_right: bool):
	if is_active: return
	is_active = true
	visible = true
	input_index = 0
	current_sequence.clear()
	
	# --- 1. 定位逻辑 (关键) ---
	# 我们根据主角的朝向，决定法阵出现在左手边还是右手边
	if is_facing_right:
		position = offset_pos # 在右侧提灯处
		# 确保文字不镜像
		scale.x = 1 
	else:
		position = Vector2(-offset_pos.x, offset_pos.y) # 镜像到左侧
		# 如果父节点(Player) flip了，这里可能不需要特殊处理
		# 但如果 Player 是通过 scale.x = -1 翻转的，这里需要修正 scale.x = -1 才能让字变正？
		# 为了保险，我们假设 Player 是通过 flip_h 翻转 sprite，坐标系没变。
		scale.x = 1 

	# --- 2. 子弹时间 ---
	Engine.time_scale = 0.05 # 极慢速度，强化停顿感

	# --- 3. 生成字母 ---
	for i in range(3):
		var char_str = keys_list.pick_random()
		current_sequence.append(char_str)
		labels[i].text = char_str
		labels[i].modulate = Color.WHITE
		labels[i].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labels[i].vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# --- 4. 正三角布局计算 ---
	# 0度是右边。我们将三个点分布在：90度(下), 210度(左上), 330度(右上) -> 这是一个倒三角
	# 或者：-90度(上), 30度(右下), 150度(左下) -> 这是一个正三角
	var angles = [-90, 30, 150] 
	var points = []
	
	for i in range(3):
		var rad = deg_to_rad(angles[i])
		var pos = Vector2(cos(rad), sin(rad)) * layout_radius
		labels[i].position = pos - labels[i].size / 2 # 居中修正
		points.append(pos)

	# --- 5. 放置箭头 ---
	_place_arrow(arrows[0], points[0], points[1])
	_place_arrow(arrows[1], points[1], points[2])

	# --- 6. 展开动画 ---
	magic_circle.scale = Vector2.ZERO
	magic_circle.rotation_degrees = 0
	letters_root.scale = Vector2.ZERO
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(magic_circle, "scale", Vector2(1, 1), 0.15).set_trans(Tween.TRANS_BACK)
	tween.tween_property(letters_root, "scale", Vector2(1, 1), 0.15).set_trans(Tween.TRANS_BACK)
	# 让法阵一直慢速旋转
	var rotate_tween = create_tween().set_loops()
	rotate_tween.tween_property(magic_circle, "rotation_degrees", 360, 5.0).as_relative()

	set_process_unhandled_input(true)

func _place_arrow(arrow, p1, p2):
	arrow.visible = true
	arrow.position = (p1 + p2) / 2
	arrow.look_at(to_global(p2)) # 指向下一个点
	# 注意：如果箭头图片默认是向右的，这里就对了。如果是向上的，需要 + PI/2

func stop_qte(success: bool):
	is_active = false
	set_process_unhandled_input(false)
	Engine.time_scale = 1.0 # 恢复时间
	
	if success:
		emit_signal("qte_success")
		# 成功特效：全部高亮
		for l in labels: l.modulate = Color(0.5, 3, 0.5) # 超亮绿
		for a in arrows: a.modulate = Color.GREEN
		# 可以在这里加一个 tween 让法阵放大消散
	else:
		emit_signal("qte_failed")
		for l in labels: l.modulate = Color.RED
	
	await get_tree().create_timer(0.3).timeout
	visible = false

# 输入处理逻辑保持不变...
func _unhandled_input(event):
	if not is_active: return
	# ... (同上个版本) ...
	if event is InputEventKey and event.pressed and not event.echo:
		var is_qte_key = false
		for k in QTE_KEYS.values():
			if event.is_action_pressed(k):
				is_qte_key = true
				break
		if not is_qte_key: return
		
		var expected_char = current_sequence[input_index]
		if event.is_action_pressed(QTE_KEYS[expected_char]):
			labels[input_index].modulate = Color(2, 2, 0) # 高亮黄
			input_index += 1
			if input_index >= 3: stop_qte(true)
		else:
			stop_qte(false)
