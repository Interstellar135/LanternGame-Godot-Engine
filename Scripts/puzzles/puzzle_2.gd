# ============================================================================
# Puzzle_2.gd
# 功能：管理18个可拖拽的瓷砖，放置到对应的槽位，完成拼图
# ============================================================================

extends Control

# 信号：谜题完成时发出（success=true表示全部放置正确）
signal completed(success: bool)

# 常量定义
const SLOT_COUNT := 18  # 总共18个槽位和瓷砖
const EMPTY := -1       # 槽位为空的标记值

# 导出参数：成功时需要显示的节点列表（例如胜利动画节点）
@export var success_nodes: Array[NodePath] = []

# 关键数据结构
# slot_to_tile[slot_id] = tile_id 表示哪个瓷砖在哪个槽位
var slot_to_tile: PackedInt32Array = PackedInt32Array()
# tile_to_slot[tile_id] = slot_id 表示瓷砖当前所在的槽位
var tile_to_slot: PackedInt32Array = PackedInt32Array()
# tile_correct_slot[tile_id] = correct_slot_id 表示瓷砖正确的位置
var tile_correct_slot: PackedInt32Array = PackedInt32Array()

# UI状态
# 用户当前选中了哪个瓷砖（-1表示未选中）
var selected_tile_id := -1

# 节点缓存（提高性能，避免重复查询）
# _tile_nodes[tile_id] 存储对应 ID 的瓷砖节点
var _tile_nodes: Array[TextureRect] = []
# _slot_nodes[slot_id] 存储对应 ID 的槽位节点
var _slot_nodes: Array[TextureRect] = []
# _slot_global_positions[slot_id] 存储槽位的全局坐标（用于放置瓷砖）
var _slot_global_positions: Array[Vector2] = []

# 场景树引用
var _tiles_layer: Node  # tiles_layer 容器（包含所有瓷砖）
var _slots_layer: Node  # slots 容器（定义所有槽位）


# ============================================================================
# 初始化流程：获取节点引用 → 收集子节点 → 验证 → 建立映射 → 连接信号 → 重置状态
# ============================================================================
func _ready() -> void:
	
	# 步骤1：获取容器节点引用（缓存以提高性能）
	_tiles_layer = get_node("tiles_layer")  # 瓷砖容器（自身visible=true时瓷砖才能显示）
	_slots_layer = get_node("slots")         # 槽位容器（定义18个放置位置）

	# 步骤2：遍历容器，收集所有 tile_XX 和 slot_XX 节点，建立ID映射
	_collect_tile_and_slot_nodes()
	
	# 步骤3：验证所有必需节点都存在（如缺失则停止初始化）
	if not _validate_required_nodes():
		return
	
	# 步骤4：建立"瓷砖正确位置"的映射（简单策略：tile_id == correct_slot_id）
	_build_correct_mapping()
	
	# 步骤5：缓存所有槽位的全局坐标（用于后续放置瓷砖）
	_capture_slot_global_positions()
	
	# 步骤6：为所有瓷砖和槽位连接 gui_input 信号
	_connect_gui_input_handlers()
	
	# 步骤7：重置到初始状态（随机排列，显示UI）
	reset_to_initial()
	
	# 调试日志：确认初始化完成
	print("[Puzzle_2] _ready() completed - %d tiles, %d slots initialized" % [_tile_nodes.size(), _slot_nodes.size()])


