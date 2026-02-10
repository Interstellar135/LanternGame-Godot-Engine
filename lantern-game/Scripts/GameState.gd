extends Node

# 存档文件保存在用户数据目录，跨平台通用
const SAVE_PATH := "user://save.json"

# --- 核心存档数据 ---
# 默认第一关路径 (请确保这个路径和你实际的文件路径一致！)
var current_level_path: String = "res://scenes/level_outdoor.tscn" 
var qte_unlocked: bool = false # QTE技能状态

# 开始新游戏时重置数据
func new_game():
	current_level_path = "res://scenes/level_outdoor.tscn"
	qte_unlocked = false
	save_game()

# 保存数据到硬盘
func save_game():
	var data := {
		"current_level_path": current_level_path,
		"qte_unlocked": qte_unlocked,
	}
	var json_string := JSON.stringify(data)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		print("存档成功")

# 从硬盘读取数据
# 返回 true 表示读取成功，返回 false 表示没有存档
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false # 没有存档文件

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var content := file.get_as_text()
	
	var parsed_data = JSON.parse_string(content)
	
	if typeof(parsed_data) != TYPE_DICTIONARY:
		return false # 存档文件损坏
		
	# 读取数据，如果没有找到对应字段就使用默认值
	current_level_path = parsed_data.get("current_level_path", "res://scenes/level_outdoor.tscn")
	qte_unlocked = parsed_data.get("qte_unlocked", false)
	
	print("读档成功：关卡->", current_level_path, " QTE解锁->", qte_unlocked)
	return true
