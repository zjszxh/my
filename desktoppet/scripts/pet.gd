# Godot 4.0+ GDScript
# 这个脚本控制桌面宠物的行为，包括移动、对话以及基于疲劳值改变游戏状态。

extends Node2D

# 使用 @onready 确保节点在 _ready() 函数中可用
@onready var animated_sprite = $AnimatedSprite2D
@onready var area_2d = $Area2D
@onready var dialogue_label = $DialogueLabel # 用于对话气泡的 Label 节点
@onready var distance_label = $DistanceLabel # 用于显示行走距离的 Label
@onready var fatigue_label = $FatigueLabel # 用于显示疲劳值的 Label
@onready var game_over_label = $GameOverLabel # 游戏结束标签
@onready var restart_button = $RestartButton # 重启按钮

# 拖拽状态变量
var is_dragging = false
var drag_offset = 0.0
# 检查是否已显示过拖拽对话
var is_dragging_dialogue_shown = false
# 拖拽开始时的鼠标位置
var drag_start_pos = Vector2.ZERO
# 拖拽被识别为开始的最小距离
const DRAG_THRESHOLD = 5.0

# 自动移动状态变量
var walk_direction = Vector2.ZERO
var walk_timer = 0.0
const WALK_DURATION_MIN = 3.0  # 最小行走时间
const WALK_DURATION_MAX = 8.0  # 最大行走时间
const WALK_SPEED = 100.0       # 行走速度
const IDLE_DURATION_MAX = 5.0  # 最大空闲时间
const DOWN_DURATION_MAX = 60.0 # 最大倒地状态持续时间 (1分钟)
var down_timer = 0.0 # 倒地状态计时器
# 新增: 连续行走周期计数器和最大值，用于空闲保底机制
var consecutive_walk_cycles = 0
const MAX_WALK_CYCLES = 5

# 疲劳值变量
var fatigue_value = 0.0
const MAX_FATIGUE = 100.0
# 梯度疲劳值增长率
const FATIGUE_PER_METER_MIN = 0.2
const FATIGUE_PER_METER_MAX = 0.4
# 达到最大增长率的疲劳值
const FATIGUE_RATE_MAX_START = 70.0
# 疲劳恢复量 - 调整以确保疲劳值能够有效累积
const FATIGUE_RECOVERY_IDLE_PER_SECOND = 0.5
const FATIGUE_RECOVERY_DOWN = 8.0 # 从 10.0 降至 5.0

# 累积距离变量
var total_walk_distance = 0.0 # 累积行走距离 (像素)
# 新增: 记录上次倒地以来的行走距离，用于触发强制倒地
var distance_since_last_down = 0.0
const PIXELS_PER_METER = 50.0 # 50 像素 = 1 米

# 跟踪之前的全局位置，用于更新鼠标穿透区域
var last_global_position = Vector2.ZERO
# 获取屏幕尺寸
var screen_size = DisplayServer.screen_get_size()

# 枚举不同宠物状态
enum States { IDLE, WALK, DEATH, DOWN, GAME_OVER }
var current_state = States.IDLE

# 对话列表
const NORMAL_DIALOGUES = ["看见了某", "走呀走", "丫二丫", "溜达溜达","该你了！","无利不起早"]
const TIRED_DIALOGUES = ["有点累", "坚持一下", "再走200m", "减肥太苦了","呼呼...","今晚吃好的"]

