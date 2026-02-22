extends Node2D

signal qte_success
signal qte_failed

const QTE_KEYS = {"L": "qte_l", "I": "qte_i", "N": "qte_n", "K": "qte_k"}
var keys_list = ["L", "I", "N", "K"]
var current_sequence = []
var input_index = 0
var is_active = false

# --- 布局参数 ---
var layout_radius = 83.0 
var lantern_offset = Vector2.ZERO 

@onready var magic_circle = $MagicCircleSprite
@onready var letters_root = $LettersRoot
@onready var labels = [$LettersRoot/Label1, $LettersRoot/Label2, $LettersRoot/Label3]
@onready var arrows = [$LettersRoot/Arrow1, $LettersRoot/Arrow2]

func _ready():
	visible = false
	set_process_unhandled_input(false)
	set_process(false) # [新增] 默认不开启每帧处理，节省性能
	for arrow in arrows: arrow.visible = false

# [新增] 摩天轮核心逻辑
func _process(delta):
	# 1. 让字母容器(LettersRoot) 跟着法阵转 (公转)
	# 这样位置会变，箭头也会跟着转动指向正确方向
	letters_root.rotation = magic_circle.rotation
	
	# 2. 强制锁死 Label 的角度 (自转抵消)
	# 因为我们在 start_qte 里设置了中心轴点，所以它会原地转正，不会乱甩
	for lbl in labels:
		lbl.rotation = -letters_root.rotation

func start_qte(offset_pos: Vector2, is_facing_right: bool):
	if is_active: return
	is_active = true
	visible = true
	input_index = 0
	current_sequence.clear()
	
	# --- [🔥核心修复🔥] 强制重置旋转角度 ---
	# 必须先归零，这样后续的 Position 计算和 look_at 才会基于“正”的坐标系
	magic_circle.rotation = 0
	letters_root.rotation = 0 
	
	# --- 1. 定位逻辑 ---
	if is_facing_right:
		position = offset_pos 
		scale.x = 1 
	else:
		position = Vector2(-offset_pos.x, offset_pos.y) 
		scale.x = 1 

	Engine.time_scale = 0.05 

	# --- 3. 生成字母 (有关键修改) ---
	for i in range(3):
		var char_str = keys_list.pick_random()
		current_sequence.append(char_str)
		
		var lbl = labels[i] # 方便引用
		lbl.text = char_str
		lbl.modulate = Color.WHITE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# [🔥关键修改🔥] 修正旋转轴心，防止旋转时甩飞
		lbl.reset_size() # 先让 Label 根据字号自动调整大小
		lbl.pivot_offset = lbl.size / 2 # 把轴心移到正中间

	# --- 4. 正三角布局计算 ---
	var angles = [-90, 30, 150] 
	var points = []
	
	for i in range(3):
		var rad = deg_to_rad(angles[i])
		var pos = Vector2(cos(rad), sin(rad)) * layout_radius
		labels[i].position = pos - labels[i].size / 2 
		points.append(pos)

	# --- 5. 放置箭头 ---
		# --- 5. 放置箭头 ---
	# [新增] 这里先把箭头颜色重置回来！
	for arrow in arrows:
		arrow.modulate = Color.WHITE  # <--- 加这一行
	_place_arrow(arrows[0], points[0], points[1])
	_place_arrow(arrows[1], points[1], points[2])

	# --- 6. 展开动画 ---
	magic_circle.scale = Vector2.ZERO
	magic_circle.rotation_degrees = 0
	letters_root.scale = Vector2.ZERO
	
	# 这里 letters_root 和 magic_circle 是分开缩放的，满足你的需求
	var tween = create_tween().set_parallel(true)
	tween.tween_property(magic_circle, "scale", Vector2(1.1, 1.1), 0.15).set_trans(Tween.TRANS_BACK)
	tween.tween_property(letters_root, "scale", Vector2(1, 1), 0.15).set_trans(Tween.TRANS_BACK)
	
	# 让法阵一直慢速旋转
	var rotate_tween = create_tween().set_loops()
	rotate_tween.tween_property(magic_circle, "rotation_degrees", 360, 5.0).as_relative()

	# [新增] 开启同步旋转
	set_process(true)
	set_process_unhandled_input(true)

func _place_arrow(arrow, p1, p2):
	arrow.visible = true
	arrow.position = (p1 + p2) / 2
	arrow.look_at(to_global(p2)) 

func stop_qte(success: bool):
	is_active = false
	set_process_unhandled_input(false)
	set_process(false) # [新增] 停止旋转同步
	Engine.time_scale = 1.0 
	
	if success:
		emit_signal("qte_success")
		for l in labels: l.modulate = Color(0.5, 3, 0.5) 
		for a in arrows: a.modulate = Color.GREEN
	else:
		emit_signal("qte_failed")
		for l in labels: l.modulate = Color.RED
	
	await get_tree().create_timer(0.3).timeout
	visible = false

func _unhandled_input(event):
	if not is_active: return
	if event is InputEventKey and event.pressed and not event.echo:
		var is_qte_key = false
		for k in QTE_KEYS.values():
			if event.is_action_pressed(k):
				is_qte_key = true
				break
		if not is_qte_key: return
		
		var expected_char = current_sequence[input_index]
		if event.is_action_pressed(QTE_KEYS[expected_char]):
			labels[input_index].modulate = Color(2, 2, 0) 
			input_index += 1
			if input_index >= 3: stop_qte(true)
		else:
			stop_qte(false)
			
