extends Node

enum State { BOOT, MENU, LOBBY, GAME }

const LOGIN_SCENE := "res://features/auth/loggin_screen.tscn"
const LOADING_SCENE := "res://features/loading/loading_screen.tscn"

const SCENES := {
	State.MENU: "res://features/lobby/menu_screen.tscn",
	State.LOBBY: "res://features/lobby/room_screen.tscn",
	State.GAME: "res://features/lobby/room_screen.tscn",
}

signal state_changed(new_state: State)

var state: State = State.BOOT
var game_id := ""
var map_id := ""

func _ready() -> void:
	Lobby.session_expired.connect(expire_session)

func set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

func resolve_next_scene() -> String:
	if state == State.BOOT:
		var logged: bool = Session.is_logged_in() or await Session.try_restore()
		if not logged:
			return LOGIN_SCENE    
		set_state(State.MENU)
	return SCENES[state]

## El servidor inició la partida (US-018): se guarda a cuál y con qué mapa.
## El cambio de escena lo hace quien llama, pasando por la pantalla de carga.
func start_game(lobby: Dictionary) -> void:
	game_id = lobby.get("game_id", "")
	map_id = lobby.get("map_id", "")
	set_state(State.GAME)

## Sesión vencida (US-002 esc. 3): se limpian los tokens y se vuelve al login.
func expire_session() -> void:
	Lobby.clear()
	Session.clear()
	reset()
	get_tree().change_scene_to_file(LOADING_SCENE)

func reset() -> void:
	game_id = ""
	map_id = ""
	set_state(State.BOOT)
