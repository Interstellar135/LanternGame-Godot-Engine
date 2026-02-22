extends CharacterBody2D

# [新增] 添加信号定义
signal died 

#核心配置
@export_group("Stats")
@export var shield_duration = 10.0 # 无敌持续时间
@export var move_speed = 300.0 
@export var max_hp = 100.0 # 注意：为了回血平滑，建议改成 float (100.0)
@export var hp_regen_rate = 10.0 # 新增：每秒回血量 (比如每秒回10点)

@export_group("Combat Assets")
@export var bullet_scene: PackedScene # 记得拖拽子弹场景进来

# [新增] 技能锁开关 (默认关闭，由关卡脚本控制打开)
@export var qte_unlocked: bool = false

# --- 动画配置 ---
@export_group("Animations")
@export var idle_variations:Array[String] = ["Idle1"] # 美术给你的其他闲置动画名

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
# 保存一个变量用来控制呼吸动画，方便消失时打断它
var shield_tween: Tween
var health_tween: Tween # <--- [新增] 专门控制血条动画
var is_puzzle_locked = false # 允许外部锁住输入
# [新增] 标志位：是否等待停下后收刀
var pending_combat_exit = false
# 在变量定义区加这行
var is_cutscene_locked = false # 剧情锁，开启后完全动不了

#节点引用
@onready var body_art = $Sprite2D
@onready var qte_system = $QTESystem
@onready var lantern_pos_node = $LanternPos # 记得引用那个 Marker2D
@onready var sprite = $Sprite2D # 或 $BodySprite
@onready var shield_sprite = $ShieldSprite
@onready var anim = $AnimationPlayer
@onready var detection_area = $CombatDetectionArea 
#计时器引用
@onready var invincibility_timer = $InvincibilityTimer
@onready var combat_exit_timer = $CombatExitTimer # 建议设为 5.0秒, One Shot
@onready var idle_timer = $IdleTimer # 建议设为 3.0秒, One Shot
# 新增 UI 引用
@onready var health_bar = $CanvasLayer/HealthBar
@onready var damage_bar = $CanvasLayer/DamageBar # <--- [必须添加] 引用黄条

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
	# --- [新增] 强制把自己加入 player 组 ---
	add_to_group("player") 
	shield_sprite.visible = false
	shield_sprite.scale = Vector2.ZERO # <--- 新增这行，防止第一帧闪现大图
	current_hp = max_hp
	# 初始化 UI (实血条)
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current_hp
		
	# [新增] 初始化缓冲条 (黄条)
	if damage_bar:
		damage_bar.max_value = max_hp
		damage_bar.value = current_hp
	# 连接QTE信号
	qte_system.qte_success.connect(_on_qte_success)
	qte_system.qte_failed.connect(_on_qte_failed)
	invincibility_timer.timeout.connect(_on_shield_timeout)
	#连接计时信号
	combat_exit_timer.timeout.connect(_on_combat_exit_timeout)
	idle_timer.timeout.connect(_on_idle_timer_timeout)
	# 初始状态
	# 不要只写 change_state(State.Idle)
	# 因为 change_state 会因为状态相同而被拦截
	
	# 强制初始化
	current_state = State.Idle 
	_play_normal_idle() # 或者直接写 anim.play(ANIM_IDLE_NORMAL)
	if detection_area:
		detection_area.body_entered.connect(_on_enemy_detected)
	

func _physics_process(delta):
		# [新增] 如果剧情锁开了，谁来喊都没用，直接 return
	if is_cutscene_locked:
		velocity = Vector2.ZERO # 确保不滑行
		move_and_slide() # 加上这句是为了让重力稍微生效一点（或者干脆不加）
		return
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
			
			# [新增] 发送死亡信号！
			emit_signal("died") 
 
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
	
	# [新增] 既然重新进入战斗/刷新时间，就取消等待收刀
	pending_combat_exit = false 
	
	if not is_in_combat:
		is_in_combat = true
		# 只有从平时状态切过来，才播拔刀前摇
		# 避免在受击或攻击时被强制切去播前摇
		if current_state == State.Idle or current_state == State.Walk:
			change_state(State.Combat_prepare)
	
# 脱战倒计时回调
func _on_combat_exit_timeout():
	# 情况1：站着不动 -> 直接收刀
	if current_state == State.Idle:
		change_state(State.Combat_exit)
	
	# 情况2：正在跑/跳/其他 -> 标记“待会收刀”，但保持战斗姿态
	else:
		pending_combat_exit = true
		print("移动中超时：已标记，将在停下后执行收刀")
		
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
		# [修改] 只有当状态不是 Idle 时才需要切换
		if current_state != State.Idle:
			
			# [新增] 检查是否有“等待收刀”的标志
			if pending_combat_exit:
				print("��测到停止移动，执行延迟收刀")
				pending_combat_exit = false # 消费掉这个标志
				change_state(State.Combat_exit) # 播放收刀动画
				
			else:
				# 正常情况：直接变回待机
				change_state(State.Idle)
			
