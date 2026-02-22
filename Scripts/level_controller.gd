extends Node2D

# --- 1. 关卡配置 (Inspector 设置) ---
@export_group("Level Config")
@export var next_level_path: String = ""          # 下一关的场景路径 (例如 res://scenes/level_indoor_f1.tscn)
@export var allow_qte_in_this_level: bool = true  # 本关是否允许使用 QTE (Outdoor设为false, 其它true)
@export var unlock_qte_when_cleared: bool = false # 通关后是否永久解锁 QTE (Outdoor设为true)

@export_group("Level Override")
@export var override_qte_setting: bool = false # 是否启用强制覆盖
@export var force_qte_state: bool = false      # 强制覆盖成什么状态

# --- 在脚本最开头添加这个变量 ---
@export_group("Scene Navigation")
# [修改] 改成 export_file，这样你在编辑器里直接选文件，绝对不会错
@export_file("*.tscn") var main_menu_path: String = "res://Scenes/MainMenu.tscn"
@export_file("*.tscn") var end_screen_path: String = "res://Scenes/EndScreen.tscn"
# 1. 顶部变量：只引用���加的亮图
@onready var map_light = $Map_Light 
# (如果报错说找不到，检查一下你是不是把图放到了别的子节点下面)

# --- 2. 节点引用 (请确保 LevelBase 结构里有这些节点) ---
@onready var enemies_container = $Enemies          # 敌人容器
@onready var interactables_container = $Interactables # 交互物容器
@onready var start_pos = $StartPos                 # 玩家出生点 (Marker2D)
@onready var player = $Player                      # 玩家实例
@onready var pause_menu = $HUD/PauseMenu           # 暂停菜单 (Control)

# 获取解密点 (倒三角)，名字要对应
@onready var puzzle_trigger = interactables_container.get_node_or_null("PuzzleTrigger")

# --- 3. 运行时变量 ---
var enemies_alive: int = 0
var is_puzzle_solved: bool = false

func _ready():
	# A. 初始化玩家位置
	if player and start_pos:
		player.global_position = start_pos.global_position
	
	# B. 应用技能锁 (根据存档 + 本关配置)
	_apply_skill_locks()
	
	# C. 初始化敌人统计
	_setup_enemies()
	
	# D. 初始化解密点 (连接信号)
	_setup_puzzle()
	
	# [新增] 专门监听 PuzzleManager 的全局信号 (用于最终演出)
	var manager = get_tree().get_first_node_in_group("puzzle_manager")
	if manager:
		if not manager.puzzle_resolved.is_connected(_on_final_puzzle_resolved):
			manager.puzzle_resolved.connect(_on_final_puzzle_resolved)

	# [新增] 确保地图初始状态
	if map_light: map_light.visible = false
	
	# E. 初始化暂停菜单
	if pause_menu:
		pause_menu.visible = false
		pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS # 确保暂停时菜单还能动

	# F. 监听玩家死亡
	if player:
		# 假设 Player 脚本里有 signal died，或者用 tree_exited 做兜底
		if player.has_signal("died"):
			player.died.connect(_on_player_died)
		else:
			# 如果没有专门信号，就检测节点移除
			player.tree_exited.connect(_on_player_died)
			
	if override_qte_setting:
		# 如果勾选了覆盖，就用关卡管理器的设置
		player.qte_unlocked = force_qte_state
	else:
		# 否则，还是读取全局存档 (或者保留 Player 自身的设置)
		player.qte_unlocked = GameState.is_qte_unlocked

# --- 4. 核心逻辑 ---

func _apply_skill_locks():
	# 读取全局存档 GameState，结合本关限制，决定玩家能不能用 QTE
	if player and "qte_unlocked" in player:
		# GameState.qte_unlocked 是存档里的状态
		# allow_qte_in_this_level 是本关的强制限制
		#player.qte_unlocked = GameState.qte_unlocked and allow_qte_in_this_level
		print("本关QTE状态: ", player.qte_unlocked)

func _setup_enemies():
	enemies_alive = 0
	for child in enemies_container.get_children():
		# 确保所有敌人都加了组 "enemy"
		if child.is_in_group("enemy"):
			enemies_alive += 1
			# 监听敌人移除 (死亡)
			child.tree_exited.connect(_on_enemy_killed)
	
	print("关卡初始化，敌人剩余: ", enemies_alive)
	# 如果是纯解密关没有怪，直接刷新一次锁状态
	if enemies_alive == 0:
		_update_puzzle_lock_state()

func _on_enemy_killed():
	enemies_alive -= 1
	# print("敌人剩余: ", enemies_alive)
	if enemies_alive <= 0:
		enemies_alive = 0
		print("区域清空！可以解密了")
		_update_puzzle_lock_state()

func _setup_puzzle():
	# 初始化解密点状态
	_update_puzzle_lock_state()
	
	# 连接解密请求信号 (你的解密点脚本里需要 signal interact_requested)
	if puzzle_trigger and puzzle_trigger.has_signal("interact_requested"):
		if not puzzle_trigger.interact_requested.is_connected(_on_puzzle_interact):
			puzzle_trigger.interact_requested.connect(_on_puzzle_interact)

