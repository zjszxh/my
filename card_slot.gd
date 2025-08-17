extends Area2D

# 当其他物体进入这个区域时，这个函数会被调用
func _on_body_entered(body):
	# 检查进入的物体是否是卡片
	if body.is_in_group("cards"):
		print("卡片进入卡槽了！")

# 当其他物体离开这个区域时，这个函数会被调用
func _on_body_exited(body):
	# 检查离开的物体是否是卡片
	if body.is_in_group("cards"):
		print("卡片离开卡槽了。")
