# QTEManager.gd - QTE逻辑核心（纯UI层，无游戏逻辑）
extends Node

# ===== 信号（与Player解耦）=====
signal qte_success(sequence: Array)
signal qte_failed
signal qte_ended
signal qte_started

# ===== 暴露参数 =====
@export var time_limit: float = 3.0  # 倒计时总时长
@export var fade_duration: float = 0.2  # 淡入淡出时长

# ===== 内部状态 =====
var current_sequence: Array = []
var input_index: int = 0
var is_active: bool = false
var timer: Timer
var _original_modulate: Color

# ===== 节点引用 =====
@onready var panel = get_parent() as Control  # QTEPanel
@onready var key_prompts = [
	panel.get_node("KeyPromptContainer/Key1"),
	panel.get_node("KeyPromptContainer/Key2"),
	panel.get_node("KeyPromptContainer/Key3")
]
@onready var timer_bar = panel.get_node("TimerBar") as ProgressBar

func _ready():
	# 初始化
	_original_modulate = panel.modulate
	panel.hide()
	panel.modulate.a = 0
	
	# 创建倒计时Timer
	timer = Timer.new()
	timer.one_shot = false
	timer.wait_time = 0.05
	timer.timeout.connect(_on_timer_tick)
	add_child(timer)

# ===== 启动QTE（由Player调用）=====
func start_at_position(screen_pos: Vector2, sequence: Array):
	if is_active: return
	
	current_sequence = sequence
	input_index = 0
	is_active = true
	
	# 1. 精准定位QTEPanel（以法阵中心为Panel中心）
	panel.rect_position = screen_pos - panel.rect_size / 2
	
	# 2. 更新按键图标（按美术资源路径加载）
	for i in range(min(3, key_prompts.size())):
		if i < current_sequence.size():
			var key_name = current_sequence[i]
			# 路径示例: "res://assets/qte/keys/q.png"
			var texture_path = "res://Assets/qte/keys/" + key_name + ".png"
			if ResourceLoader.exists(texture_path):
				key_prompts[i].texture = load(texture_path)
			key_prompts[i].modulate = Color.WHITE  # 重置颜色
			key_prompts[i].show()
		else:
			key_prompts[i].hide()
	
	# 3. 重置倒计时条
	if timer_bar:
		timer_bar.max_value = time_limit
		timer_bar.value = time_limit
	
	# 4. 淡入动画
	panel.modulate = _original_modulate
	panel.modulate.a = 0
	panel.show()
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, fade_duration).set_ease(Tween.EASE_OUT)
	
	# 5. 启动倒计时
	timer.start()
	emit_signal("qte_started")

# ===== 倒计时逻辑 =====
func _on_timer_tick():
	if not is_active: return
	if timer_bar:
		timer_bar.value = max(0, timer_bar.value - timer.wait_time)
		if timer_bar.value <= 0:
			_fail_qte()

# ===== 全局输入监听（仅活跃时处理）=====
func _input(event):
	if not is_active or not event is InputEventKey: return
	
	# 获取按键名（需Input Map配置qte_key_*）
	var pressed_key = _get_mapped_key(event)
	if pressed_key == "":
		return
	
	# 检查是否匹配当前序列
	if pressed_key == current_sequence[input_index]:
		_highlight_key(input_index, true)
		input_index += 1
		if input_index >= current_sequence.size():
			_success_qte()
	else:
		_highlight_key(input_index, false)
		_fail_qte()

# ===== 结果处理 =====
func _success_qte():
	_cleanup()
	emit_signal("qte_success", current_sequence.duplicate())

func _fail_qte():
	_cleanup()
	emit_signal("qte_failed")

func _cleanup():
	if not is_active: return
	is_active = false
	timer.stop()
	
	# 淡出动画
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(func():
		panel.hide()
		emit_signal("qte_ended")
	)

# ===== 辅助函数 =====
func _highlight_key(index: int, success: bool):
	if index < key_prompts.size() and key_prompts[index].is_visible_in_tree():
		key_prompts[index].modulate = Color.GREEN if success else Color.RED

func _get_mapped_key(event: InputEvent) -> String:
	# 检查Input Map中预设的qte_key_*动作
	var key_actions = ["qte_key_l", "qte_key_i", "qte_key_n", "qte_key_k"]
	for action in key_actions:
		if event.is_action_pressed(action):
			return action.split("_")[-1]  # 返回 "l", "i" 等
	return ""

# ===== 外部控制（供Player强制结束）=====
func force_end():
	if is_active:
		_cleanup()
