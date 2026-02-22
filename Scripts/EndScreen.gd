extends Control

# 当点击“重新游玩”按钮时 -> 返回主菜单
func _on_restart_button_pressed():
	# 重要：如果你的游戏结束是通过“暂停”实现的，必须先解除暂停，否则跳回主菜单后游戏还是卡住的
	get_tree().paused = false 
	
	# 跳转到主菜单场景
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

# 当点击“退出”按钮时 -> 关闭游戏
func _on_quit_button_pressed():
	# 直接退出应用程序
	get_tree().quit()