func _ready():
	# 定义固定窗口高度
	const WINDOW_HEIGHT = 200
	
	# 设置窗口尺寸：宽度为屏幕宽度，高度为固定值
	DisplayServer.window_set_size(Vector2i(screen_size.x, WINDOW_HEIGHT))
	
	# 设置窗口位置：位于屏幕底部，水平居中
	var window_pos_x = 0
	var window_pos_y = screen_size.y - WINDOW_HEIGHT
	DisplayServer.window_set_position(Vector2i(window_pos_x, window_pos_y))
	
	# 设置窗口标志，使其透明并允许鼠标穿透
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)

	# 设置角色初始位置在窗口中央
	var window_center_x = screen_size.x / 2
	position.x = window_center_x
	position.y = WINDOW_HEIGHT / 2 # 宠物的 y 坐标是窗口的中心
	
	# 初始化自动移动计时器，确保初始状态为空闲
	current_state = States.IDLE
	walk_timer = randf_range(0.0, IDLE_DURATION_MAX)
	
	# DEBUG: 将初始疲劳值设置为95用于测试，之后可以注释掉
	#fatigue_value = 95.0
	
	# 初始化对话气泡，并隐藏它
	dialogue_label.hide()
	set_dialogue_style()
	
	# 初始化距离标签，并使其可见
	distance_label.show()
	set_distance_style()
	
	# 初始化疲劳值标签，并使其可见
	fatigue_label.show()
	set_fatigue_style()

	# 初始化游戏结束标签和重启按钮，并隐藏它们
	game_over_label.hide()
	set_game_over_style()
	restart_button.hide()
	# 连接重启按钮的 pressed 信号到 restart_game 函数
	restart_button.pressed.connect(restart_game)
	
	# 初始设置鼠标穿透区域
	setup_mouse_passthrough()
	# 记录初始位置
	last_global_position = global_position
	
	# 连接动画播放完成的信号
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
	# 确保所有变量都已初始化
	if consecutive_walk_cycles == null:
		consecutive_walk_cycles = 0

# 动画播放完成时调用的函数
func _on_animation_finished():
	# 如果当前动画是 "death"
	if animated_sprite.animation == "death":
		# 在死亡动画播放完后，切换到 "down"（倒地）动画
		current_state = States.DOWN
		animated_sprite.play("down")
		# 重置倒地计时器
		down_timer = DOWN_DURATION_MAX

# 每一帧都调用的函数
func _process(delta):
	# 修复: 检查游戏是否结束，如果是，则停止所有逻辑
	if current_state == States.GAME_OVER:
		return
		
	# 如果宠物正在被拖拽，则阻止自动移动
	if is_dragging:
		# 根据水平鼠标移动更新宠物的 x 坐标
		var new_x = get_global_mouse_position().x + drag_offset
		# 将宠物的 x 坐标限制在窗口边界内
		position.x = clamp(new_x, get_viewport().size.x / 2 - screen_size.x / 2, get_viewport().size.x / 2 + screen_size.x / 2)
		
		# 拖拽时保持 "idle" 动画
		if animated_sprite.animation != "idle":
			animated_sprite.play("idle")
		
		# 只有当鼠标移动超过阈值时才显示持久性对话
		if not is_dragging_dialogue_shown and get_global_mouse_position().distance_to(drag_start_pos) > DRAG_THRESHOLD:
			is_dragging_dialogue_shown = true
			show_persistent_dialogue("拉我干啥？")
		
	else:
		# 自动移动逻辑
		walk_timer -= delta
		if walk_timer <= 0:
			# 如果角色处于空闲或行走状态，则改变状态
			if current_state != States.DOWN and current_state != States.DEATH:
				_change_movement_state()
		
		# 根据疲劳值计算速度
		var current_walk_speed = WALK_SPEED
		var current_anim_speed = 1.0 # 默认动画速度
		
		# 使用平滑插值来调整速度和动画倍速
		if fatigue_value >= 40.0 and fatigue_value <= 60.0:
			var t = (fatigue_value - 40.0) / 20.0 # 将疲劳值归一化到 0-1 范围
			current_walk_speed = lerp(WALK_SPEED, WALK_SPEED / 2.0, t)
			current_anim_speed = lerp(1.0, 0.7, t) # 将动画速度平滑降至 0.7
		elif fatigue_value > 60.0:
			# 疲劳值超过60后，速度和动画倍速都固定为最低值
			current_walk_speed = WALK_SPEED / 2.0
			current_anim_speed = 0.7
		
		if current_state == States.WALK:
			# 更新精灵朝向
			if walk_direction.x > 0:
				animated_sprite.flip_h = false
			elif walk_direction.x < 0:
				animated_sprite.flip_h = true
			
			# 设置动画播放倍速
			animated_sprite.speed_scale = current_anim_speed
			
			# 在窗口内更新角色的位置
			var new_pos = position + walk_direction * current_walk_speed * delta
			
			# 累积行走距离和疲劳值
			var walked_pixels = (walk_direction * current_walk_speed * delta).length()
			total_walk_distance += walked_pixels
			distance_since_last_down += walked_pixels # 新增：更新倒地以来的距离
			
			# 使用分段式疲劳值增长
			var current_fatigue_rate
			if fatigue_value <= 40:
				current_fatigue_rate = 0.2
			elif fatigue_value <= 70:
				current_fatigue_rate = 0.3
			else:
				current_fatigue_rate = 0.4
			
			fatigue_value += walked_pixels / PIXELS_PER_METER * current_fatigue_rate
			
			# 边界检查
			var viewport_center_x = get_viewport().size.x / 2
			var left_bound = viewport_center_x - screen_size.x / 2
			var right_bound = viewport_center_x + screen_size.x / 2
			
			# 如果角色碰到左右边界，反转移动方向
			if (new_pos.x <= left_bound and walk_direction.x < 0) or (new_pos.x >= right_bound and walk_direction.x > 0):
				walk_direction.x *= -1
			
			position = new_pos

		# 根据当前状态播放动画并更新疲劳值
		match current_state:
			States.IDLE:
				if animated_sprite.animation != "idle":
					animated_sprite.play("idle")
				# 空闲时每秒减少疲劳值
				fatigue_value -= FATIGUE_RECOVERY_IDLE_PER_SECOND * delta
			States.WALK:
				if animated_sprite.animation != "walk":
					animated_sprite.play("walk")
			States.DEATH:
				if animated_sprite.animation != "death":
					animated_sprite.play("death")
			States.DOWN:
				if animated_sprite.animation != "down":
					animated_sprite.play("down")
				# 倒地状态下显示持久性对话
				show_persistent_dialogue("别点我...")
				
				# 倒地状态下减少疲劳值
				fatigue_value -= FATIGUE_RECOVERY_DOWN / DOWN_DURATION_MAX * delta
				
				# 减少倒地计时器
				down_timer -= delta
				if down_timer <= 0:
					_change_movement_state_after_down()
		
	# 将疲劳值限制在 0 到 100 之间
	fatigue_value = clamp(fatigue_value, 0.0, MAX_FATIGUE)
	
	# 如果疲劳值达到100，触发游戏结束
	if fatigue_value >= MAX_FATIGUE:
		game_over()
		
	# 更新距离标签
	var distance_in_meters = int(round(total_walk_distance / PIXELS_PER_METER))
	distance_label.text = str(distance_in_meters, "m")
	
	# 更新疲劳值标签
	fatigue_label.text = "累: " + str(int(round(fatigue_value)))
	
	# 如果全局位置发生变化，更新鼠标穿透区域
	if global_position != last_global_position:
		setup_mouse_passthrough()
		last_global_position = global_position
		
