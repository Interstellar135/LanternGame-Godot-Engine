extends Node2D

# 信号定义
signal puzzle_opened(puzzle_id: StringName)
signal puzzle_closed(puzzle_id: StringName, reason: StringName)
signal puzzle_resolved(puzzle_id: StringName, success: bool)
signal request_level_change(next_level_path: String)

# 常量配置
const PUZZLE_1_ID: StringName = &"puzzle_1"
const PUZZLE_2_ID: StringName = &"puzzle_2"
# [新增] 第 3 关 (最终关) 的 ID 和路径
const PUZZLE_FINAL_ID: StringName = &"puzzle_final"
const PUZZLE_FINAL_SCENE_PATH := "res://Scenes/Puzzle_Final.tscn"
const PUZZLE_1_SCENE_PATH := "res://Scenes/Puzzle_1.tscn"
const PUZZLE_2_SCENE_PATH := "res://Scenes/Puzzle_2.tscn"

# 导出变量配置
@export var next_level_path_by_puzzle_id: Dictionary = {}
@export var hud_hint_label_path: NodePath
@export var player_hud_path: NodePath  # [新增] 主角 UI 路径

# 内部变量
# 1. 变量定义改松一点
var _player_hud: Node = null 
var active_puzzle: Node = null
var active_puzzle_id: StringName = &""
var puzzle_mode: bool = false
var current_interactable_id: StringName = &""


# 节点引用 (根据您的层级结构)
@onready var _puzzle_layer: CanvasItem = get_node_or_null("../PuzzleLayer") as CanvasItem
@onready var _puzzle_root: Node = get_node_or_null("../PuzzleLayer/PuzzleRoot")
@onready var _puzzle_hud: CanvasItem = get_node_or_null("../PuzzleLayer/puzzle_hud") as CanvasItem
@onready var _esc_button: Button = get_node_or_null("../PuzzleLayer/puzzle_hud/esc") as Button
@onready var _submit_button: Button = get_node_or_null("../PuzzleLayer/puzzle_hud/submit") as Button
@onready var _reset_button: Button = get_node_or_null("../PuzzleLayer/puzzle_hud/reset") as Button
@onready var _player: Node = get_node_or_null("../Player")

var _hint_label: Label = null
var _puzzle_1_scene: PackedScene = null
var _puzzle_2_scene: PackedScene = null
# 在类变量区域增加一个变量存它
var _puzzle_final_scene: PackedScene = null


func _ready() -> void:
	# 1. 自动把自己加入组，方便 Trigger 找到 (替代 static inst)
	add_to_group("puzzle_manager")
	
	_load_puzzle_scenes()
	_self_check_paths()
	_connect_hud_buttons_once()
	_cache_hint_label()
	_set_puzzle_ui_visible(false)
	
	if player_hud_path:
		_player_hud = get_node_or_null(player_hud_path)

	_debug("ready done - PuzzleManager initialized")


# [修改] 使用 _input 而不是 _unhandled_input 来处理解谜时的 ESC
# 这样能保证它比 LevelControl (通常用 _unhandled_input) 先收到信号
# 确保 Inspector 里 Process Mode = Always !!!

# 确保 Inspector 里 Process Mode = Always !!!

# [第一部分] 高优先级：专门负责拦截 ESC
# 只要还在解谜，ESC 就归我管，暂停菜单别想碰
func _input(event: InputEvent) -> void:
	if not puzzle_mode:
		return

	if event.is_action_pressed("ui_cancel"): # 按了 ESC
		_debug("PuzzleManager: 强行拦截 ESC")
		cancel_puzzle()
		
		# [核心] 这句话是神技！
		# 它告诉 Godot引擎：“这个按键已经被我吃掉了，不要再传给 LevelControl (暂停菜单)！”
		get_viewport().set_input_as_handled()


# [第二部分] 低优先级：专门负责平时按 E 交互
# 只有当 puzzle_mode = false 时，这个函数才有机会执行
func _unhandled_input(event: InputEvent) -> void:
	# 如果正在解谜，上面的 _input 已经处理了按键，
	# 或者是其他无关按键，这里直接无视，防止误触
	if puzzle_mode:
		return
		
	# 只有没在解谜时，才允许按 E 打开新拼图
	if current_interactable_id != &"" and event.is_action_pressed("interact"):
		open_puzzle(current_interactable_id)
		# 这里��记处理，防止 E 键穿透去做别的事
		get_viewport().set_input_as_handled()


# ==============================================================================
# 核心功能：打开/关闭/提交
# ==============================================================================

