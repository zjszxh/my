
extends Node2D
@onready var label: Label = $"../Label"
@onready var card_deck: Node2D = $"../CardDeck"
@onready var draw_button: Button = $"../DrawButton"
@onready var card_container: Node2D = $"../CardContainer"



var card_being_dragged
var drag_offset = Vector2.ZERO
var was_in_slot_at_start = false

var card_scene = preload("res://scn/card.tscn")
const DEAL_COUNT = 5
var cards_on_field = 0

var initial_card_local_positions = []

func _ready() -> void:
	# 将按钮的 "pressed" 信号连接到发牌函数
	#draw_button.pressed.connect(deal_cards)
	
	# 新增：直接计算卡牌相对于 CardContainer 的局部位置
	var card_width = 100
	var card_spacing = 250
	
	var total_width = (DEAL_COUNT * card_width) + ((DEAL_COUNT - 1) * card_spacing)
	var start_x = -total_width / 2.0
	var start_y = 0.0
	
	for i in range(DEAL_COUNT):
		var target_position = Vector2(start_x + i * (card_width + card_spacing), start_y)
		initial_card_local_positions.append(target_position)
	
	# 🌟 新增：在游戏开始时自动调用发牌函数
	deal_cards()

func deal_cards() -> void:
	if cards_on_field > 0:
		return
	
	draw_button.disabled = true
	label.text = "发牌中..."
	
	for i in range(DEAL_COUNT):
		var new_card = card_scene.instantiate()
		card_container.add_child(new_card)
		
		# 新增：将新卡牌添加到 "cards" 组
		new_card.add_to_group("cards")
		
		# 将卡牌的初始位置设置为牌堆的全局位置
		new_card.global_position = card_deck.global_position
		
		var target_position_local = initial_card_local_positions[i]
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
		tween.tween_property(new_card, "position", target_position_local, 0.5)
		
		cards_on_field += 1
		
		await tween.finished
	
	draw_button.disabled = false
	label.text = "发牌完成！"

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var card = raycast_check_card()
			if card:
				card_being_dragged = card
				drag_offset = get_global_mouse_position() - card.global_position
				was_in_slot_at_start = card_being_dragged.is_in_group("card_slots")
			else:
				card_being_dragged = null

		else:
			if card_being_dragged:
				var overlapping_areas = card_being_dragged.get_overlapping_areas()
				var dropped_in_slot = false
				var discarded = false

				for area in overlapping_areas:
					if area.is_in_group("card_slots"):
						var card_collision_shape = card_being_dragged.find_child("CollisionShape2D")
						var slot_collision_shape = area.find_child("CollisionShape2D")

						if card_collision_shape and slot_collision_shape:
							var card_rect = card_collision_shape.get_global_transform() * card_collision_shape.shape.get_rect()
							var slot_rect = slot_collision_shape.get_global_transform() * slot_collision_shape.shape.get_rect()

							var card_center = card_rect.position + card_rect.size / 2.0
							var slot_center = slot_rect.position + slot_rect.size / 2.0

							var move_vector = slot_center - card_center
							card_being_dragged.global_position += move_vector
							card_being_dragged.z_index = area.z_index + 1

							dropped_in_slot = true

							if not was_in_slot_at_start:
								label.text = "你放置了一张卡牌"
								card_being_dragged.add_to_group("card_slots")
								cards_on_field -= 1

							break

					if area.is_in_group("giveup"):
						card_being_dragged.queue_free()
						discarded = true
						label.text = "你弃掉了一张卡牌"
						cards_on_field -= 1
						break

				if not dropped_in_slot and not discarded and was_in_slot_at_start:
					label.text = "你移出了一张卡牌"
					card_being_dragged.remove_from_group("card_slots")

			card_being_dragged = null


	if event is InputEventMouseMotion:
		if card_being_dragged:
			card_being_dragged.global_position = get_global_mouse_position() - drag_offset
			
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
	#提交github
