extends Node2D

# 使用 @onready 确保节点在脚本准备好后被正确引用。
# "../" 表示向上移动到父节点，然后寻找指定名称的子节点。
# 这样无论脚本挂载在哪个子节点上，只要路径正确，都能找到这些节点。
@onready var label: Label = $"../Label"
@onready var card_deck: Node2D = $"../CardDeck"
@onready var draw_button: Button = $"../DrawButton"
@onready var card_container: Node2D = $"../CardContainer"
@onready var deck_count_label: Label = $"../CardDeck/DeckCountLabel"


# 用于存储正在拖动的卡牌节点。
var card_being_dragged: Node2D = null
# 存储鼠标点击卡牌时的偏移量，用于拖拽时保持卡牌位置稳定。
var drag_offset = Vector2.ZERO
# 记录卡牌在开始拖拽时是否在卡槽中。
var was_in_slot_at_start = false
# 存储卡牌被拿起时的全局位置，用于飞回操作。
var original_position = Vector2.ZERO

# 使用 preload 预加载卡牌场景，可以提高加载速度。
var card_scene = preload("res://scn/card.tscn")
# 定义每次发牌的数量，使用 const (常量) 表示这个值不会改变。
const DEAL_COUNT = 5
# 跟踪场上已发出的卡牌数量，初始为0。
var cards_on_field = 0

# 定义牌堆的总卡牌数量。
const DECK_SIZE = 20
# 跟踪牌堆中剩余的卡牌数量。
var cards_in_deck = DECK_SIZE


# 一个空数组，用于存储每张卡牌的目标位置（相对于 CardContainer）。
var initial_card_local_positions = []

# _ready() 是 Godot 的内置函数，在节点及其子节点进入场景树后只执行一次。
func _ready() -> void:
	# --- 准备工作：计算卡牌的排列位置 ---
	var card_width = 100
	var card_spacing = 250
	
	var total_width = (DEAL_COUNT * card_width) + ((DEAL_COUNT - 1) * card_spacing)
	var start_x = -total_width / 2.0
	var start_y = 0.0
	
	for i in range(DEAL_COUNT):
		var target_position = Vector2(start_x + i * (card_width + card_spacing), start_y)
		initial_card_local_positions.append(target_position)
	
	# 在游戏开始时自动调用发牌函数。
	deal_cards()
	# 首次调用更新牌堆数量的函数。
	update_deck_count_label()

# 更新牌堆上显示剩余卡牌数量的函数。
func update_deck_count_label():
	deck_count_label.text = str(cards_in_deck)

# 处理发牌逻辑的函数。
func deal_cards() -> void:
	# 修复了快速弃牌后按钮无法点击的 bug。
	# 只有当牌堆不为空，并且场上没有卡牌时才开始发牌。
	if cards_in_deck <= 0:
		label.text = "牌堆已空！"
		draw_button.disabled = true
		return
		
	if cards_on_field > 0:
		label.text = "场上已有卡牌！"
		return
	
	draw_button.disabled = true
	label.text = "发牌中..."
	
	for i in range(DEAL_COUNT):
		if cards_in_deck <= 0:
			break
		
		var new_card = card_scene.instantiate()
		card_container.add_child(new_card)
		new_card.add_to_group("cards")
		new_card.global_position = card_deck.global_position
		
		var target_position_local = initial_card_local_positions[i]
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		tween.tween_property(new_card, "position", target_position_local, 0.5)
		
		cards_on_field += 1
		cards_in_deck -= 1
		update_deck_count_label()
		
		await tween.finished
	
	draw_button.disabled = false
	label.text = "发牌完成！"

# _input() 是 Godot 的内置函数，用于处理所有输入事件。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_card_drag_start()
		else:
			_handle_card_drop()

	elif event is InputEventMouseMotion and card_being_dragged:
		_handle_card_drag_motion()

# 处理卡牌拖拽开始的逻辑。
func _handle_card_drag_start():
	var card = raycast_check_card()
	if card:
		card_being_dragged = card
		drag_offset = get_global_mouse_position() - card.global_position
		was_in_slot_at_start = card_being_dragged.is_in_group("card_slots")
		original_position = card.global_position

