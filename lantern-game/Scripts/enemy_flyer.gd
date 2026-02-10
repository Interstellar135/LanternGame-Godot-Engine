extends CharacterBody2D


#基础配置
@export_group("Stats")
@export var move_speed = 80.0       # 普通飞行速度
@export var dash_speed = 400.0      # 冲刺攻击速度
@export var dash_duration = 0.4     # 冲刺持续时间
@export var attack_damage = 15
@export var max_hp = 20

@export_group("Floating")
@export var float_amplitude = 50.0  # 上下浮动的幅度 (像素)
@export var float_speed = 3.0       # 上下浮动的频率

# --- 动画名称 ---
const ANIM_IDLE   = "Idle"    # 上下浮动
const ANIM_MOVE   = "Move"    # 移动
const ANIM_ATTACK = "Attack"  # 前突/冲撞
const ANIM_HURT   = "Hurt"    # 受击
const ANIM_DEATH  = "Death"   # 死亡

# ==========================================
#               2. 状态定义
# ==========================================
enum State {
	IDLE,       # 原地悬浮
	PATROL,     # 左右巡逻悬浮
	CHASE,      # 追踪玩家
	PREPARE,    # 攻击前摇（锁定方向，停顿一下）
	DASH,       # 冲刺过程（高速移动）
	HURT,       #受击动画
	DEATH       #死亡动画
}

var current_state = State.IDLE
var current_hp = max_hp
var target_player = null
var home_position = Vector2.ZERO # 记录出生点，或者巡逻基准点
var time_offset = 0.0            # 用于正弦波随机化

# 冲刺相关
var dash_direction = Vector2.ZERO
var dash_timer = 0.0

#节点引用
@onready var sprite = $Sprite2D
@onready var anim = $AnimationPlayer
@onready var detection_area = $DetectionArea
@onready var attack_area = $AttackArea
@onready var hitbox = $Hitbox       # 专门用来撞人的区域
@onready var patrol_timer = $PatrolTimer
@onready var attack_cooldown = $AttackCooldown
@onready var health_bar = $ProgressBar # <-- 新增：获取血条节点

func _ready():
	current_hp = max_hp
	# 初始化血条
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	
	home_position = global_position
	time_offset = randf() * 100.0 # 让每个蝙蝠浮动的节奏不一样
	
	detection_area.body_entered.connect(_on_detection_entered)
	detection_area.body_exited.connect(_on_detection_exited)
	hitbox.body_entered.connect(_on_hitbox_entered) # 冲撞伤害判定
	patrol_timer.timeout.connect(_on_patrol_timer_timeout)
	
	start_patrol()

func _physics_process(delta):
	if current_state == State.DEATH: return

	match current_state:
		State.IDLE:
			# X轴不动，Y轴做正弦波浮动
			velocity.x = move_toward(velocity.x, 0, 10)
			_apply_floating_y(delta)
			
		State.PATROL:
			# X轴匀速移动，Y轴浮动
			# 简单的左右巡逻逻辑：
			# 这里简化为围绕出生点左右移动，或者你可以沿用之前的时间控制逻辑
			var patrol_dir = 1 if sprite.flip_h else -1 # 根据朝向决定方向
			velocity.x = patrol_dir * move_speed
			_apply_floating_y(delta)
			
		State.CHASE:
			if target_player:
				# 飞向玩家
				var direction = (target_player.global_position - global_position).normalized()
				velocity = direction * move_speed
				_update_facing(velocity.x)
				
				# 检查攻击距离
				if _can_attack():
					start_dash_attack()

		State.PREPARE:
			velocity = Vector2.ZERO # 前摇时停住不动，给玩家反应时间

		State.DASH:
			# 只有冲刺时才应用超高速
			velocity = dash_direction * dash_speed
			
			# 手动计算冲刺计时
			dash_timer -= delta
			if dash_timer <= 0:
				_end_dash()

		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)

	move_and_slide()

# ==========================================
#               4. 辅助逻辑
# ==========================================

# 模拟悬浮效果 (Sine Wave)
func _apply_floating_y(delta):
	# 利用 Time.get_ticks_msec 计算正弦波
	var time = Time.get_ticks_msec() / 1000.0 + time_offset
	# 计算出一个微小的垂直速度，而不是直接改position，这样物理碰撞更稳定
	var float_v = cos(time * float_speed) * float_amplitude
	velocity.y = float_v

