# player.gd - 战斗系统 + QTE联动核心
extends CharacterBody2D

# ===== 暴露参数（检查器可调）=====
@export var max_health: int = 100
@export var attack_damage: int = 15
@export var qte_shield_value: int = 25
@export var qte_shield_duration: float = 5.0
@export var summon_animation_name: String = "summon"  # 美术提供的召唤动画名
# ===== 移动参数（检查器可调）=====
@export var move_speed: float = 200.0  # 水平移动速度
@export var animation_idle: String = "Idle"   # 与画师确认动画名！
@export var animation_walk: String = "Walk"   # 与画师确认动画名！

# ===== 内部状态 =====
var health: int = 100
var shield: int = 0
var in_combat: bool = false  # 由敌人FSM通过信号设置
var in_qte: bool = false
var qte_screen_position: Vector2  # 用于调试绘制

# ===== 节点引用 =====
@onready var hurtbox = get_node_or_null("Hurtbox")
@onready var attack_hitbox = get_node_or_null("AttackHitbox")
@onready var anim_player = get_node_or_null("AnimationPlayer")
@onready var shield_sprite = get_node_or_null("ShieldSprite")
@onready var shield_vfx = get_node_or_null("Shield_VFX")
@onready var summon_circle = get_node_or_null("SummonCircle")
@onready var summon_vfx = get_node_or_null("SummonVFX")
@onready var camera = get_node_or_null("Camera2D")
@onready var body_art = get_node_or_null("BodyArt")

var qte_manager: Node = null

func _ready():
	# 获取 QTEManager（使用树查询而非绝对路径）
	var root := get_tree().root
	if root:
		var qte_panel = root.find_child("QTEPanel", true, false)
		if qte_panel:
			qte_manager = qte_panel.find_child("QTEManager", true, false)
	
	# 信号连接（关键！避免运行时错误）
	if hurtbox:
		hurtbox.body_entered.connect(_on_hurtbox_entered)
	
	if qte_manager:
		if qte_manager.has_signal("qte_success"):
			qte_manager.qte_success.connect(_on_qte_success)
		if qte_manager.has_signal("qte_failed"):
			qte_manager.qte_failed.connect(_on_qte_failed)
		if qte_manager.has_signal("qte_ended"):
			qte_manager.qte_ended.connect(_on_qte_ended)
	
	add_to_group("player")
	_update_shield_visibility()
	health = max_health
	print("[Player] _ready() completed")
	
	
	
func _update_animation(move_dir: float):
	if anim_player == null:
		return
	
	# 跳过动画更新：正在播放非移动类动画（召唤/受伤等）
	if anim_player.current_animation == summon_animation_name or \
		anim_player.current_animation == "hurt" or \
		anim_player.current_animation == "attack":
		return
	
	# 播放行走动画（有移动）
	if abs(move_dir) > 0.1 and anim_player.current_animation != animation_walk:
		anim_player.play(animation_walk)
	# 播放待机动画（静止）
	elif abs(move_dir) <= 0.1 and anim_player.current_animation != animation_idle:
		anim_player.play(animation_idle)
	


func _physics_process(delta: float):
	# 【关键保护】QTE/召唤期间冻结移动（与现有逻辑无缝衔接）
	if in_qte:
		velocity = Vector2.ZERO
		return
	
	# ===== 1. 获取输入（AD键）=====
	# 方案A：推荐！使用Input Map（解耦按键，支持手柄）
	var move_dir = Input.get_axis("move_left", "move_right")  # 需配置Input Map（见下方）
	
	# ===== 2. 计算速度 & 更新朝向 =====
	velocity.x = move_dir * move_speed
	
	# 翻转角色朝向（假设默认朝右：move_dir>0=向右需翻转）
	if body_art != null and move_dir != 0:
		body_art.flip_h = move_dir > 0  # 向右移动时水平翻转
	
	# ===== 3. 动画状态机（智能切换）=====
	_update_animation(move_dir)
	
	# ===== 4. 应用物理移动 =====
	move_and_slide()	


# ===== 遇敌状态管理（供敌人FSM调用）=====
func set_in_combat(value: bool):
	in_combat = value
	if not value and in_qte:  # 退出战斗时强制结束QTE
		_end_qte()

# ===== 战斗核心逻辑 =====
func take_damage(amount: int):
	if shield > 0:
		shield = max(0, shield - amount)
		if shield == 0: _remove_shield()
		emit_signal("shield_hit")
		return
	health = max(0, health - amount)
	if health > 0 and anim_player:
		anim_player.play("hurt")
	emit_signal("health_changed", health, max_health)
	if health <= 0: _on_death()

