extends Node

enum State { BOOT, LOBBY, GAME }

const LOGIN_SCENE := "res://features/auth/loggin_screen.tscn"
const LOADING_SCENE := "res://features/loading/loading_screen.tscn"

const SCENES := {
	State.LOBBY: "res://features/lobby/RoomScreen.tscn",
	State.GAME: "res://features/lobby/RoomScreen.tscn",
}

signal state_changed(new_state: State)

var state: State = State.BOOT

func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

func resolve_next_scene() -> String:
	Session.logout()
	if state == State.BOOT:
		var logged: bool = Session.is_logged_in() or await Session.try_restore()
		if not logged:
			return LOGIN_SCENE    
		set_state(State.LOBBY)
	return SCENES[state]

func reset() -> void:
	set_state(State.BOOT)