# ============================================================================
# 扫描场景树，收集所有瓷砖和槽位节点，按名称后缀ID进行索引
# 例如: tile_00 → _tile_nodes[0], slot_05 → _slot_nodes[5]
# ============================================================================
func _collect_tile_and_slot_nodes() -> void:
	# 预分配数组大小（18个元素），初始值为 null
	_tile_nodes.resize(SLOT_COUNT)
	_slot_nodes.resize(SLOT_COUNT)
	
	# 初始化所有元素为 null（防止未初始化的访问）
	for i in range(SLOT_COUNT):
		_tile_nodes[i] = null
		_slot_nodes[i] = null

	# 遍历 tiles_layer 的所有子节点
	for child in _tiles_layer.get_children():
		# 检查是否为 TextureRect 类型（瓷砖节点）
		if child is TextureRect:
			var tile_node := child as TextureRect
			# 从节点名称提取 ID（tile_00 → 0, tile_17 → 17）
			var tile_id := _parse_suffix_id(tile_node.name, "tile_")
			# 验证 ID 在有效范围内
			if tile_id >= 0 and tile_id < SLOT_COUNT:
				_tile_nodes[tile_id] = tile_node

	# 遍历 slots 的所有子节点
	for child in _slots_layer.get_children():
		# 检查是否为 TextureRect 类型（槽位节点）
		if child is TextureRect:
			var slot_node := child as TextureRect
			# 从节点名称提取 ID（slot_00 → 0, slot_17 → 17）
			var slot_id := _parse_suffix_id(slot_node.name, "slot_")
			# 验证 ID 在有效范围内
			if slot_id >= 0 and slot_id < SLOT_COUNT:
				_slot_nodes[slot_id] = slot_node


# ============================================================================
# 验证所有18个瓷砖和槽位都已正确加载
# 如果有缺失，打印错误并返回 false（触发 _ready() 提前返回）
# ============================================================================
func _validate_required_nodes() -> bool:
	var ok := true  # 标志：是否通过验证
	
	# 逐一检查 18 个瓷砖
	for i in range(SLOT_COUNT):
		if _tile_nodes[i] == null:
			# 缺失瓷砖节点，打印错误并标记失败
			push_error("Missing tile node: tile_%02d" % i)
			ok = false
		# 逐一检查 18 个槽位
		if _slot_nodes[i] == null:
			# 缺失槽位节点，打印错误并标记失败
			push_error("Missing slot node: slot_%02d" % i)
			ok = false
	
	return ok


# ============================================================================
# 建立"正确答案"映射：定义每个瓷砖应该放在哪个槽位
# 当前规则：tile_id == correct_slot_id（瓷砖0放在槽位0，瓷砖1放在槽位1...）
# ============================================================================
func _build_correct_mapping() -> void:
	# 清空并重新分配数组
	tile_correct_slot = PackedInt32Array()
	tile_correct_slot.resize(SLOT_COUNT)
	
	# 对每个瓷砖，设置其正确的槽位 ID（简单: tile_id == slot_id）
	for tile_id in range(SLOT_COUNT):
		tile_correct_slot[tile_id] = tile_id


# ============================================================================
# 缓存所有槽位的全局坐标，后续放置瓷砖时直接使用
# 这样避免每次放置时都重新计算位置
# ============================================================================
func _capture_slot_global_positions() -> void:
	# 预分配数组大小
	_slot_global_positions.resize(SLOT_COUNT)
	
	for slot_id in range(SLOT_COUNT):
		var s := _slot_nodes[slot_id]  # 获取槽位节点
		
		# 如果槽位节点不存在，使用默认坐标
		if s == null:
			_slot_global_positions[slot_id] = Vector2.ZERO
			continue
		
		# 记录槽位的全局坐标（后续用于放置瓷砖）
		_slot_global_positions[slot_id] = s.global_position


# ============================================================================
# 为所有瓷砖和槽位连接 gui_input 信号处理器
# 使用 Godot 4 信号连接方式（Callable + bind 传递参数）
# ============================================================================
func _connect_gui_input_handlers() -> void:
	# 为所有瓷砖连接 gui_input 信号
	for tile_id in range(SLOT_COUNT):
		var tile_node := _tile_nodes[tile_id]  # 获取瓷砖节点
		
		# 跳过不存在的节点
		if tile_node == null:
			continue
		
		# 创建回调信息：调用 _on_tile_gui_input，并绑定 tile_id 参数
		var tile_callable := Callable(self, "_on_tile_gui_input").bind(tile_id)
		
		# Godot 4 信号连接方式：只有尚未连接时才连接（防止重复连接）
		if not tile_node.gui_input.is_connected(tile_callable):
			tile_node.gui_input.connect(tile_callable)

	# 为所有槽位连接 gui_input 信号
	for slot_id in range(SLOT_COUNT):
		var slot_node := _slot_nodes[slot_id]  # 获取槽位节点
		
		# 跳过不存在的节点
		if slot_node == null:
			continue
		
		# 创建回调信息：调用 _on_slot_gui_input，并绑定 slot_id 参数
		var slot_callable := Callable(self, "_on_slot_gui_input").bind(slot_id)
		
		# Godot 4 信号连接方式：只有尚未连接时才连接（防止重复连接）
		if not slot_node.gui_input.is_connected(slot_callable):
			slot_node.gui_input.connect(slot_callable)


