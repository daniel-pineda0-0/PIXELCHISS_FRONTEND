class_name Boot extends Node

func restore_session()->String:
	if await Session.try_restore():
		return ""
	return "res://features/auth/LogginScreen.tscn"
