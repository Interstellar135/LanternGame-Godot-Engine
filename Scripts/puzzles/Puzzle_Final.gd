@tool
extends "puzzle.gd" # 继承你的基类

# 定义信号
signal solved 

func _ready():
	# 为了防止一瞬间完成玩家没反应过来，我们可以稍微停顿 0.1 秒
	# 或者直接立刻完成
	call_deferred("_auto_solve")

func _auto_solve():
	print("💡 灯火交互触发！自动完成...")
	# 直接发出胜利信号
	solved.emit()

# 必须实现的接口
func is_solved() -> bool:
	return true

# 异步结束：这里可以留白，或者播个音效
func finish_async() -> void:
	# 如果你想让“点亮”这个瞬间有一点点延迟感（比如播放点火声）
	# await get_tree().create_timer(0.5).timeout
	pass 
