extends CharacterBody2D

#核心配置
@export_group("Stats")
@export var shield_duration = 3.0 # 无敌持续时间
@export var move_speed = 300.0 
@export var max_hp = 100.0 # 注意：为了回血平滑，建议改成 float (100.0)
@export var hp_regen_rate = 10.0 # 新增：每秒回血量 (比如每秒回10点)

@export_group("Combat Assets")
@export var bullet_scene: PackedScene # 记得拖拽子弹场景进来
@export var idle_variations:Array[String] = ["Idle1", "Idle2"] # 美术给你的其他闲置动画名

#动画名称配置
const ANIM_IDLE_NORMAL = "Idle_Normal" # 普通待机2个
const ANIM_IDLE_COMBAT = "Idle_Combat" # 战斗待机(单帧或循环)
const ANIM_WALK_NORMAL = "Walk"             # 普通行走
const ANIM_WALK_COMBAT = "Walk_Combat"      # 战斗行走(长柄状态)
const ANIM_PREPARE     = "Combat_prepare"   # 遇敌/变形前摇
const ANIM_EXIT        = "Combat_exit"       # 脱战/恢复 (Combat_prepare的倒放)
const ANIM_ATTACK      = "Attack"           # 攻击
const ANIM_HURT        = "Hurt"             # 受击
const ANIM_DEATH       = "Death"            # 死亡

#内部变量
var current_state = State.Idle
var current_hp = max_hp
var is_in_combat = false # 默认为平时状态
var is_invincible = false # 这是一个独立的状态，因为无敌时也可以跑

#节点引用
@onready var body_art = $Sprite2D
@onready var qte_system = $QTESystem
@onready var lantern_pos_node = $LanternPos # 记得引用那个 Marker2D
@onready var sprite = $Sprite2D # 或 $BodySprite
@onready var shield_sprite = $ShieldSprite
@onready var anim = $AnimationPlayer
#计时器引用
@onready var invincibility_timer = $InvincibilityTimer
@onready var combat_exit_timer = $CombatExitTimer # 建议设为 5.0秒, One Shot
@onready var idle_timer = $IdleTimer # 建议设为 3.0秒, One Shot
# 新增 UI 引用
@onready var health_bar = $CanvasLayer/HealthBar

#状态机定义
enum State {
	Idle, 	#待机两个
	Walk,	#行走两个
	Combat_prepare,	#战斗准备
	Combat_exit,    # 脱战后摇 (收刀)
	Attack,	#攻击
	Hurt,	#受击
	Death	#死亡
}


func _ready():
	shield_sprite.visible = false
	current_hp = max_hp
	# 初始化 UI
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current_hp
	# 连接QTE信号
	qte_system.qte_success.connect(_on_qte_success)
	qte_system.qte_failed.connect(_on_qte_failed)
	invincibility_timer.timeout.connect(_on_shield_timeout)
	#连接计时信号
	combat_exit_timer.timeout.connect(_on_combat_exit_timeout)
	idle_timer.timeout.connect(_on_idle_timer_timeout)
	# 初始状态
	change_state(State.Idle)
	

func _physics_process(delta):
	#死了就是死了，直接return，不然你会看到主角反复死去……
	if current_state == State.Death:
		return
		
	# --- 新增：脱战回血逻辑 ---
	# 如果不在战斗中，且血量不满，且没死
	if not is_in_combat and current_hp < max_hp and current_state != State.Death:
		current_hp += hp_regen_rate * delta
		# 限制不超过上限
		if current_hp > max_hp:
			current_hp = max_hp
		# 更新 UI
		update_health_ui()
	# -----------------------
	
	match current_state:
		State.Idle,State.Walk:
			_handle_move_input(delta)
		State.Attack:
			# 攻击时施加摩擦力，防止滑步
			velocity.x = move_toward(velocity.x, 0, move_speed * delta)
		State.Combat_prepare, State.Combat_exit, State.Hurt:
			# 受击击退减速
			velocity.x = move_toward(velocity.x, 0, 500 * delta)
	
	#应用物理移动
	move_and_slide()	
	

#核心：状态机逻辑
func change_state(new_state):
	# 死亡状态不可逆
	if current_state == State.Death: 
		return
	# 防止重复进入 (HURT除外，允许连续挨打)
	if current_state == new_state and new_state != State.Hurt: 
		return
	#更新状态
	current_state = new_state
	
	match current_state:
		State.Idle:
			velocity.x = 0
			if is_in_combat:
				# 战斗状态：播放长柄持灯姿势 (禁止发呆)
				anim.play(ANIM_IDLE_COMBAT)
				idle_timer.stop()
			else:
				# 平时状态：播放普通呼吸 + 开启发呆计时
				_play_normal_idle()
			
		State.Walk:
			idle_timer.stop()
			# 根据是否战斗，决定播放哪种走路动画
			if is_in_combat:
				anim.play(ANIM_WALK_COMBAT)
			else:
				anim.play(ANIM_WALK_NORMAL)
			
		State.Combat_prepare:
			idle_timer.stop()
			velocity.x = 0
			anim.play(ANIM_PREPARE)
			await anim.animation_finished
			if current_state == State.Combat_prepare:
				change_state(State.Idle) # 播完切回IDLE (此时已是战斗态idle)
				
		State.Combat_exit:
			idle_timer.stop()
			velocity.x = 0
			anim.play(ANIM_EXIT) # 收刀
			await anim.animation_finished
			
			# 关键：动画播完才算真正脱战
			is_in_combat = false 
			print("脱战完成：已收刀")
			
			if current_state == State.Combat_exit:
				change_state(State.Idle) # 切回 IDLE (此时 is_in_combat=false，会显示普通待机)
				
		State.Attack:
			idle_timer.stop()
			enter_combat_mode() # 攻击会刷新战斗状态
			velocity.x = 0
			anim.play(ANIM_ATTACK)
			# 攻击结束自动切回 IDLE
			await anim.animation_finished
			if current_state == State.Attack:
				change_state(State.Idle)
				
		State.Hurt:
			idle_timer.stop()
			enter_combat_mode() # 挨打也会进入战斗状态
			anim.play(ANIM_HURT)
			await anim.animation_finished
			if current_state == State.Hurt:
				change_state(State.Idle)
				
		State.Death:
			idle_timer.stop()
			combat_exit_timer.stop()
			velocity = Vector2.ZERO
			anim.play(ANIM_DEATH)
 
