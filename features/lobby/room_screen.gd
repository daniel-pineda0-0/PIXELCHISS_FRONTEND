extends Control
## Sala de espera (US-003, 005, 012, 016, 017, 018).
##
## Pinta lo que dice Lobby.data y manda las acciones del jugador; el servidor
## decide si son válidas y esta pantalla muestra su mensaje cuando no lo son.

const STATUS_TIME := 4.0
const READY_COLOR := Color(0.6, 1.0, 0.6)

@onready var player_cards: Array = [%PlayerCard, %PlayerCard2, %PlayerCard3, %PlayerCard4]
@onready var map_cards: Array = [%MapCard, %MapCard2]

@onready var room_code_label:Label=%RoomCodeLabel
#@onready var copy_button = %CopyButton          # JoinButton (tiene set_text)
@onready var exit_button:TextureButton=%ExitButton
@onready var ready_button:TextureButton=%ReadyButton
@onready var start_button = %StartButton        # JoinButton (tiene set_text)
#@onready var leader_label: Label = %LeaderLabel
#@onready var preview_label: Label = %PreviewLabel
#@onready var status_label: Label = %StatusLabel

var _map_ids: Array[String] = []   # map_ids[i] es el mapa de map_cards[i]
var _selected_map := ""            # mapa en vista previa (US-012 esc. 5)
var _known_names := {}             # user_id -> nombre, para avisar quién entra o sale
var _was_host := false
var _status_timer := Timer.new()

func _ready() -> void:
	if not Lobby.in_lobby():
		_go_menu()
		return
	_status_timer.one_shot = true
	_status_timer.wait_time = STATUS_TIME
#	_status_timer.timeout.connect(func(): status_label.text = "")
	add_child(_status_timer)

	Lobby.changed.connect(_on_lobby_changed)
	Lobby.maps_loaded.connect(_build_maps)
	Lobby.left.connect(func(_reason: String): _go_menu())
	Lobby.started.connect(_on_started)
	for card in player_cards:
		card.add_bot_requested.connect(_on_add_bot_requested)
		card.remove_bot_requested.connect(_on_remove_bot_requested)
		card.kick_requested.connect(_on_kick_requested)
	for card in map_cards:
		card.selected.connect(_on_map_selected)
		card.vote_pressed.connect(_on_vote_pressed)
		card.visible = false
	#copy_button.set_text("Copy")
	start_button.set_text("Start")

	room_code_label.text = Lobby.data.code
	_was_host = Lobby.is_host()
	_remember_players()
	_refresh()
	if Lobby.maps.is_empty():
		if not await Lobby.fetch_maps():
			_show_status("No se pudieron cargar los mapas")
	else:
		_build_maps(Lobby.maps)
	if GameState.state == GameState.State.GAME and Lobby.in_lobby():
		status_label.text = "Partida iniciada: %s" % GameState.game_id

# --- Pintar la sala ---

func _refresh() -> void:
	if not Lobby.in_lobby():
		return
	var players: Array = Lobby.data.players
	var open: bool = Lobby.data.status == Lobby.STATUS_WAITING
	var can_manage := Lobby.is_host() and open
	for i in player_cards.size():
		if i < players.size():
			var is_me: bool = players[i].user_id == Lobby.my_id()
			player_cards[i].show_player(players[i], Lobby.seat_of(i, players.size()), can_manage, is_me)
		else:
			player_cards[i].show_empty(can_manage)
	_refresh_maps()
	_refresh_buttons()

func _refresh_buttons() -> void:
	if not Lobby.in_lobby():
		return
	var open: bool = Lobby.data.status == Lobby.STATUS_WAITING
	var is_ready: bool = Lobby.me().get("ready", false)
	# Comparten el mismo lugar: el anfitrión inicia, los demás se marcan listos.
	ready_button.visible = not Lobby.is_host()
	ready_button.disabled = not open
	ready_button.self_modulate = READY_COLOR if is_ready else Color.WHITE
	start_button.visible = Lobby.is_host()
	start_button.disabled = not open

