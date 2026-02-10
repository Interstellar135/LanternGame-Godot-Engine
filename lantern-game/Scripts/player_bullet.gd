extends Area2D

var direction = Vector2.RIGHT
var speed = 600.0 # 主角的子弹通常快一点
var damage = 20

func _ready():
	# 自动连接“飞出屏幕”信号，飞出去了就删掉自己
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	# 连接碰撞信号
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	# 打中敌人
	if body.is_in_group("enemy"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free() # 击中消失
	
	# 打中墙壁 (只要不是主角，且Mask里只勾了Enemy和World，那剩下的就是墙)
	# 为了保险，加个判断
	elif not body.is_in_group("player"):
		queue_free()