# ============================================================================
# 瓷砖点击处理器：玩家点击瓷砖时调用
# 功能：记录用户选中的瓷砖 ID
# ============================================================================
func _on_tile_gui_input(event: InputEvent, tile_id: int) -> void:
	# 检查是否为鼠标左键按下事件
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 确保是左键且处于按下状态（不是释放）
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 记录当前选中的瓷砖 ID
			selected_tile_id = tile_id


# ============================================================================
# 槽位点击处理器：玩家点击槽位时调用
# 功能：将选中的瓷砖放置到当前槽位，验证是否完成
# ============================================================================
func _on_slot_gui_input(event: InputEvent, slot_id: int) -> void:
	# 检查是否为鼠标左键按下事件
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# 确保是左键且处于按下状态（不是释放）
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 检查是否有瓷砖被选中（selected_tile_id == -1 表示未选中）
			if selected_tile_id == -1:
				return
			
			# 将选中的瓷砖放置到当前槽位
			place(selected_tile_id, slot_id)
			
			# 检查是否已完成谜题，并更新成功UI显示
			set_success_visual(is_solved())


# ============================================================================
# 核心放置逻辑：将瓷砖放入槽位，并处理交换逻辑
# 规则：
#   - 如果槽位为空，直接将瓷砖放入
#   - 如果槽位有其他瓷砖，执行交换（两瓷砖互换位置）
# ============================================================================
func place(tile_id: int, slot_id: int) -> void:
	# 验证 tile_id 的合法性
	if tile_id < 0 or tile_id >= SLOT_COUNT:
		return
	
	# 验证 slot_id 的合法性
	if slot_id < 0 or slot_id >= SLOT_COUNT:
		return

	# 获取该瓷砖当前所在的槽位
	var old_slot := tile_to_slot[tile_id]
	
	# 如果瓷砖已经在该槽位，直接移动（刷新位置）并返回
	if old_slot == slot_id:
		_move_tile_to_slot(tile_id, slot_id)
		return

	# 获取目标槽位中已有的瓷砖（如果有的话）
	var tile_old := slot_to_tile[slot_id]

	# 清空瓷砖的旧槽位
	if old_slot != EMPTY:
		slot_to_tile[old_slot] = EMPTY

	# 如果目标槽位中有其他瓷砖，执行交换
	if tile_old != EMPTY:
		# 将旧瓷砖移动到该瓷砖的旧槽位
		tile_to_slot[tile_old] = old_slot
		# 如果旧槽位不为空，更新旧槽位的映射关系
		if old_slot != EMPTY:
			slot_to_tile[old_slot] = tile_old
			# 立即刷新旧瓷砖的显示位置
			_move_tile_to_slot(tile_old, old_slot)

	# 将当前瓷砖放入目标槽位
	slot_to_tile[slot_id] = tile_id
	tile_to_slot[tile_id] = slot_id
	
	# 刷新当前瓷砖的显示位置
	_move_tile_to_slot(tile_id, slot_id)


# ============================================================================
# 检查拼图是否已完成：所有瓷砖都放在了正确的位置
# 返回值：true = 全部正确，false = 有未放置或位置错误的瓷砖
# ============================================================================
func is_solved() -> bool:
	# 逐一检查每个槽位
	for slot_id in range(SLOT_COUNT):
		# 获取该槽位中的瓷砖 ID
		var tile_id := slot_to_tile[slot_id]
		
		# 如果槽位为空（未放置瓷砖），则未完成
		if tile_id == EMPTY:
			return false
		
		# 如果瓷砖不在其正确位置，则未完成
		if tile_correct_slot[tile_id] != slot_id:
			return false
	
	# 所有槽位都已正确放置
	return true


# ============================================================================
# 重置谜题到初始状态
# 功能：清除选中、打乱瓷砖、隐藏成功UI
# ============================================================================
func reset_to_initial() -> void:
	# 清除玩家的选择
	selected_tile_id = -1
	
	# 重新排列瓷砖（打乱但确保无法直接看出答案）
	_rebuild_derangement_layout()
	
	# 隐藏成功UI（这样 is_solved 会返回 false）
	set_success_visual(false)


