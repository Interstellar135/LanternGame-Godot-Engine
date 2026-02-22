extends Node

# 记录当前音量 (0.0 到 1.0)
var master_volume: float = 1.0

# 更新音量的方法
func update_volume(value: float):
	master_volume = value
	
	# 获取 Master (主总线) 的索引，通常是 0
	var bus_index = AudioServer.get_bus_index("Master")
	
	# 将 0-1 的线性值转换为分贝 (dB)
	# 如果值太小（接近0），直接静音 (-80dB)
	if value > 0.01:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
	else:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
