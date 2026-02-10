extends CharacterBody2D

#基础配置
@export_group("Stats")
@export var move_speed = 50.0       # 爬行速度通常比较慢
@export var gravity = 980.0
@export var max_hp = 30
@export var attack_damage = 10
@export var attack_cooldown = 2.0   # 攻击间隔

@export_group("Assets")
@export var projectile_scene: PackedScene # 拖入你的射线/子弹场景

# --- 动画名称配置 (请根据美术资源修改) ---
const ANIM_IDLE   = "Idle"    # 基础待机
const ANIM_WALK   = "Walk"    # 巡视/爬行
const ANIM_ATTACK = "Attack"  # 发射射线
const ANIM_HURT   = "Hurt"    # 受击
const ANIM_DEATH  = "Death"   # 死亡

# ==========================================
#               2. 状态机定义
# ==========================================
enum State {
	IDLE,       # 发呆/休息
	PATROL,     # 巡视移动
	CHASE,      # 发现玩家(追击/调整位置)
	ATTACK,     # 攻击前摇/发射
	HURT,       # 受击硬直
	DEATH       # 死亡
}

var current_state = State.IDLE
var current_hp = max_hp
var target_player = null
var facing_right = true     # 默认朝向
var patrol_dir = 1          # 1:右, -1:左

#节点引用
@onready var sprite = $Sprite2D
@onready var anim = $AnimationPlayer
@onready var muzzle_pos = $MuzzlePos        # 发射口
@onready var patrol_timer = $PatrolTimer
@onready var attack_timer = $AttackTimer
@onready var detection_area = $DetectionArea
@onready var attack_area = $AttackArea
@onready var health_bar = $ProgressBar # <-- 新增：获取血条节点

func _ready():
	current_hp = max_hp
	# 初始化血条
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	
	# 连接信号
	detection_area.body_entered.connect(_on_detection_entered)
	detection_area.body_exited.connect(_on_detection_exited)
	attack_area.body_entered.connect(_on_attack_range_entered)
	attack_area.body_exited.connect(_on_attack_range_exited)
	
	attack_timer.wait_time = attack_cooldown
	attack_timer.one_shot = true
	
	patrol_timer.timeout.connect(_on_patrol_timer_timeout)
	
	# 开始行为
	start_patrol_idle()

func _physics_process(delta):
	# 应用重力
	if not is_on_floor():
		velocity.y += gravity * delta
	
	if current_state == State.DEATH: return

	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, move_speed * delta)
			
		State.PATROL:
			velocity.x = patrol_dir * move_speed
			_update_facing(patrol_dir)
			
		State.CHASE:
			if target_player:
				var dir = (target_player.global_position - global_position).normalized().x
				velocity.x = dir * move_speed
				_update_facing(dir)
			
		State.ATTACK, State.HURT:
			velocity.x = 0 # 攻击和受伤时不动

	move_and_slide()

#状态切换逻辑
func change_state(new_state):
	if current_state == State.DEATH: return
	if current_state == new_state and new_state != State.HURT: return
	
	current_state = new_state
	
	match current_state:
		State.IDLE:
			anim.play(ANIM_IDLE)
			
		State.PATROL:
			anim.play(ANIM_WALK)
			
		State.CHASE:
			anim.play(ANIM_WALK) # 追击复用爬行动画
			
		State.ATTACK:
			velocity.x = 0
			anim.play(ANIM_ATTACK)
			# 这里用 await 等待动画播完，
			# 但真正的子弹生成建议用 Animation Call Method 触发 spawn_projectile
			await anim.animation_finished 
			
			# 攻击结束后的决策
			if current_state == State.ATTACK:
				attack_timer.start() # 开始冷却
				if target_player and overlaps_attack_area():
					# 如果还在攻击范围内，且冷却没好，先切回 IDLE 等冷却
					change_state(State.IDLE)
				elif target_player:
					change_state(State.CHASE)
				else:
					start_patrol_idle()

		State.HURT:
			anim.play(ANIM_HURT)
			await anim.animation_finished
			# 恢复逻辑
			if current_state == State.HURT:
				if target_player:
					change_state(State.CHASE)
				else:
					start_patrol_idle()

		State.DEATH:
			anim.play(ANIM_DEATH)
			velocity = Vector2.ZERO
			$CollisionShape2D.call_deferred("set_disabled", true)
			# 播完动画消失
			await anim.animation_finished
			queue_free()

#战斗行为
# 这个函数供 AnimationPlayer 的 Call Method Track 调用
# 如果你没在动画里配，可以在 perform_attack 里手动延时调用
func spawn_projectile():
	if projectile_scene:
		var proj = projectile_scene.instantiate()
		proj.global_position = muzzle_pos.global_position
		
		# 确定射线方向
		var dir = Vector2.LEFT if not facing_right else Vector2.RIGHT
		
		# 如果你想让射线稍微追踪玩家高度，可以算角度
		# var angle = (target_player.global_position - muzzle_pos.global_position).angle()
		# dir = Vector2(cos(angle), sin(angle))
		
		if proj.get("direction") != null:
			proj.direction = dir
		if proj.get("damage") != null:
			proj.damage = attack_damage
			
		get_parent().add_child(proj)

func take_damage(amount):
	if current_state == State.DEATH: return
	
	current_hp -= amount
	print("Crawler HP:", current_hp)
	
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
#               6. AI 感知与巡逻
# ==========================================

# --- 巡逻逻辑 ---
func start_patrol_idle():
	change_state(State.IDLE)
	patrol_timer.wait_time = 2.0 # 停 2 秒
	patrol_timer.start()

func _on_patrol_timer_timeout():
	if current_state == State.IDLE:
		# 休息完了，开始走
		change_state(State.PATROL)
		patrol_dir *= -1 # 掉头
		patrol_timer.wait_time = 3.0 # 走 3 秒
		patrol_timer.start()
	elif current_state == State.PATROL:
		# 走累了，停下来
		start_patrol_idle()

# --- 感知逻辑 ---
func _on_detection_entered(body):
	if body.is_in_group("player"): # 记得给主角加 Group
		target_player = body
		patrol_timer.stop() # 发现敌人，停止巡逻逻辑
		change_state(State.CHASE)

func _on_detection_exited(body):
	if body == target_player:
		target_player = null
		start_patrol_idle() # 丢失目标，恢复巡逻

func _on_attack_range_entered(body):
	if body == target_player:
		try_attack()

func _on_attack_range_exited(body):
	if body == target_player and current_state == State.ATTACK:
		# 正在攻击时不用管，等攻击结束会自动判断
		pass

func try_attack():
	# 只有冷却好了才攻击
	if attack_timer.is_stopped() and current_state != State.HURT and current_state != State.DEATH:
		change_state(State.ATTACK)

func _process(delta):
	# 这种 tick 检查为了处理：玩家一直站在攻击范围内的情况
	if current_state == State.IDLE or current_state == State.CHASE:
		if target_player and overlaps_attack_area() and attack_timer.is_stopped():
			try_attack()

# --- 辅助 ---
func _update_facing(dir_x):
	if dir_x > 0 and not facing_right:
		facing_right = true
		sprite.flip_h = false # 假设素材默认朝右
	elif dir_x < 0 and facing_right:
		facing_right = false
		sprite.flip_h = true

func overlaps_attack_area() -> bool:
	return target_player in attack_area.get_overlapping_bodies()
