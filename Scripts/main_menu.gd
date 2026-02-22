extends Control

# 当脚本挂载后，你需要手动连接信号，或者在编辑器里连接
# 这里假设你通过编辑器将按钮的 pressed 信号连接到了这里

func _on_start_button_pressed():
	# 跳转到室内关卡
	# 注意：请确保你的关卡路径是正确的
	get_tree().change_scene_to_file("res://Scenes/Level_Outdoor.tscn")

func _on_settings_button_pressed():
	# 跳转到设置界面
	get_tree().change_scene_to_file("res://Scenes/SettingsMenu.tscn")

func _on_quit_button_pressed():
	# 退出游戏
	get_tree().quit()