# 处理输入事件的函数
func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				# 检查 area_2d 是否有效
				if is_instance_valid(area_2d) and area_2d.get_node("CollisionShape2D"):
					# 检查鼠标是否在碰撞形状内
					if area_2d.get_node("CollisionShape2D").shape.get_rect().has_point(area_2d.to_local(get_global_mouse_position())):
						# 只有当角色不是倒地或死亡状态时才允许拖拽
						if current_state != States.DOWN and current_state != States.DEATH and current_state != States.GAME_OVER:
							is_dragging = true
							drag_start_pos = get_global_mouse_position()
							drag_offset = position.x - get_global_mouse_position().x
						
			elif not event.is_pressed():
				is_dragging = false
				is_dragging_dialogue_shown = false # 拖拽结束后重置对话状态
				hide_dialogue()
				
				# 如果角色在倒地状态，松开左键将使其恢复
				if current_state == States.DOWN:
					_change_movement_state_after_down()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				# 检查 area_2d 是否有效
				if is_instance_valid(area_2d) and area_2d.get_node("CollisionShape2D"):
					# 检查鼠标是否在碰撞形状内
					if area_2d.get_node("CollisionShape2D").shape.get_rect().has_point(area_2d.to_local(get_global_mouse_position())):
						# 右键点击时显示特定的对话
						show_temporary_dialogue("你弄啥？")
				
# 显示一个带淡入淡出效果的临时对话
func show_temporary_dialogue(text):
	dialogue_label.text = text
	dialogue_label.show()
	
	var tween = get_tree().create_tween()
	tween.tween_property(dialogue_label, "modulate", Color(1, 1, 1, 1), 0.5) # 淡入
	tween.tween_interval(1.0) # 保持一段时间
	tween.tween_property(dialogue_label, "modulate", Color(1, 1, 1, 0), 0.5) # 淡出
	tween.tween_callback(dialogue_label.hide) # 淡出后隐藏

