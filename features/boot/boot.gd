extends Control

func _ready() -> void:
	restore_session.call_deferred()

func restore_session()->void:
	if await Session.try_restore():
		get_tree().change_scene_to_file("res://scenes/RoomScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/loggin_screen.tscn")
