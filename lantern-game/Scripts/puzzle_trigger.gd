extends Area2D

signal interact_requested # 发送信号给关卡脚本

var can_interact = false
var is_active = false # 只有怪打完了才变成 true

@onready var prompt_label = $Label
@onready var sprite = $Sprite2D

func _ready():
	prompt_label.visible = false
	sprite.modulate = Color(0.5, 0.5, 0.5) # 默认灰色(不可用)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

# 由关卡脚本调用，开启交互功能
func activate():
	is_active = true
	sprite.modulate = Color.WHITE # 变亮
	# 播放发光特效等...

func _on_body_entered(body):
	if is_active and body.is_in_group("player"):
		can_interact = true
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		can_interact = false
		prompt_label.visible = false

func _unhandled_input(event):
	if can_interact and event.is_action_pressed("interact"): # 记得在输入映射里设 E 键为 interact
		interact_requested.emit()