# ============================================================================
# 设置成功UI的可见性，并发出完成信号
# 参数：should_show - true 表示显示成功UI，false 表示隐藏
# 这里不使用 "visible" 作为参数名，避免与基类属性冲突
# ============================================================================
func set_success_visual(should_show: bool) -> void:
	# 遍历所有需要显示的成功节点（在检查器中配置）
	for path in success_nodes:
		# 跳过空的 NodePath
		if path == NodePath():
			continue
		
		# 根据路径获取节点
		var n := get_node_or_null(path)
		
		# 检查节点是否存在且为 CanvasItem（可视节点的基类）
		if n is CanvasItem:
			# 设置节点的可见性
			(n as CanvasItem).visible = should_show
	
	# 如果是显示成功状态（完成谜题），发出信号
	if should_show:
		completed.emit(true)


# ============================================================================
# 初始化随机排列：创建一个"错排"，确保所有瓷砖都不在正确位置
# 算法：旋转排列（slot_to_tile[slot] = (slot + 1) % 18）
# 效果：没有瓷砖在正确位置，但排列是确定性的（便于调试和一致性）
# ============================================================================
func _rebuild_derangement_layout() -> void:
	# 清空并重新分配映射数组
	slot_to_tile = PackedInt32Array()
	tile_to_slot = PackedInt32Array()
	slot_to_tile.resize(SLOT_COUNT)
	tile_to_slot.resize(SLOT_COUNT)

	# 初始化所有位置为空
	for i in range(SLOT_COUNT):
		slot_to_tile[i] = EMPTY
		tile_to_slot[i] = EMPTY

	# 构建旋转排列：tile_id = (slot_id + 1) % SLOT_COUNT
	# 例如：slot0→tile1, slot1→tile2, ..., slot17→tile0
	# 保证：对所有 slot，slot_to_tile[slot] != slot（没有瓷砖在正确位置）
	for slot_id in range(SLOT_COUNT):
		var tile_id := (slot_id + 1) % SLOT_COUNT
		slot_to_tile[slot_id] = tile_id
		tile_to_slot[tile_id] = slot_id

	# 刷新所有瓷砖的显示位置
	for slot_id in range(SLOT_COUNT):
		var tile_id := slot_to_tile[slot_id]
		_move_tile_to_slot(tile_id, slot_id)


# ============================================================================
# 更新瓷砖的屏幕位置：将瓷砖移动到指定槽位的坐标
# 功能：瓷砖的物理位置不变（仍在 tiles_layer），但显示坐标更新
# ============================================================================
func _move_tile_to_slot(tile_id: int, slot_id: int) -> void:
	# 验证瓷砖 ID 的合法性
	if tile_id < 0 or tile_id >= _tile_nodes.size():
		return
	
	# 获取瓷砖节点
	var tile_node := _tile_nodes[tile_id]
	if tile_node == null:
		return
	
	# 验证槽位 ID 的合法性
	if slot_id < 0 or slot_id >= _slot_global_positions.size():
		return
	
	# 获取目标槽位的全局坐标
	var dest := _slot_global_positions[slot_id]
	
	# 设置瓷砖的全局位置（这样瓷砖会移动到槽位的位置）
	tile_node.global_position = dest


# ============================================================================
# 解析节点名称，提取数字后缀作为 ID
# 例如：_parse_suffix_id("tile_05", "tile_") → 5
#      _parse_suffix_id("slot_12", "slot_") → 12
# 返回值：-1 表示解析失败
# ============================================================================
func _parse_suffix_id(node_name: String, prefix: String) -> int:
	# 检查节点名是否以前缀开头
	if not node_name.begins_with(prefix):
		return -1
	
	# 提取前缀后的后缀部分（数字部分）
	var suffix := node_name.substr(prefix.length())
	
	# 后缀必须恰好是2个字符（00 到 17）
	if suffix.length() != 2:
		return -1
	
	# 检查后缀是否为有效的整数字符串
	if not suffix.is_valid_int():
		return -1
	
	# 转换为整数并返回
	return int(suffix)
