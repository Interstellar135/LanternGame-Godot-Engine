extends Area2D

# --- 核心配置 ---
# 这个 ID 必须和 PuzzleManager 里配置的 Key 一致 (比如 puzzle_1)
@export var puzzle_id: StringName = "puzzle_1" 

# --- 内部状态 ---
var is_active = false # 只有怪打完了才变成 true
var _manager: Node = null # 用来缓存 PuzzleManager

# --- 节点引用 ---
@onready var prompt_label = $Label
@onready var sprite = $Sprite2D # 或者是你的 TriangleSprite
# 如果你有 AnimationPlayer，也可以在这里引用
# @onready var anim = $AnimationPlayer

func _ready():
	# 1. 初始化视觉状态
	prompt_label.visible = false
	sprite.modulate = Color(0.5, 0.5, 0.5) # 默认灰色(不可用)
	
	# 2. 自动寻找 PuzzleManager
	# 这种查找方式比较通用，不管它在场景树的哪里都能找到
	_manager = get_tree().root.find_child("PuzzleManager", true, false)
	if not _manager:
		push_warning("PuzzleTrigger: 找不到 PuzzleManager，解谜功能将无法触发！")

	# 3. 连接物理信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

# --- 外部接口：由关卡脚本调用 ---
# 当你清除了关卡小怪后，调用这个函数
func activate():
	is_active = true
	sprite.modulate = Color.WHITE # 变亮，表示可以用了
	
	# 如果玩家此时就已经站在圈里了，立刻更新状态
	# 这样防止玩家站在圈里杀完怪，还要退出去再进来才能触发
	var bodies = get_overlapping_bodies()
	for body in bodies:
		if body.name == "Player":
			_register_to_manager()
			prompt_label.visible = true

# --- 物理检测回调 ---
func _on_body_entered(body):
	# 只有当 (1) 是主角 (2) 机关已激活 时，才允许交互
	if body.name == "Player" and is_active:
		prompt_label.visible = true
		_register_to_manager()

func _on_body_exited(body):
	if body.name == "Player":
		prompt_label.visible = false
		_unregister_from_manager()

# --- 辅助函数：与管理器通信 ---
func _register_to_manager():
	if _manager:
		# 告诉管理器：现在按 E 键打开的是这个 puzzle_id
		_manager.set_interactable(puzzle_id)

func _unregister_from_manager():
	if _manager:
		# 告诉管理器：玩家走了，没什么可交互的了
		_manager.clear_interactable(puzzle_id)

# --- [已删除] ---
# func _unhandled_input(event):
#    这里不需要了！
#    因为 PuzzleManager 会检测按键，���根据 set_interactable 设定的 ID 来打开谜题。
#    如果这里保留，可能会导致按一次 E 触发两次逻辑。