func open_puzzle(puzzle_id: StringName) -> void:
	if puzzle_id == &"":
		push_error("[PuzzleManager] open_puzzle failed: empty puzzle_id")
		return

	if _puzzle_root == null:
		push_error("[PuzzleManager] open_puzzle failed: missing ../PuzzleLayer/PuzzleRoot")
		return

	# 防止重复打开
	if active_puzzle != null:
		close_puzzle(&"reopen")

	var scene := _get_scene_by_id(puzzle_id)
	if scene == null:
		push_error("[PuzzleManager] open_puzzle failed: unknown puzzle_id = %s" % String(puzzle_id))
		return

	# 实例化拼图
	active_puzzle = scene.instantiate()
	active_puzzle_id = puzzle_id
	
	# [关键] 自动连接子拼图的 "solved" 信号
	# 这样 Puzzle_2 一发信号，Manager 就自动提交，不需要手动按按钮
	if active_puzzle.has_signal("solved"):
		if not active_puzzle.solved.is_connected(submit_puzzle):
			active_puzzle.solved.connect(submit_puzzle)
			_debug("Connected 'solved' signal from puzzle")

	_puzzle_root.add_child(active_puzzle)
	
	# UI 和输入状态切换
	_set_puzzle_ui_visible(true)
	_set_player_input_enabled(false)
	puzzle_mode = true
	
	# 隐藏主角血条等 UI
	if _player_hud and "visible" in _player_hud:
		_player_hud.visible = false
		
	_debug("opened %s" % String(puzzle_id))
	emit_signal("puzzle_opened", puzzle_id)


func close_puzzle(reason: StringName = &"cancel") -> void:
		# [新增] 强制重置按钮状态！防止它卡在“按下”或“高亮”状态
	if _esc_button:
		_esc_button.button_pressed = false # 强制弹起
		_esc_button.release_focus()        # 强制丢失焦点
		# 如果按钮有高亮纹理，有时需要手动重置鼠标进入状态(比较少见，通常上面两行够了)
	var closed_id := active_puzzle_id

	if active_puzzle != null and is_instance_valid(active_puzzle):
		active_puzzle.queue_free()

	active_puzzle = null
	active_puzzle_id = &""
	
	# 恢复状态
	_set_puzzle_ui_visible(false)
	_set_player_input_enabled(true)
	puzzle_mode = false
	_set_hud_hint("")
	
	# 恢复主角 UI
	if _player_hud and "visible" in _player_hud:
		_player_hud.visible = true
		
	_debug("closed puzzle=%s reason=%s" % [String(closed_id), String(reason)])
	emit_signal("puzzle_closed", closed_id, reason)


func submit_puzzle() -> void:
	if active_puzzle == null:
		return

	# 1. 检查拼图是否完成
	if not active_puzzle.has_method("is_solved"):
		push_error("[PuzzleManager] submit failed: active puzzle missing is_solved()")
		return

	var solved_variant: Variant = active_puzzle.call("is_solved")
	var solved := solved_variant as bool
	
	if solved:
		_set_hud_hint("Solved! Level Complete!")
		_debug("submit success: %s" % String(active_puzzle_id))
		
		# [关键] 2. 异步播放胜利动画 (等待 finish_async)
		if active_puzzle.has_method("finish_async"):
			await active_puzzle.call("finish_async")
		
		emit_signal("puzzle_resolved", active_puzzle_id, true)
		
		# [关键] 3. 执行关卡跳转
		_emit_level_change_if_configured(active_puzzle_id)
		
		close_puzzle(&"success")
		return

	# --- 失败处理逻辑 ---
	if active_puzzle_id == PUZZLE_2_ID:
		_set_hud_hint("Puzzle 2 not complete")
		return # 不关闭，继续玩

	if active_puzzle_id == PUZZLE_1_ID:
		_set_hud_hint("Puzzle 1 not complete")
		return # 不关闭，继续玩

	_set_hud_hint("Not complete")


# ==============================================================================
# 辅助逻辑
# ==============================================================================

func cancel_puzzle() -> void:
	close_puzzle(&"cancel")


func reset_puzzle() -> void:
	if active_puzzle == null:
		return
	if active_puzzle.has_method("reset_to_initial"):
		active_puzzle.call("reset_to_initial")
		
		# [修改] 设置提示文字
		_set_hud_hint("Puzzle reset")
		
		# [新增] 创建一个临时的 Timer，1.5秒后清空文字
		get_tree().create_timer(1.5).timeout.connect(func(): _set_hud_hint(""))
		
	else:
		push_error("[PuzzleManager] reset failed: active puzzle missing reset_to_initial()")


func set_interactable(puzzle_id: StringName) -> void:
	if puzzle_id == &"":
		return
	current_interactable_id = puzzle_id
	# 可以加一个 "按 E 交互" 的提示 UI
	_debug("set_interactable: %s" % String(puzzle_id))


func clear_interactable(puzzle_id: StringName = &"") -> void:
	if puzzle_id == &"" or current_interactable_id == puzzle_id:
		current_interactable_id = &""
		_debug("clear_interactable")