#辅助逻辑
#待机（非战斗）切换, 播放普通待机 + 启动随机状态
func _play_normal_idle():
	anim.play(ANIM_IDLE_NORMAL)
	idle_timer.wait_time = randf_range(3.0, 6.0)
	idle_timer.start()
# 状态倒计时回调
func _on_idle_timer_timeout():
	# 只有在非战斗 IDLE 下才发呆
	if current_state == State.Idle and not is_in_combat and not idle_variations.is_empty():
		var random_anim = idle_variations.pick_random()
		anim.play(random_anim)
		await anim.animation_finished
		if current_state == State.Idle:
			_play_normal_idle() # 恢复循环

#战斗模式管理
func enter_combat_mode():
	combat_exit_timer.start(5.0) # 刷新5秒倒计时
	
	if not is_in_combat:
		is_in_combat = true
		# 只有从平时状态切过来，才播拔刀前摇
		# 避免在受击或攻击时被强制切去播前摇
		if current_state == State.Idle or current_state == State.Walk:
			change_state(State.Combat_prepare)
	
# 脱战倒计时回调
func _on_combat_exit_timeout():
	# 只有站着不动时，才播放优雅的收刀动作
	if current_state == State.Idle:
		change_state(State.Combat_exit)
	else:
		# 如果正在跑，直接静默切换状态
		is_in_combat = false
		print("移动中脱战：下次停下将恢复普通姿态")
		
#输入处理（移动，攻击，QTE）

#移动部分
func _handle_move_input(delta):
	# 只有idle和walk允许输入
	var move_dir = Input.get_axis("move_left", "move_right")
	
	if move_dir != 0:
		velocity.x = move_dir * move_speed
		if sprite.flip_h != (move_dir < 0):
			sprite.flip_h = (move_dir < 0)
			
		if current_state != State.Walk:
			change_state(State.Walk)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		if current_state != State.Idle:
			change_state(State.Idle)
			
#攻击，QTE部分
func _unhandled_input(event):
	# 限制输入：只有活着且不在硬直中才能操作
	if current_state in [State.Death, State.Hurt, State.Combat_prepare, State.Combat_exit]:
		return

	# 攻击 (J)
	if event.is_action_pressed("attack"):
		perform_attack()
	
	# QTE (Q)
	if event.is_action_pressed("skill_qte"):
		var offset = lantern_pos_node.position
		var is_facing_right = not sprite.flip_h
		qte_system.start_qte(offset, is_facing_right)

#具体战斗行为
func perform_attack():
	change_state(State.Attack)
	# 推荐：在动画里添加 Call Method Track 调用 spawn_bullet
	# spawn_bullet() 
	
func spawn_bullet():
	# 1. 检查有没有配置子弹场景 (防报错)
	if bullet_scene:      
		# 2. 实例化 (Instantiate)
		# 相当于把子弹场景从“图纸”变成了一个真实的“节点对象”
		var bullet = bullet_scene.instantiate()  
		# 3. 设置位置
		# 把子弹移到 lantern_pos_node (你的 Marker2D) 的位置
		# 这样子弹就会从提灯口飞出来，而不是从主角脚底下飞出来
		bullet.global_position = lantern_pos_node.global_position 
		# 4. 设置方向
		# sprite.flip_h 为 true 代表向左，false 代表向右
		# 如果向左，方向就是 (-1, 0)，向右就是 (1, 0)
		var dir = Vector2(-1 if sprite.flip_h else 1, 0)       
		# 5. 把方向传给子弹
		# 假设子弹脚本里有个变量叫 direction，用来控制飞行方向
		if bullet.get("direction") != null:
			bullet.direction = dir     
		# 6. 添加到场景 (最重要的！)
		# get_parent() 通常是当前关卡的根节点。
		# 我们不能 add_child(bullet) 加到主角身上，否则主角移动时，发射出去的子弹也会跟着主角平移（很滑稽）。
		# 必须把子弹加到“世界”里，让它独立飞行。
		get_parent().add_child(bullet)
		
func take_damage(amount):
	if is_invincible:
		print("护盾生效：伤害免疫")
		return
	if current_state == State.Death: return

	current_hp -= amount
	update_health_ui() # 新增：受伤立刻刷新UI
	
	print("受到伤害, 剩余HP:", current_hp)
	
	if current_hp <= 0:
		current_hp = 0 # 锁死为0，防止UI显示负数
		update_health_ui()
		change_state(State.Death)
	else:
		change_state(State.Hurt)

#QTE 回调

func _on_qte_success():
	activate_shield()

func _on_qte_failed():
	print("Spell failed!")
	# 可以播放一个冒烟的特效

#护盾逻辑

func activate_shield():
	is_invincible = true
	shield_sprite.visible = true
	invincibility_timer.start(shield_duration)
	print("Shield Activated!")

func _on_shield_timeout():
	is_invincible = false
	shield_sprite.visible = false
	print("Shield Depleted.")

# 新增：封装一个更新UI的小函数
func update_health_ui():
	if health_bar:
		health_bar.value = current_hp