func _update_puzzle_lock_state():
	if not puzzle_trigger: return
	
	if enemies_alive <= 0:
		# 怪清完了 -> 激活
		if puzzle_trigger.has_method("activate"):
			puzzle_trigger.activate()
	else:
		# 还有怪 -> 锁定
		if puzzle_trigger.has_method("deactivate"):
			puzzle_trigger.deactivate()

# --- 5. 解密与通关流程 ---

func _on_puzzle_interact():
	print("收到解密请求，启动解密逻辑...")
	# 可以在这里暂停游戏，弹出解密UI
	# 这里模拟直接成功，对接时请替换为你的解密回调
	_on_puzzle_success() 

# 当解密成功时��用
func _on_puzzle_success():
	is_puzzle_solved = true
	_try_finish_level()

# 当解密失败时调用
func _on_puzzle_failed():
	is_puzzle_solved = false
	print("解密失败，状态重置")
	# 这里不需要重置关卡，只需要让解密点可以再次交互

func _try_finish_level():
	if enemies_alive <= 0 and is_puzzle_solved:
		print("达成通关条件！")
		_level_complete()

func _level_complete():
	# 1. 解锁奖励 (如果本关配置了)
	if unlock_qte_when_cleared:
		GameState.qte_unlocked = true
	
	# 2. 存档 & 跳转
	if next_level_path != "":
		GameState.current_level_path = next_level_path
		GameState.save_game() # 自动存档
		get_tree().change_scene_to_file(next_level_path)
	else:
		print("没有下一关配置，可能是最后一关？")
		# 可以在这里跳转到 EndGame 场景
		# get_tree().change_scene_to_file("res://scenes/EndGame.tscn")

# --- 6. 玩家死亡逻辑 ---

func _on_player_died():
	print("玩家死亡，稍后重置...")
	# 1秒后重载当前场景
	await get_tree().create_timer(1.0).timeout
	get_tree().reload_current_scene()

# --- 7. 输入与暂停菜单 ---

# LevelControl.gd

func _unhandled_input(event):
	# 这里不需要任何 puzzle_mode 的判断逻辑了
	# 因为如果 PuzzleManager 在工作，它会把 ESC 拦截下来，
	# 导致代码根本跑不到这一行。能跑道这一行，说明一定没在解谜。
	
	if event.is_action_pressed("ui_cancel"): 
		print("LevelControl: 收到 ESC (未被拦截)，切换暂停")
		_toggle_pause()

func _toggle_pause():
	if not pause_menu: return
	
	var is_paused = not get_tree().paused
	get_tree().paused = is_paused # 冻结游戏
	pause_menu.visible = is_paused # 显示菜单
	
	# 可选：显示/隐藏鼠标
	# Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_HIDDEN)

# --- 暂停菜单按钮的回调 (请手动连接信号到这些函数) ---

func _on_btn_resume_pressed():
	_toggle_pause() # 再次切换=取消暂停

func _on_btn_save_pressed():
	# 保存当前关卡进度
	GameState.current_level_path = scene_file_path
	GameState.save_game()
	
	# 如果有提示文字Label，可以在这里更新一下
	print("进度已保存")
	# 简单反馈：把按钮文字变一下
	var btn = pause_menu.find_child("BtnSave", true, false)
	if btn:
		btn.text = "已保存!"
		btn.disabled = true
		await get_tree().create_timer(1.0).timeout
		if btn:
			btn.text = "保存进度"
			btn.disabled = false

func _on_btn_quit_pressed():
	_toggle_pause() # 切场景前必须解冻！
	
	# [修改] 使用变量跳转，而不是写死字符串
	if main_menu_path != "":
		get_tree().change_scene_to_file(main_menu_path)
	else:
		print("❌ 错误：未设置主菜单路径！")
	
	
# [新增] 最终演出回调
func _on_final_puzzle_resolved(puzzle_id: StringName, success: bool):
	# 只有是最终谜题才触发
	if puzzle_id == &"puzzle_final" and success:
		print("🎉 收到最终信号！开始结局演出...")
		_play_ending_sequence()

# [新增] 演出流程
# [新增] 演出流程
func _play_ending_sequence():
	print("💡 亮灯！开启剧情绝对锁定...")
	
	if player:
		# 1. [关键] 开启剧情锁 (无视 PuzzleManager 的干扰)
		if "is_cutscene_locked" in player:
			player.is_cutscene_locked = true
		
		# 2. 视觉修正：变成站立
		if player.has_method("change_state"):
			player.change_state(0) # Idle
		if "velocity" in player:
			player.velocity = Vector2.ZERO
			
		# 3. 强制播放普通待机 (防止卡在战斗待机)
		# 假设你的 Player 脚本里有 anim 引用
		if "anim" in player:
			player.anim.play("Idle_Normal") # 或者你定义的常量名
	
	# --- 3. 视觉演出 ---
	if map_light:
		map_light.visible = true 
	
	# --- 4. 等待跳转 ---
	await get_tree().create_timer(3.0).timeout
	
	# 跳转逻辑 (保持你现在的代码)
	var target_path = end_screen_path
	if target_path == "": target_path = "res://Scenes/EndScreen.tscn"
	get_tree().change_scene_to_file(target_path)