## Reparte los mapas del servidor en las tarjetas que ya tiene la escena.
func _build_maps(maps: Array) -> void:
	_map_ids.clear()
	for i in map_cards.size():
		map_cards[i].visible = i < maps.size()
		if i < maps.size():
			map_cards[i].setup(maps[i])
			_map_ids.append(str(maps[i].id))
	if maps.size() > map_cards.size():
		push_warning("El servidor tiene %d mapas y la sala solo muestra %d" % [maps.size(), map_cards.size()])
	if _selected_map == "" and not _map_ids.is_empty():
		_selected_map = Lobby.my_vote() if Lobby.my_vote() != "" else _map_ids[0]
	_refresh_maps()

func _refresh_maps() -> void:
	if not Lobby.in_lobby():
		return
	var votes: Dictionary = Lobby.data.map_votes
	for i in _map_ids.size():
		var map_id := _map_ids[i]
		map_cards[i].set_votes(int(votes.get(map_id, 0)))
		map_cards[i].set_voted(map_id == Lobby.my_vote())
		map_cards[i].set_selected(map_id == _selected_map)
	var leader := Lobby.leading_map_id()
	leader_label.text = "Mapa: %s" % (_map_name(leader) if leader != "" else "al azar")
	preview_label.text = _preview_text(_selected_map)

func _map_name(map_id: String) -> String:
	for map in Lobby.maps:
		if map.id == map_id:
			return map.name
	return map_id

## Vista previa del mapa seleccionado: nombre, temática y descripción (US-012 esc. 5).
func _preview_text(map_id: String) -> String:
	for map in Lobby.maps:
		if map.id == map_id:
			return "%s - %s\n%s" % [map.name, map.theme, map.description]
	return ""

# --- Avisos de quién entra, sale o pasa a ser anfitrión ---

func _remember_players() -> void:
	_known_names.clear()
	for player in Lobby.data.players:
		_known_names[player.user_id] = player.display_name

func _announce_changes() -> void:
	var current := {}
	for player in Lobby.data.players:
		current[player.user_id] = player.display_name
	for id in current:
		if not _known_names.has(id):
			_show_status("%s se unio a la sala" % current[id])
	for id in _known_names:
		if not current.has(id):
			_show_status("%s salio de la sala" % _known_names[id])
	_known_names = current
	var host := Lobby.is_host()
	if host and not _was_host:
		_show_status("Ahora eres el anfitrion")
	_was_host = host

func _show_status(text: String) -> void:
	status_label.text = text
	_status_timer.start()

func _report(result: Dictionary) -> void:
	if not result.ok:
		_show_status(result.error)

# --- Señales de Lobby ---

func _on_lobby_changed(_lobby: Dictionary) -> void:
	_announce_changes()
	_refresh()

func _on_started(lobby: Dictionary) -> void:
	GameState.start_game(lobby)
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

func _go_menu() -> void:
	GameState.set_state(GameState.State.MENU)
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

# --- Acciones del jugador ---

func _on_exit_button_pressed() -> void:
	exit_button.disabled = true
	await Lobby.leave()
	_go_menu()

func _on_ready_button_pressed() -> void:
	var is_ready: bool = Lobby.me().get("ready", false)
	_report(await Lobby.set_ready(not is_ready))

func _on_start_button_pressed() -> void:
	start_button.disabled = true
	var result := await Lobby.start()
	if result.ok:
		return
	_show_status(result.error)
	_refresh_buttons()

func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(Lobby.data.code)
	_show_status("Codigo copiado")

func _on_map_selected(map_id: String) -> void:
	_selected_map = map_id
	_refresh_maps()

func _on_vote_pressed(map_id: String) -> void:
	_report(await Lobby.vote(map_id))

func _on_add_bot_requested() -> void:
	_report(await Lobby.add_bot())

func _on_remove_bot_requested(bot_id: String) -> void:
	_report(await Lobby.remove_bot(bot_id))

func _on_kick_requested(user_id: String) -> void:
	_report(await Lobby.kick(user_id))