func _update_facing(dir_x):
	if dir_x > 0: sprite.flip_h = false # 假设素材默认朝右
	elif dir_x < 0: sprite.flip_h = true

func _can_attack():
	# 1. 有目标 2. 在攻击范围内 3. 冷却好了
	if not target_player: return false
	if not attack_cooldown.is_stopped(): return false
	
	# 手动检测是否在攻击区域内
	var bodies = attack_area.get_overlapping_bodies()
	return target_player in bodies

# ==========================================
#               5. 核心：冲刺攻击逻辑
# ==========================================
func start_dash_attack():
	change_state(State.PREPARE)
	
	# 1. 播放攻击前摇动画
	anim.play(ANIM_ATTACK)
	
	# 2. 锁定玩家当前位置为冲刺方向
	dash_direction = (target_player.global_position - global_position).normalized()
	_update_facing(dash_direction.x)
	
	# 3. 停顿一小会 (前摇时间)，比如 0.3 秒
	# 可以在动画里设置，或者用代码硬等
	await get_tree().create_timer(0.3).timeout
	
	if current_state == State.PREPARE: # 确保没被打断
		change_state(State.DASH)

func _end_dash():
	velocity = Vector2.ZERO
	attack_cooldown.start(2.0) # 开始冷却
	if target_player:
		change_state(State.CHASE)
	else:
		start_patrol()

# 处理冲撞伤害 (Hitbox)
func _on_hitbox_entered(body):
	# 只有在冲刺状态下，撞到人才有伤害
	# (或者你可以设定只要碰到就有伤害，看游戏设计)
	if current_state == State.DASH and body.is_in_group("player"):
		print("冲撞命中玩家！")
		if body.has_method("take_damage"):
			body.take_damage(attack_damage)
			# 撞到人后可以选择反弹或者穿过去，这里选择反弹一点点
			# velocity = -velocity * 0.5 

# ==========================================
#               6. 状态机与生命周期
# ==========================================
func change_state(new_state):
	if current_state == State.DEATH: return
	
	current_state = new_state
	
	match current_state:
		State.IDLE:
			anim.play(ANIM_IDLE)
		State.PATROL:
			anim.play(ANIM_MOVE)
		State.CHASE:
			anim.play(ANIM_MOVE)
		State.PREPARE:
			# 已经在 start_dash_attack 里播了动画，这里可以不写，或者播一个特定的 Warning 动画
			pass
		State.DASH:
			# 保持攻击动画，或者如果美术有专门的“飞行中”特效帧
			dash_timer = dash_duration
		State.HURT:
			anim.play(ANIM_HURT)
			await anim.animation_finished
			if current_state == State.HURT:
				if target_player: change_state(State.CHASE)
				else: start_patrol()
		State.DEATH:
			anim.play(ANIM_DEATH)
			velocity = Vector2.ZERO
			# 重力开启，让尸体掉下去 (可选)
			# gravity = 980 
			await anim.animation_finished
			queue_free()

func take_damage(amount):
	if current_state == State.DEATH: return
	current_hp -= amount
	 # 更新血条
	health_bar.value = current_hp
	health_bar.visible = true # 受伤显示血条
	
	if current_hp <= 0:
		change_state(State.DEATH)
		health_bar.visible = false # 死了就藏起来
	else:
		# 受伤击退：向后退一点
		var knockback_dir = Vector2.RIGHT if sprite.flip_h else Vector2.LEFT
		velocity = knockback_dir * 150
		change_state(State.HURT)

# ==========================================
#               7. 巡逻逻辑
# ==========================================
func start_patrol():
	change_state(State.IDLE)
	patrol_timer.start(2.0) # 休息2秒

func _on_patrol_timer_timeout():
	if current_state == State.IDLE:
		change_state(State.PATROL)
		# 随机掉头
		if randf() > 0.5: sprite.flip_h = !sprite.flip_h
		patrol_timer.start(3.0) # 飞3秒
	elif current_state == State.PATROL:
		change_state(State.IDLE)
		patrol_timer.start(2.0)

# ==========================================
#               8. 侦测信号
# ==========================================
func _on_detection_entered(body):
	if body.is_in_group("player"):
		target_player = body
		change_state(State.CHASE)

func _on_detection_exited(body):
	if body == target_player:
		target_player = null
		start_patrol()