#攻击，QTE部分
func _unhandled_input(event):
	if is_puzzle_locked: return # 如果被锁了，什么按键都不认
	# [测试] 只要按了键盘，就打印出来，看看函数有没有被触发
	if event is InputEventKey and event.pressed:
		print("按键被触发: ", event.as_text())
	# 限制输入：只有活着且不在硬直中才能操作
	if current_state in [State.Death, State.Hurt, State.Combat_prepare, State.Combat_exit]:
		return

	# 攻击 (J)
	if event.is_action_pressed("attack"):
		perform_attack()
	
	# [测试] 在判断锁之前打印
	if event.is_action_pressed("skill_qte"):
		print("检测到 Q 键！当前锁状态 qte_unlocked: ", qte_unlocked)
	# QTE (Q)
	# [修改] 增加 qte_unlocked 的判断
	if qte_unlocked and event.is_action_pressed("skill_qte"):
		print("QTE 逻辑启动！") # 如果打印了这句但没反应，是 QTE 系统内部问题
		var offset = lantern_pos_node.position
		var is_facing_right = not sprite.flip_h
		qte_system.start_qte(offset, is_facing_right)

#具体战斗行为
func perform_attack():
	# 情况 1：平时闲逛时按攻击键 -> 先拔刀 (进入战斗状态)
	if not is_in_combat:
		enter_combat_mode() 
		# 这里不需要手动再切 Attack 了，因为 enter_combat_mode 会切到 Prepare。
		# 你可以让玩家看完拔刀动作后，再按一次 J 才能砍（比较真实）。
		# 或者，如果你想拔刀后自动接第一刀，可以在 Combat_prepare 结束后自动切 Attack。
		return

	# 情况 2：已经是战斗状态了 -> 直接砍
	change_state(State.Attack)
	# 推荐：在动画里添加 Call Method Track 调用 spawn_bullet
	spawn_bullet()
	
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
	# 防止重复触发导致逻辑混乱，如果已有盾牌，先重置一下
	if is_invincible:
		if shield_tween: shield_tween.kill() # 杀掉之前的动画
	
	is_invincible = true
	shield_sprite.visible = true
	
	# --- 阶段 1: 出现动画 (从0变大) ---
	shield_sprite.scale = Vector2.ZERO # 先缩成0
	shield_sprite.modulate.a = 1.0     # 确保不透明
	
	var pop_tween = create_tween()
	# 0.3秒内，像果冻一样弹出来 (TRANS_BACK)
	pop_tween.tween_property(shield_sprite, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_BACK)
	
	# --- 阶段 2: 启动呼吸循环 (出现动画结束后) ---
	pop_tween.tween_callback(_start_shield_loop) # 播完弹出，就开始呼吸
	
	# 启动无敌计时器
	invincibility_timer.start(shield_duration)
	print("Shield Activated! 无敌模式启动")
	
# 辅助函数：让盾牌像呼吸一样忽隐忽现
func _start_shield_loop():
	# 如果盾牌没了，就不播了
	if not is_invincible: return
	
	# 创建一个新的循环动画
	if shield_tween: shield_tween.kill()
	shield_tween = create_tween().set_loops() # 无限循环
	
	# 1秒变半透明，1秒变回来
	shield_tween.tween_property(shield_sprite, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
	shield_tween.tween_property(shield_sprite, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func _on_shield_timeout():
	is_invincible = false
	print("Shield Depleted. 盾牌破碎")
	
	# 杀掉呼吸动画，防止干扰
	if shield_tween: shield_tween.kill()
	
	# --- 消失动画 (变小 + 变透明) ---
	var end_tween = create_tween()
	# 并行执行：一边变小，一边变透明
	end_tween.set_parallel(true)
	end_tween.tween_property(shield_sprite, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	end_tween.tween_property(shield_sprite, "modulate:a", 0.0, 0.3)
	
	# 等动画播完，再彻底隐藏节点
	await end_tween.finished
	shield_sprite.visible = false

# 新增：封装一个更新UI的小函数 (带平滑动画版)
# ========================================================
# [修改] 双层血条更新逻辑
# ========================================================
func update_health_ui():
	# 1. ���际血条 (绿条/Top)：立刻减少，或者极快减少
	if health_bar:
		# 0.1秒变过去，显得干脆利落
		# 注意：这里不用 health_tween，直接创建一个临时的 tween
		var tween_top = create_tween()
		tween_top.tween_property(health_bar, "value", current_hp, 0.1).set_trans(Tween.TRANS_SINE)
	
	# 2. 缓冲血条 (黄条/Bottom)：延迟后慢吞吞地追上来
	if damage_bar:
		# 如果之前的缓冲动画还没播完，先杀掉，防止逻辑冲突
		if health_tween: 
			health_tween.kill()
		
		health_tween = create_tween()
		
		# 关键逻辑：
		# 1. 先停顿 0.5 秒 (让玩家看到那截黄色的血条残影)
		# 2. 然后在 0.4 秒内平滑减少到当前血量
		health_tween.tween_interval(0.5) 
		health_tween.tween_property(damage_bar, "value", current_hp, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
func _on_enemy_detected(body):
	# 假设你的敌人都在 "enemy" 组里，或者通过名字判断
	if body.is_in_group("enemy") or "Enemy" in body.name:
		print("发现敌人！进入战斗姿态")
		enter_combat_mode()
		
# [新增] 强制结束战斗状态 (供外部调用，如解谜、过场动画)
func force_stop_combat():
	# 1. 停止战斗计时器
	combat_exit_timer.stop()
	
	# 2. 清除所有战斗标记
	is_in_combat = false
	pending_combat_exit = false
	
	# 3. 强制切回普通待机
	# 先设为 Idle，确保状态机重置
	change_state(State.Idle) 
	
	# 4. 手动触发一次普通待机逻辑 (确保不播战斗Idle)
	anim.play(ANIM_IDLE_NORMAL)
	
	# 5. 重新开启发呆计时器 (可选，恢复生活气息)
	if idle_timer.is_stopped():
		idle_timer.start(randf_range(3.0, 6.0))
		
	print("已强制脱战，重置为 IDLE")
