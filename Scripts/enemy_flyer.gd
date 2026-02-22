extends CharacterBody2D

# [修改] 基础配置
@export_group("Stats")
@export var move_speed = 80.0       
@export var attack_damage = 15      # 这是近身碰撞伤害
@export var bullet_damage = 10      # [新增] 子弹伤害
@export var max_hp = 20

@export_group("Combat")
@export var bullet_scene: PackedScene # [新增] 必须把子弹场景拖进来！
@export var shoot_interval = 2.0      # 攻冷却时间

@export_group("Floating")
@export var float_amplitude = 50.0  
@export var float_speed = 3.0       

# --- 动画名称 ---
const ANIM_IDLE   = "Idle"    
const ANIM_MOVE   = "Move"    
const ANIM_ATTACK = "Attack"  
const ANIM_HURT   = "Hurt"    
const ANIM_DEATH  = "Death"   

# --- 状态定义 ---
enum State { IDLE, PATROL, CHASE, ATTACK, HURT, DEATH }

var current_state = State.IDLE
var current_hp = max_hp
var target_player = null
var home_position = Vector2.ZERO 
var time_offset = 0.0            

# [修改] 节点引用
@onready var sprite = $Sprite2D
@onready var anim = $AnimationPlayer
@onready var detection_area = $DetectionArea
@onready var attack_area = $AttackArea
@onready var hitbox = $Hitbox       
@onready var patrol_timer = $PatrolTimer
@onready var attack_cooldown = $AttackCooldown
@onready var muzzle = $Muzzle

# --- [关键修改] 血条引用 ---
@onready var health_bar = $ProgressBar  # 前景红条
@onready var damage_bar = $DamageBar    # [新增] 背景缓冲白条 (记得在场景里加这个节点！)

func _ready():
	# 自动把自己加入 "enemy" 组
	add_to_group("enemy")
	current_hp = max_hp
	
	home_position = global_position
	time_offset = randf() * 100.0 
	
	# --- [核心] 初始化双层血条 ---
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.visible = false # 初始隐藏
	
	if damage_bar:
		damage_bar.max_value = max_hp
		damage_bar.value = current_hp
		damage_bar.visible = false
	# ---------------------------
	
	detection_area.body_entered.connect(_on_detection_entered)
	detection_area.body_exited.connect(_on_detection_exited)
	hitbox.body_entered.connect(_on_hitbox_entered) 
	patrol_timer.timeout.connect(_on_patrol_timer_timeout)
	
	start_patrol()

func _physics_process(delta):
	if current_state == State.DEATH: return

	match current_state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, 10)
			_apply_floating_y(delta)
			
		State.PATROL:
			var patrol_dir = 1 if sprite.flip_h else -1 
			velocity.x = patrol_dir * move_speed
			_apply_floating_y(delta)
			
		State.CHASE:
			if target_player:
				var direction = (target_player.global_position - global_position).normalized()
				velocity = direction * move_speed
				_update_facing(velocity.x)
				
				# 检查是否可以射击
				if _can_attack():
					start_shooting()

		State.ATTACK:
			velocity = Vector2.ZERO 

		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)

	move_and_slide()

# ==========================================
#               辅助逻辑
# ==========================================
func _apply_floating_y(delta):
	var time = Time.get_ticks_msec() / 1000.0 + time_offset
	var float_v = cos(time * float_speed) * float_amplitude
	velocity.y = float_v

func _update_facing(dir_x):
	# 素材默认朝左，所以：
	if dir_x > 0: 
		# 向右飞 -> 需要翻转 (Flip H = true)
		sprite.flip_h = true 
	elif dir_x < 0: 
		# 向左飞 -> 保持默认 (Flip H = false)
		sprite.flip_h = false

func _can_attack():
	if not target_player: return false
	if not attack_cooldown.is_stopped(): return false
	
	var bodies = attack_area.get_overlapping_bodies()
	return target_player in bodies

# ==========================================
#           射击逻辑
# ==========================================
func start_shooting():
	change_state(State.ATTACK)
	attack_cooldown.start(shoot_interval)

	var dir_to_player = (target_player.global_position - global_position).normalized()
	_update_facing(dir_to_player.x)
	
	anim.play(ANIM_ATTACK)
	
	# 等待前摇
	await get_tree().create_timer(0.3).timeout
	
	if current_state == State.ATTACK:
		spawn_bullet()
		await anim.animation_finished
		if current_state == State.ATTACK: 
			if target_player:
				change_state(State.CHASE)
			else:
				start_patrol()

func spawn_bullet():
	if not bullet_scene: return
		
	var bullet = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position
	
	# 设置伤害
	if "damage" in bullet: bullet.damage = bullet_damage
	
	# [关键修改] 把目标传给子弹，让子弹自己去追
	if target_player and "target" in bullet:
		bullet.target = target_player
	
	# 如果子弹没有追踪功能，至少给它一个初始方向
	elif target_player and "direction" in bullet:
		bullet.direction = (target_player.global_position - muzzle.global_position).normalized()
		bullet.rotation = bullet.direction.angle()
		
	get_parent().add_child(bullet)


# ==========================================
#         [核心修改] 受击与血条
# ==========================================
func take_damage(amount):
	if current_state == State.DEATH: return
	
	current_hp -= amount
	
	# --- 1. 显示血条 ---
	health_bar.visible = true
	if damage_bar: damage_bar.visible = true
	
	# --- 2. 红条瞬间扣除 ---
	health_bar.value = current_hp
	
	# --- 3. 白条缓冲动画 ---
	if damage_bar:
		var tween = create_tween()
		tween.tween_interval(0.1) # 停顿一下
		tween.tween_property(damage_bar, "value", current_hp, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	if current_hp <= 0:
		change_state(State.DEATH)
		# 死亡隐藏血条
		health_bar.visible = false
		if damage_bar: damage_bar.visible = false
	else:
		var knockback_dir = Vector2.RIGHT if sprite.flip_h else Vector2.LEFT
		velocity = knockback_dir * 100
		change_state(State.HURT)

func _on_hitbox_entered(body):
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(attack_damage)

func change_state(new_state):
	if current_state == State.DEATH: return
	current_state = new_state
	
	match current_state:
		State.IDLE: anim.play(ANIM_IDLE)
		State.PATROL: anim.play(ANIM_MOVE)
		State.CHASE: anim.play(ANIM_MOVE)
		State.ATTACK: pass
		State.HURT:
			anim.play(ANIM_HURT)
			await anim.animation_finished
			if current_state == State.HURT:
				if target_player: change_state(State.CHASE)
				else: start_patrol()
		State.DEATH:
			anim.play(ANIM_DEATH)
			velocity = Vector2.ZERO
			await anim.animation_finished
			queue_free()

# 巡逻和侦测
func start_patrol():
	change_state(State.IDLE)
	patrol_timer.start(2.0)

func _on_patrol_timer_timeout():
	if current_state == State.IDLE:
		change_state(State.PATROL)
		if randf() > 0.5: sprite.flip_h = !sprite.flip_h
		patrol_timer.start(3.0)
	elif current_state == State.PATROL:
		change_state(State.IDLE)
		patrol_timer.start(2.0)

func _on_detection_entered(body):
	if body.is_in_group("player"):
		target_player = body
		change_state(State.CHASE)

func _on_detection_exited(body):
	if body == target_player:
		target_player = null
		start_patrol()
	
