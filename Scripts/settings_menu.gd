extends Control

# [必填] 主菜单路径
@export_file("*.tscn") var main_menu_path: String = "res://Scenes/MainMenu.tscn"

@onready var master_slider = $MarginContainer/TabContainer/音量设置/HSlider
@onready var btn_back = $BtnBack

func _ready():
	# 1. 连接返回按钮
	btn_back.pressed.connect(_on_back_pressed)
	
	# 2. 初始化滑条位置 (读取当前实际音量)
	# AudioServer.get_bus_volume_db(0) 得到的是分贝，要转回 0~1
	var current_db = AudioServer.get_bus_volume_db(0)
	master_slider.value = db_to_linear(current_db)
	
	# 3. 连接滑条信号
	master_slider.value_changed.connect(_on_volume_changed)

func _on_volume_changed(value: float):
	# value 是 0.0 到 1.0
	# 如果拉到最底，直接静音
	var db_volume = linear_to_db(value)
	
	# 0 是 Master 总线 (Master Bus)
	AudioServer.set_bus_volume_db(0, db_volume)
	
	# 处理完全静音的情况 (避免还有微弱声音)
	AudioServer.set_bus_mute(0, value < 0.01)

func _on_back_pressed():
	# 返回主菜单
	if main_menu_path != "":
		get_tree().change_scene_to_file(main_menu_path)