func _emit_level_change_if_configured(puzzle_id: StringName) -> void:
	if not next_level_path_by_puzzle_id.has(String(puzzle_id)):
		push_warning("No next level configured for %s" % puzzle_id)
		return
		
	var next_path := next_level_path_by_puzzle_id[String(puzzle_id)] as String
	
	if next_path == "":
		return
		
	_debug("Requesting Level Change to: %s" % next_path)
	emit_signal("request_level_change", next_path)
	
	# [修改] 直接切换场景 (最稳妥的方式)
	print("🚀 [PuzzleManager] Switching Scene to: ", next_path)
	get_tree().change_scene_to_file(next_path)


# ==============================================================================
# 内部工具函数
# ==============================================================================

func _set_player_input_enabled(enabled: bool) -> void:
	if _player == null:
		return
	
	if not enabled:
		# --- 进入解谜 ---
		if _player.has_method("change_state"):
			_player.change_state(0) # 0 = Idle
			
		if "is_puzzle_locked" in _player:
			_player.is_puzzle_locked = true
			
		_player.set_physics_process(false)
		
		# [建议] 进入解谜时也先停一下战斗计时器，防止在解谜时后台倒计时结束乱切状态
		if _player.has_method("force_stop_combat"):
			_player.force_stop_combat()
			
	else:
		# --- 退出解谜 ---
		if "is_puzzle_locked" in _player:
			_player.is_puzzle_locked = false
			
		_player.set_physics_process(true)
		
		# [关键] 调用刚才写的新函数，彻底清洗状态！
		if _player.has_method("force_stop_combat"):
			_player.force_stop_combat()
		else:
			# 保底逻辑 (万一你忘了改 Player 脚本)
			if _player.has_method("change_state"):
				_player.change_state(0)


func _load_puzzle_scenes() -> void:
	if ResourceLoader.exists(PUZZLE_1_SCENE_PATH):
		_puzzle_1_scene = load(PUZZLE_1_SCENE_PATH) as PackedScene
	if ResourceLoader.exists(PUZZLE_2_SCENE_PATH):
		_puzzle_2_scene = load(PUZZLE_2_SCENE_PATH) as PackedScene
		
		# [新增] 加载第 3 关
	if ResourceLoader.exists(PUZZLE_FINAL_SCENE_PATH):
		_puzzle_final_scene = load(PUZZLE_FINAL_SCENE_PATH) as PackedScene
	else:
		push_error("[PuzzleManager] missing puzzle scene: %s" % PUZZLE_FINAL_SCENE_PATH)


func _self_check_paths() -> void:
	if _puzzle_layer == null: push_error("Missing node: ../PuzzleLayer")
	if _puzzle_root == null: push_error("Missing node: ../PuzzleLayer/PuzzleRoot")
	if _player == null: push_error("Missing node: ../Player")


func _get_scene_by_id(puzzle_id: StringName) -> PackedScene:
	if puzzle_id == PUZZLE_1_ID: return _puzzle_1_scene
	if puzzle_id == PUZZLE_2_ID: return _puzzle_2_scene
		# [新增] 如果是 puzzle_final，就返回第 3 关
	if puzzle_id == PUZZLE_FINAL_ID: return _puzzle_final_scene
	return null


func _connect_hud_buttons_once() -> void:
	if _esc_button:
		if not _esc_button.pressed.is_connected(cancel_puzzle):
			_esc_button.pressed.connect(cancel_puzzle)
		# [新增] 强制关闭焦点模式，防止键盘 ESC 键导致按钮卡死
		_esc_button.focus_mode = Control.FOCUS_NONE 

	if _submit_button:
		if not _submit_button.pressed.is_connected(submit_puzzle):
			_submit_button.pressed.connect(submit_puzzle)
		# [新增] 强制关闭焦点模式
		_submit_button.focus_mode = Control.FOCUS_NONE 

	if _reset_button:
		if not _reset_button.pressed.is_connected(reset_puzzle):
			_reset_button.pressed.connect(reset_puzzle)
		# [新增] 强制关闭焦点模式
		_reset_button.focus_mode = Control.FOCUS_NONE 


func _cache_hint_label() -> void:
	if hud_hint_label_path != NodePath():
		var node := get_node_or_null(hud_hint_label_path)
		if node is Label: _hint_label = node


func _set_hud_hint(text: String) -> void:
	if _hint_label: _hint_label.text = text
	if text != "": _debug("HUD: %s" % text)


func _set_puzzle_ui_visible(visible: bool) -> void:
	if _puzzle_layer: _puzzle_layer.visible = visible
	if _puzzle_hud: _puzzle_hud.visible = visible


func _debug(msg: String) -> void:
	print("[PuzzleManager] %s" % msg)

# 兼容旧信号连接 (如果UI里还连着这些空函数)
func _on_reset_pressed() -> void: reset_puzzle()
func _on_submit_pressed() -> void: submit_puzzle()
func _on_esc_pressed() -> void: cancel_puzzle()
