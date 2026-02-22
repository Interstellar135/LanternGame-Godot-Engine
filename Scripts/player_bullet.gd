extends Area2D

# --- 基础参数 ---
var direction = Vector2.RIGHT
var speed = 600.0 
var damage = 20

# --- 索敌参数 [新增] ---
@export var steer_force = 50.0  # 转向力：数值越大，转弯越急（设为 0 就是普通直线子弹）
var target: Node2D = null       # 当前锁定的敌人

func _ready():
	# 自动销毁
	if has_node("VisibleOnScreenNotifier2D"):
		$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	
	body_entered.connect(_on_body_entered)
	_update_visual_rotation()
	
	# [新增] 子弹一出生，立刻寻找最近的敌人
	target = _find_nearest_enemy()

func _physics_process(delta):
	# --- [核心修改] 追踪逻辑 ---
	if target and is_instance_valid(target):
		# 1. 计算理想方向：从子弹指向敌人
		var desired_direction = (target.global_position - global_position).normalized()
		
		# 2. 慢慢转向：让当前方向 慢慢靠近 理想方向
		# move_toward 就像给向量做线性插值，制造平滑的转弯弧线
		# steer_force * delta 控制转弯速度
		direction = direction.move_toward(desired_direction, steer_force * delta)
		
		# 3. 归一化：确保速度恒定，不会因为转向而变慢
		direction = direction.normalized()
	
	# --- 移动 ---
	position += direction * speed * delta
	
	# --- 更新朝向 ---
	# 让子弹图片始终车头朝前
	rotation = direction.angle()

# [新增] 寻找最近敌人的函数
func _find_nearest_enemy() -> Node2D:
	var nearest_enemy = null
	var min_distance = 1000.0 # 索敌范围：1000像素内才追踪
	
	# 获取当前场景里所有处于 "enemy" 组的节点
	var enemies = get_tree().get_nodes_in_group("enemy")
	
	for enemy in enemies:
		# 排除死掉的敌人（假设敌人脚本里有个 is_dead 变量，没有的话可以去掉这行）
		if "is_dead" in enemy and enemy.is_dead:
			continue
			
		var dist = global_position.distance_to(enemy.global_position)
		if dist < min_distance:
			min_distance = dist
			nearest_enemy = enemy
			
	return nearest_enemy

# 这个函数依然保留，用于主角手动设定初始发射方向
func set_direction(new_dir: Vector2):
	direction = new_dir.normalized()
	_update_visual_rotation()

func _update_visual_rotation():
	rotation = direction.angle()

func _on_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		return 
	
	if body.is_in_group("enemy"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free() 
	else:
		queue_free()