# 处理卡牌拖拽过程中的逻辑。
func _handle_card_drag_motion():
	# 确保有卡牌正在被拖拽。
	if not card_being_dragged:
		return
		
	var viewport_size = get_viewport().size
	var card_sprite = card_being_dragged.get_node("CardSprite")
	if not is_instance_valid(card_sprite) or not card_sprite.get_texture():
		return
	var card_size = card_sprite.get_texture().get_size()
	
	var new_position = get_global_mouse_position() - drag_offset
	
	var half_card_size = card_size / 2.0
	
	var clamped_x = clamp(new_position.x, half_card_size.x, viewport_size.x - half_card_size.x)
	var clamped_y = clamp(new_position.y, half_card_size.y, viewport_size.y - half_card_size.y)
	
	card_being_dragged.global_position = Vector2(clamped_x, clamped_y)

# 处理卡牌被丢弃的逻辑，是 _input 函数的核心优化部分。
func _handle_card_drop():
	if not card_being_dragged:
		return
		
	var current_card = card_being_dragged
	card_being_dragged = null
	
	var overlapping_areas = current_card.get_overlapping_areas()
	var dropped_in_slot = false
	var discarded = false
	var card_rect = current_card.get_global_transform() * current_card.get_node("CardSprite").get_rect()
	
	for area in overlapping_areas:
		# 检查是否落在卡槽。
		if area.is_in_group("card_slots"):
			var slot_rect = _get_collision_rect(area)
			if slot_rect:
				var card_center = card_rect.position + card_rect.size / 2.0
				var slot_center = slot_rect.position + slot_rect.size / 2.0
				var move_vector = slot_center - card_center
				current_card.global_position += move_vector
				current_card.z_index = area.z_index + 1
				dropped_in_slot = true
				
				if not was_in_slot_at_start:
					label.text = "你放置了一张卡牌"
					current_card.add_to_group("card_slots")
					cards_on_field -= 1
				break
		
		# 检查是否落在弃牌区。
		elif area.is_in_group("giveup"):
			var giveup_rect = _get_collision_rect(area)
			# 🌟 新的逻辑: 检查弃牌区是否完全包含了卡牌的矩形。
			if giveup_rect.encloses(card_rect):
				discarded = true
				_play_dissolve_animation(current_card)
				break
	
	# 如果没有落在任何有效区域，则飞回原位。
	if not dropped_in_slot and not discarded:
		label.text = "卡牌被移出，飞回原位！"
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		tween.tween_property(current_card, "global_position", original_position, 0.3)

# 播放卡牌溶解动画的私有函数。
func _play_dissolve_animation(card_to_dissolve: Node2D):
	card_to_dissolve.z_index = 100
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	tween.tween_property(card_to_dissolve, "scale", Vector2.ZERO, 0.5)
	tween.tween_property(card_to_dissolve, "modulate", Color(1, 1, 1, 0), 0.5)
	
	await tween.finished
	
	card_to_dissolve.queue_free()
	
	label.text = "你弃掉了一张卡牌"
	cards_on_field -= 1

# 辅助函数：安全地获取碰撞体的全局矩形。
func _get_collision_rect(area: Area2D) -> Rect2:
	var shape_node = area.find_child("CollisionShape2D")
	if shape_node and shape_node.shape:
		return shape_node.get_global_transform() * shape_node.shape.get_rect()
	return Rect2()

# 射线检测函数，用于判断鼠标下方是否有卡牌。
func raycast_check_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = 1
	
	var results = space_state.intersect_point(parameters)
	
	if results.is_empty():
		return null
	
	var top_card = null
	var top_z_index = -INF
	
	for result in results:
		var current_card = result.collider
		if current_card.is_in_group("cards"):
			if current_card.z_index > top_z_index:
				top_z_index = current_card.z_index
				top_card = current_card
			elif current_card.z_index == top_z_index:
				if top_card == null or current_card.get_index() > top_card.get_index():
					top_card = current_card
					
	return top_card
