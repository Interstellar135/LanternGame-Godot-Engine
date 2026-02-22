extends Control

# [必填] 主菜单路径 (用 export 选文件，防止写错)
@export_file("*.tscn") var main_menu_path: String = "res://Scenes/MainMenu.tscn"
# [新增] 引用滑条 (变量名随便起，后面 %HSlider 必须跟节点名一致)
@onready var volume_slider = $CenterContainer/VBoxContainer/HSlider

const MASTER_BUS_INDEX = 0

func _ready():
	# 1. 初始状态必须是隐藏的
	visible = false
	
	# 2. 连接按钮信号
	$CenterContainer/VBoxContainer/BtnResume.pressed.connect(_on_resume_pressed)
	$CenterContainer/VBoxContainer/BtnMenu.pressed.connect(_on_menu_pressed)
	
		# [新增] 1. 初始化滑条位置 (让它显示���前真实音量)
	if volume_slider:
		var current_db = AudioServer.get_bus_volume_db(MASTER_BUS_INDEX)
		volume_slider.value = db_to_linear(current_db)
		
		# [新增] 2. 连接信号
		volume_slider.value_changed.connect(_on_volume_changed)
		
# [新增] 音量控制函数
func _on_volume_changed(value: float):
	var db_volume = linear_to_db(value)
	AudioServer.set_bus_volume_db(MASTER_BUS_INDEX, db_volume)
	
	# 静音处理
	AudioServer.set_bus_mute(MASTER_BUS_INDEX, value < 0.05)

func _input(event):
	# 监听 ESC 键
	if event.is_action_pressed("ui_cancel"): # 默认 ESC 映射为 ui_cancel
		toggle_pause()

func toggle_pause():
	# 切换暂停状态
	var is_paused = not get_tree().paused
	get_tree().paused = is_paused
	
	# 显示/隐藏菜单
	visible = is_paused
	
	# 处理鼠标显示 (如果游戏里隐藏了鼠标，暂停时要显示出来)
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# 如果你是动作游戏，平时鼠标可能隐藏，这里根据情况改
		# Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN) 
		pass

func _on_resume_pressed():
	toggle_pause()

func _on_menu_pressed():
	# 切场景前必须先解冻！否则新场景也会卡住不动！
	get_tree().paused = false 
	
	if main_menu_path != "":
		get_tree().change_scene_to_file(main_menu_path)
	else:
		print("❌ 还没设置主菜单路径！")
