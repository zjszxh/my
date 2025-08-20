# DesktopPet.gd
# 这是一个桌面宠物核心脚本，负责角色的移动、状态管理、动画、拖拽和窗口穿透。
extends CharacterBody2D

# -----------------------------------------------------------
# 状态机常量
# -----------------------------------------------------------
enum {
	STATE_IDLE,      # 角色空闲，停留
	STATE_WALK,      # 角色行走
}

# -----------------------------------------------------------
# 导出变量 (在 Godot 编辑器中可调节)
# -----------------------------------------------------------
@export var walk_speed = 100.0  # 角色移动速度
@export var ground_y_offset = 80.0 # 角色距离窗口底部的垂直偏移量
@export var idle_time_min = 2.0   # 最小停留时间（秒）
@export var idle_time_max = 5.0   # 最大停留时间（秒）
@export var walk_time_min = 3.0   # 最小行走时间（秒）
@export var walk_time_max = 8.0   # 最大行走时间（秒）

# -----------------------------------------------------------
# 内部变量
# -----------------------------------------------------------
var current_state = STATE_WALK
var state_timer = 0.0
var walk_direction = 1              # 1: right, -1: left
var window_size = Vector2.ZERO      # 存储窗口的尺寸
var passthrough_polygon = PackedVector2Array() # 存储可穿透区域多边形

# 拖拽相关变量
var is_dragging = false
var initial_mouse_pos = Vector2.ZERO
var initial_pet_pos = Vector2.ZERO

# -----------------------------------------------------------
# Godot 内置函数
# -----------------------------------------------------------

func _ready():
	# 初始化窗口设置，包括位置和穿透
	initialize_window_and_character()
	
	# 初始化角色状态
	walk_direction = randi_range(0, 1) * 2 - 1
	set_state(STATE_WALK)
	
	# 连接 Area2D 的信号
	$Area2D.input_event.connect(_on_Area2D_input_event)
	$Area2D.mouse_entered.connect(_on_Area2D_mouse_entered)
	$Area2D.mouse_exited.connect(_on_Area2D_mouse_exited)

func _physics_process(delta):
	# 统一进行物理移动和边界检测
	if is_dragging:
		handle_dragging()
	else:
		handle_movement(delta)
		
		velocity.y = 0
		move_and_slide()
	
	# **核心修改**: 检查并处理边界碰撞
	if global_position.x <= 0 or global_position.x >= window_size.x:
		# 强制将角色位置限制在边界内，以防穿出
		global_position.x = clamp(global_position.x, 0, window_size.x)
		
		# 改变方向并切换到空闲状态
		walk_direction = -walk_direction
		set_state(STATE_IDLE)
	
	# 动画处理
	update_animation()

# -----------------------------------------------------------
# 私有函数：封装逻辑
# -----------------------------------------------------------

func initialize_window_and_character():
	var target_screen_index = 0 
	var screen_size_vector = DisplayServer.screen_get_size(target_screen_index)
	var screen_position_vector = DisplayServer.screen_get_position(target_screen_index)
	
	window_size = DisplayServer.window_get_size()
	
	var new_position_x = screen_position_vector.x + 0
	var new_position_y = screen_position_vector.y + screen_size_vector.y - window_size.y
	
	DisplayServer.window_set_position(Vector2(new_position_x, new_position_y))
	#global_position.y = window_size.y - ground_y_offset
	
	passthrough_polygon.push_back(Vector2(0, 0))
	passthrough_polygon.push_back(Vector2(window_size.x, 0))
	passthrough_polygon.push_back(Vector2(window_size.x, window_size.y))
	passthrough_polygon.push_back(Vector2(0, window_size.y))
	
	DisplayServer.window_set_mouse_passthrough(passthrough_polygon)

func set_state(new_state):
	current_state = new_state
	match current_state:
		STATE_IDLE:
			state_timer = randf_range(idle_time_min, idle_time_max)
			velocity.x = 0
		STATE_WALK:
			state_timer = randf_range(walk_time_min, walk_time_max)
			velocity.x = walk_direction * walk_speed

func handle_movement(delta):
	match current_state:
		STATE_IDLE:
			state_timer -= delta
			if state_timer <= 0:
				set_state(STATE_WALK)
		STATE_WALK:
			state_timer -= delta
			if state_timer <= 0:
				set_state(STATE_IDLE)

func update_animation():
	if is_dragging or current_state == STATE_IDLE:
		$AnimatedSprite2D.play("idle")
	elif current_state == STATE_WALK:
		$AnimatedSprite2D.flip_h = walk_direction < 0
		$AnimatedSprite2D.play("run")
	
func handle_dragging():
	var new_x = initial_pet_pos.x + get_viewport().get_mouse_position().x - initial_mouse_pos.x
	global_position = Vector2(new_x, global_position.y)
	velocity = Vector2.ZERO

# -----------------------------------------------------------
# 信号处理函数
# -----------------------------------------------------------

func _on_Area2D_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			is_dragging = true
			initial_mouse_pos = get_viewport().get_mouse_position()
			initial_pet_pos = global_position
			update_animation()
		else:
			if is_dragging:
				is_dragging = false
				DisplayServer.window_set_mouse_passthrough(passthrough_polygon)
				set_state(STATE_IDLE)
				state_timer = 0.5 

func _on_Area2D_mouse_entered():
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	
func _on_Area2D_mouse_exited():
	if not is_dragging:
		DisplayServer.window_set_mouse_passthrough(passthrough_polygon)