func _on_hurtbox_entered(body):
	if body.is_in_group("enemy_attack") and body.is_instance_valid():
		take_damage(body.damage if body.has_method("get_damage") else 10)

# ===== QTE触发流程（核心！）=====
func _input(event):
	# 仅在遇敌状态 + 非QTE中 + 按下Q键触发
	if event.is_action_pressed("skill_qte") and in_combat and not in_qte:
		_start_summon_sequence()

func _start_summon_sequence():
	in_qte = true
	velocity = Vector2.ZERO  # 冻结移动，增强施法沉浸感
	if anim_player:
		anim_player.play(summon_animation_name)  # 播放"提灯召唤"动画

# 【AnimationPlayer关键帧调用】法阵完全展开时启动QTE
func _on_summon_animation_keyframe():
	# 1. 播放召唤粒子（提灯光流射向地面）
	if summon_vfx != null: 
		summon_vfx.emitting = true
		summon_vfx.restart()
	
	# 2. 显示法阵并计算屏幕坐标（关键！）
	if summon_circle != null:
		summon_circle.visible = true
		# 通过Camera2D将世界坐标转为屏幕坐标
		if camera != null:
			qte_screen_position = camera.unproject_position(summon_circle.global_position)
		else:
			qte_screen_position = summon_circle.global_position
	
	# 3. 生成随机三键序列（从预设池选）
	var key_pool = ["l", "i", "n", "k"]
	key_pool.shuffle()
	var sequence = key_pool.slice(0, 3)
	
	# 4. 通知QTE系统在法阵位置启动
	if qte_manager != null and qte_manager.is_inside_tree():
		qte_manager.start_at_position(qte_screen_position, sequence)
	else:
		push_error("QTEManager not found! Check node path.")

# ===== QTE结果处理 =====
func _on_qte_success(sequence: Array):
	# 法阵成功反馈：金光脉冲
	if summon_circle != null:
		var original_modulate = summon_circle.modulate
		summon_circle.modulate = Color.YELLOW
		await get_tree().create_timer(0.1).timeout
		summon_circle.modulate = original_modulate
	
	# 激活护盾（复用战斗系统逻辑）
	shield = qte_shield_value
	_update_shield_visibility()
	
	# 播放护盾激活特效（瞬间）
	if shield_vfx != null:
		shield_vfx.restart()  # 仅播放一次
	
	# 播放成功音效（可选）
	# $AudioStreamPlayer.play("res://sfx/shield_activate.wav")

func _on_qte_failed():
	# 失败反馈：法阵暗红闪烁
	if summon_circle != null:
		var original_modulate = summon_circle.modulate
		summon_circle.modulate = Color(1, 0.3, 0.3)
		await get_tree().create_timer(0.15).timeout
		summon_circle.modulate = original_modulate
	# 可添加失败音效/硬直

func _on_qte_ended():
	_end_qte()

func _end_qte():
	in_qte = false
	# 淡出法阵（与QTEPanel同步）
	if summon_circle != null and summon_circle.visible:
		var tween = create_tween()
		tween.tween_property(summon_circle, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func():
			summon_circle.visible = false
			summon_circle.modulate.a = 1.0
			if summon_vfx != null: summon_vfx.emitting = false
		)
	# 恢复移动（如有冻结）
	# velocity = Vector2.ZERO  # 根据实际需求

# ===== 护盾管理 =====
func _update_shield_visibility():
	if shield_sprite != null:
		shield_sprite.visible = shield > 0
		# 可选：动态透明度（护盾越少越透明）
		# if shield_sprite.visible: shield_sprite.modulate.a = clamp(float(shield) / qte_shield_value, 0.3, 1.0)

func _remove_shield():
	shield = 0
	_update_shield_visibility()

# ===== 调试辅助（开发期启用）=====
func _draw():
	if in_qte:  # 移除 Engine.is_editor_hint() 以便运行时调试（发布前注释整段）
		# 绘制QTE中心红点
		draw_circle(qte_screen_position, 8, Color.RED)
		
		# Godot 4 正确用法：font=null, 对齐参数用整数, color放最后
		draw_string(
			null,  # font (null=使用默认字体)
			qte_screen_position + Vector2(10, 0),  # 位置
			"QTE CENTER",  # 文本
			HORIZONTAL_ALIGNMENT_LEFT,  # 水平对齐 (Godot 4 枚举)
			VERTICAL_ALIGNMENT_TOP,     # 垂直对齐
			-1,                         # clip_w (-1=不裁剪)
			Color.RED                   # 颜色 (必须放最后!)
		)


# ===== 信号声明（供UI/音效系统监听）=====
signal health_changed(current: int, max: int)
signal shield_hit
signal death

func _on_death():
	emit_signal("death")
	queue_free()  # 或播放死亡动画
