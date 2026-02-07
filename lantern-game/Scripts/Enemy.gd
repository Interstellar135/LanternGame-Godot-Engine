extends CharacterBody2D

enum State { IDLE, ATTACK }
var current_state = State.IDLE

@export var move_speed: float = 120.0
@export var attack_range: float = 50.0  # 贴脸攻击距离
@export var patrol_radius: float = 100.0 # IDLE徘徊范围

var player = null
var start_pos: Vector2
var target_pos: Vector2
var attack_area: Area2D
var cooldown_timer: Timer

func _ready():
	start_pos = global_position
	target_pos = start_pos
	attack_area = $AttackArea
	cooldown_timer = $CooldownTimer
	
	# 连接攻击范围信号（核心！）
	attack_area.area_entered.connect(_on_attack_area_entered)
	attack_area.area_exited.connect(_on_attack_area_exited)
	
	# 初始化IDLE目标点
	_set_new_patrol_target()

func _on_attack_area_entered(area):
	if area.is_in_group("player") and current_state != State.ATTACK:
		player = area
		current_state = State.ATTACK
		print("⚔️ 进入ATTACK状态！")

func _on_attack_area_exited(area):
	if area.is_in_group("player") and area == player and current_state == State.ATTACK:
		player = null
		current_state = State.IDLE
		_set_new_patrol_target()
		print("🚶 切回IDLE状态")

func _set_new_patrol_target():
	# 在出生点周围生成随机目标点
	var rand_offset = Vector2(randf_range(-1, 1), 0).normalized() * randf_range(0, patrol_radius)
	target_pos = start_pos + rand_offset

func _physics_process(delta):
	match current_state:
		State.IDLE:
			_handle_idle(delta)
		State.ATTACK:
			_handle_attack(delta)

# === IDLE状态：小范围徘徊 ===
func _handle_idle(delta):
	# 向目标点移动
	var dir = (target_pos - global_position).normalized()
	velocity.x = dir.x * move_speed
	
	# 翻转Sprite朝向
	$Sprite2D.flip_h = dir.x < 0
	
	# 到达目标点后重置
	if global_position.distance_to(target_pos) < 10:
		await get_tree().create_timer(1.0).timeout  # 等待1秒
		_set_new_patrol_target()
	
	move_and_slide()

# === ATTACK状态：冲向玩家+攻击 ===
func _handle_attack(delta):
	if not player or not is_instance_valid(player):
		current_state = State.IDLE
		return
	
	# 1. 向玩家移动
	var to_player = (player.global_position - global_position).normalized()
	velocity.x = to_player.x * move_speed
	$Sprite2D.flip_h = to_player.x < 0
	
	# 2. 距离≤攻击范围 且 冷却结束 → 攻击！
	if global_position.distance_to(player.global_position) <= attack_range:
		if cooldown_timer.is_stopped():
			_perform_attack()
	
	move_and_slide()

# === 攻击逻辑（替换为你的伤害系统）===
func _perform_attack():
	print("💥 敌人攻击！造成10点伤害")
	# 以下为示例（按需修改）：
	# player.take_damage(10)
	# $AnimationPlayer.play("attack")  # 有动画时启用
	# $AudioStreamPlayer.play()      # 播放音效
	
	# 重置攻击冷却
	cooldown_timer.start()