# 显示一个持久性的对话
func show_persistent_dialogue(text):
	dialogue_label.text = text
	dialogue_label.show()
	dialogue_label.modulate = Color(1, 1, 1, 1)

# 隐藏对话
func hide_dialogue():
	if is_instance_valid(dialogue_label):
		dialogue_label.hide()
		
# 设置对话气泡的样式（白色背景，黑色文字）
func set_dialogue_style():
	dialogue_label.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	dialogue_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.5))
	
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(1, 1, 1, 1)
	stylebox.set_corner_radius_all(5)
	stylebox.set_expand_margin_all(5)
	dialogue_label.add_theme_stylebox_override("normal", stylebox)

# 设置距离标签的样式（红色背景，白色文字）
func set_distance_style():
	distance_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(255.0 / 255.0, 135.0 / 255.0, 106.0 / 255.0, 1)
	stylebox.set_corner_radius_all(5)
	stylebox.set_expand_margin_all(5)
	distance_label.add_theme_stylebox_override("normal", stylebox)
	
# 设置疲劳值标签的样式
func set_fatigue_style():
	fatigue_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(135.0 / 255.0, 106.0 / 255.0, 255.0 / 255.0, 1) # 蓝色背景
	stylebox.set_corner_radius_all(5)
	stylebox.set_expand_margin_all(5)
	fatigue_label.add_theme_stylebox_override("normal", stylebox)

# 设置游戏结束标签的样式
func set_game_over_style():
	game_over_label.add_theme_color_override("font_color", Color(1, 1, 1)) # 白色文字
	game_over_label.add_theme_font_size_override("font_size", 48) # 字体大小
	game_over_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0)) # 添加黑色阴影
	
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0, 0, 0, 0) # 透明背景
	stylebox.set_corner_radius_all(10)
	stylebox.set_expand_margin_all(15)
	game_over_label.add_theme_stylebox_override("normal", stylebox)
	
# 设置鼠标穿透区域，现在只使用 Area2D 的形状
func setup_mouse_passthrough():
	# 检查 area_2d 节点是否有效
	if not is_instance_valid(area_2d):
		push_error("Error: area_2d node is not valid.")
		return
		
	var shape_node = area_2d.get_node("CollisionShape2D")
	if not is_instance_valid(shape_node):
		push_error("Error: CollisionShape2D node not found.")
		return
		
	# 修复: 检查形状是否被分配，以避免空引用错误。
	if not is_instance_valid(shape_node.shape):
		push_error("Error: CollisionShape2D node has no shape assigned.")
		return
	
	var shape = shape_node.shape
	var shape_transform = area_2d.get_global_transform()
	
	# 只支持矩形碰撞形状
	if shape is RectangleShape2D:
		var rect = shape.get_rect()
		var points = PackedVector2Array()
		# 获取矩形的四个顶点，并应用全局变换
		points.append(shape_transform * rect.position)
		points.append(shape_transform * (rect.position + Vector2(rect.size.x, 0)))
		points.append(shape_transform * (rect.position + Vector2(rect.size.x, rect.size.y)))
		points.append(shape_transform * (rect.position + Vector2(0, rect.size.y)))
		
		# 将这些点设置为鼠标穿透区域
		DisplayServer.window_set_mouse_passthrough(points)
	else:
		push_error("Mouse passthrough only works with RectangleShape2D.")

# 一个根据疲劳值获取正确对话列表的辅助函数
func _get_dialogues_by_fatigue():
	if fatigue_value > 50:
		return TIRED_DIALOGUES
	else:
		return NORMAL_DIALOGUES

