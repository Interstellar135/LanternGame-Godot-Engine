extends Area2D

var direction = Vector2.LEFT
var speed = 300.0 # 敌人的子弹通常慢一点，给玩家躲避时间
var damage = 10

func _ready():
	$VisibleOnScreenNotifier2D.screen_exited.connect(queue_free)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position += direction * speed * delta

func _on_body_entered(body):
	# 打中主角
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free() # 击中消失
	
	# 打中墙壁
	elif not body.is_in_group("enemy"):
		queue_free()
