extends Area2D

@export var speed = 200.0         # 子弹速度
@export var steer_force = 5.0     # 转向灵敏度 (越大追得越紧)
@export var life_time = 5.0       # 存活时间
@export var damage = 10

var velocity = Vector2.ZERO
var target: Node2D = null         # 追踪目标
var direction = Vector2.ZERO      # 如果没有目标，就走直线

func _ready():
	# 5秒后自动销毁，防止子弹无限多
	await get_tree().create_timer(life_time).timeout
	queue_free()
	
	# 初始连接信号 (用来造成伤害)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if target:
		# --- 追踪逻辑 ---
		var desired_velocity = (target.global_position - global_position).normalized() * speed
		# 逐渐转向目标 (Steering behavior)
		var steering = (desired_velocity - velocity) * steer_force * delta
		velocity += steering
	else:
		# --- 直线逻辑 (如果没有目标) ---
		if velocity == Vector2.ZERO and direction != Vector2.ZERO:
			velocity = direction * speed
	
	# 限制最大速度
	velocity = velocity.limit_length(speed)
	
		# 更新位置
	position += velocity * delta
	
	# 让子弹头朝向飞行方向
	if velocity.length() > 0:
		# [修改] 既然素材默认朝左，那就算出角度后 + 180度 (PI)
		rotation = velocity.angle() + PI 

func _on_body_entered(body):
	print(">> 子弹撞到了: ", body.name) # 加这句！看看控制台输出啥
	
	# 碰到主角扣血
	if body.is_in_group("player"):
		print(">> 确认是玩家！尝试扣血...") # 加这句
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	
	# 碰到墙壁
	elif body is TileMap or body.name == "TileMap":
		queue_free()