# 改变移动状态（空闲或行走）
func _change_movement_state():
	match current_state:
		States.IDLE:
			# 从空闲状态切换到行走状态
			current_state = States.WALK
			# 随机选择一个方向（左或右）
			var rand_x = 1.0 if randi() % 2 == 0 else -1.0
			walk_direction = Vector2(rand_x, 0).normalized()
			# 设置随机的行走时间
			walk_timer = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
			# 新增: 当开始行走时，将连续行走周期计数器重置为1
			consecutive_walk_cycles = 1
			
			if randf() < 0.7:
				show_temporary_dialogue(_get_dialogues_by_fatigue()[randi() % _get_dialogues_by_fatigue().size()])
		States.WALK:
			var next_state_is_death = false
			
			# 检查是否满足强制倒地的条件（距离超过200米）
			if fatigue_value >= 40.0 and distance_since_last_down >= 200 * PIXELS_PER_METER:
				next_state_is_death = true
			# 否则，检查是否满足随机倒地的条件（随机几率触发）
			elif fatigue_value >= 40.0 and randf() < 0.2:
				next_state_is_death = true
			
			# 新增: 检查是否达到空闲保底次数
			# 修复：添加空值检查以防止崩溃
			if consecutive_walk_cycles == null:
				consecutive_walk_cycles = 0
			if consecutive_walk_cycles >= MAX_WALK_CYCLES:
				# 强制切换到空闲状态
				current_state = States.IDLE
				walk_direction = Vector2.ZERO
				walk_timer = randf_range(0.0, IDLE_DURATION_MAX)
				consecutive_walk_cycles = 0
				return # 结束函数，不再执行后面的逻辑
				
			if next_state_is_death:
				# 切换到死亡状态（倒地前）
				current_state = States.DEATH
				walk_direction = Vector2.ZERO
				consecutive_walk_cycles = 0 # 切换状态时重置计数器
			else:
				# 随机切换到空闲或继续行走
				var random_state = randi() % 2
				match random_state:
					0:
						# 切换到空闲状态
						current_state = States.IDLE
						walk_direction = Vector2.ZERO
						walk_timer = randf_range(0.0, IDLE_DURATION_MAX)
						consecutive_walk_cycles = 0 # 切换到空闲时重置计数器
					1:
						# 保持行走状态，但改变方向和计时器
						current_state = States.WALK
						var rand_x = 1.0 if randi() % 2 == 0 else -1.0
						walk_direction = Vector2(rand_x, 0).normalized()
						walk_timer = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)
						consecutive_walk_cycles += 1 # 保持行走时增加计数器
						
						# 根据疲劳值选择对话
						if randf() < 0.7:
							show_temporary_dialogue(_get_dialogues_by_fatigue()[randi() % _get_dialogues_by_fatigue().size()])

# 倒地状态结束后改变状态的函数
func _change_movement_state_after_down():
	hide_dialogue()
	# 倒地后重置倒地距离
	distance_since_last_down = 0.0
	consecutive_walk_cycles = 0 # 倒地后重置连续行走计数器
	
	var random_state = randi() % 2
	down_timer = 0.0
	
	match random_state:
		0:
			current_state = States.IDLE
			walk_direction = Vector2.ZERO
			walk_timer = randf_range(0.0, IDLE_DURATION_MAX)
		1:
			current_state = States.WALK
			var rand_x = 1.0 if randi() % 2 == 0 else -1.0
			walk_direction = Vector2(rand_x, 0).normalized()
			walk_timer = randf_range(WALK_DURATION_MIN, WALK_DURATION_MAX)

# 游戏结束函数
func game_over():
	# 停止所有活动
	is_dragging = false
	current_state = States.GAME_OVER
	walk_direction = Vector2.ZERO
	
	# 隐藏角色、标签和按钮
	animated_sprite.hide()
	area_2d.hide()
	dialogue_label.hide()
	distance_label.hide()
	fatigue_label.hide()
	
	# 显示游戏结束标签和重启按钮
	var distance_in_meters = int(round(total_walk_distance / PIXELS_PER_METER))
	game_over_label.text = "游戏结束\n总行走距离: " + str(distance_in_meters) + "m"
	game_over_label.show()
	
	# 移除了此处对游戏结束标签和重启按钮位置的设置代码。
	# 请在 Godot 编辑器中直接使用锚点和布局工具来定位这些UI元素。
	
	restart_button.show()
	
	# 清除鼠标穿透区域
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	
# 重启游戏
func restart_game():
	# 隐藏游戏结束标签和重启按钮
	game_over_label.hide()
	restart_button.hide()
	
	# 重置所有状态和值
	fatigue_value = 0.0
	total_walk_distance = 0.0
	distance_since_last_down = 0.0 # 新增：重启时重置倒地距离
	consecutive_walk_cycles = 0 # 重启时重置连续行走计数器
	current_state = States.IDLE
	walk_timer = randf_range(0.0, IDLE_DURATION_MAX)
	
	# 显示角色和标签
	animated_sprite.show()
	area_2d.show()
	distance_label.show()
	fatigue_label.show()
	
	# 重新设置鼠标穿透区域
	setup_mouse_passthrough()
