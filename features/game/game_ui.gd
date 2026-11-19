extends CanvasLayer
## HUD de la partida.
## US-020: minimapa con las fichas de todos los jugadores y botones para recorrer
## los chunks del tablero (game.gd los conecta a BoardView).
## Fase 3: contador de fichas coronadas por jugador (US-015) y pantalla de
## victoria para todos al terminar la partida (US-014).
## Fase 4: avisos de las cartas (US-007 a US-009). La trivia vive en TriviaUI, el
## panel de carta en CardPanel y los objetivos en BoardView; aquí se montan y se
## atienden los avisos de efectos, capturas y salidas hechas por carta (US-010,
## US-011, US-013, US-015) y las etiquetas de efectos en las tarjetas de jugador.
## Fase 2: turnos (US-006), dados, temporizador, botón de pasar y avisos de
## liberar (US-011), zona segura (US-013) y captura (US-010). Todo sale del estado y
## los eventos del servidor: aquí no se decide ninguna regla, solo se bloquean las
## acciones obvias fuera de turno y se muestra lo que responde el servidor.

signal view_step(direction: int)    # -1 izquierda, 1 derecha, 0 soltó el botón (la cámara se mueve mientras se mantiene)

const SHARED_CELL_SPACING := 2.0
const MINIMAP_PIECE := preload("res://features/game/game_pice.tscn")
const HOVER_RADIUS := 6.0          # px del minimapa: qué tan cerca de una casilla hay que pasar para ver su letrero
const LABEL_WHITE := preload("res://service/assets/ui/prefabs/PixelFontWhite.tres")
const END_TURN_BUTTON := preload("res://features/lobby/join_button.tscn")
const SEAT_NAMES := ["Rojo", "Azul", "Verde", "Amarillo"]
const RESULT_DELAY := 1.2           # deja ver el último movimiento antes de la pantalla final
const TOAST_TIME := 1.8
const TOAST_MAX_QUEUE := 3
const LOW_TIME := 10                # segundos: el cronómetro se pone rojo
const URGENT_COLOR := Color(1.0, 0.45, 0.4)

## Texto para el jugador de los rechazos del servidor (guía §10). Los que no están
## aquí se muestran con el mensaje que mande el servidor.
const ERROR_TEXT := {
	"NOT_YOUR_TURN": "No es tu turno",
	"TURN_EXPIRED": "Se acabó el tiempo del turno",
	"ALREADY_ROLLED": "Ya lanzaste los dados",
	"ROLL_REQUIRED": "Primero lanza los dados",
	"DOUBLES_REQUIRED": "Necesitas pares para sacar una ficha",
	"CELL_FULL": "Esa casilla está llena",
	"OVERSHOOT": "Necesitas el número exacto para coronar",
	"CROWNED_PIECE": "Esa ficha ya está coronada",
	"DIE_UNAVAILABLE": "Ese dado ya se usó",
	"PENDING_CHALLENGE": "Hay un desafío pendiente",
	"GAME_FINISHED": "La partida terminó",
	"INVALID_CHALLENGE": "Ese desafío ya no está activo",
	"CHALLENGE_EXPIRED": "Se acabó el tiempo",
	"INVALID_ANSWER": "Respuesta no válida",
	"INVALID_CARD_TARGET": "Ese objetivo no es válido",
}

var _minimap_panel: Control
var _hover: PanelContainer         # letrero al pasar el ratón por una casilla del minimapa
var _hover_label: Label
var _hover_text := ""
var _layer: Node2D                  # TileMapLayer del minimapa: las fichas van dentro, así comparten su transformación
var _pieces_root: Node2D
var _pieces := {}                   # id de ficha -> MinimapPiece

var _hud: Control
var _dices_panel: Control           # panel grande de abajo: dados del turno + botón de lanzar
var _dices: Variant                 # dices.gd (show_values / play_roll / clear)
var _roll_button: Button
var _card_nodes: Array[PlayerCardGame] = []  # tarjetas del HUD, en el orden de la escena
var _cards := {}                    # asiento -> PlayerCardGame
var _cards_ready := false
var _turn_label: Label
var _end_button: TextureButton
var _toast_label: Label
var _flash: ColorRect
var _toast_queue: Array[String] = []
var _toast_left := 0.0
var _tick := 0.0
var _prev_turn_player := ""
var _exit_warned_version := -1
var _result_scheduled := false
var _result_panel: Control
var _last_dice := {}                # asiento -> últimos dados que sacó (se conservan entre turnos)
var _pending_events: Array = []     # eventos en espera mientras ruedan los dados
var _was_holding := false

func _ready() -> void:
	var minimap := find_child("MiniMap", true, false)
	if minimap != null:
		_layer = minimap.find_child("TileMapLayer", true, false) as Node2D
	_minimap_panel = minimap as Control
	var test_piece := find_child("GamePice", true, false)
	if test_piece != null:
		test_piece.queue_free()     # ficha de prueba de la escena
	if _layer != null:
		_pieces_root = Node2D.new()
		_pieces_root.name = "MiniPieces"
		_pieces_root.z_index = 10            # por encima de las casillas del minimapa
		_layer.add_child(_pieces_root)
	else:
		push_warning("GameUI: no se encontró el TileMapLayer del minimapa")

	var left := find_child("ButtonL", true, false) as Button
	var right := find_child("ButtonR", true, false) as Button
	if left != null:
		left.button_down.connect(func(): view_step.emit(-1))
		left.button_up.connect(func(): view_step.emit(0))
	if right != null:
		right.button_down.connect(func(): view_step.emit(1))
		right.button_up.connect(func(): view_step.emit(0))

	_setup_turn_hud()
	add_child(CardPanel.new())       # aviso y objetivo de las cartas (Fase 4)

	GameNet.state_changed.connect(_on_state_changed)
	GameNet.busy_changed.connect(func(_busy: bool): _refresh_turn(GameNet.state))
	GameNet.legal_moves_changed.connect(_on_legal_moves)
	GameNet.events_received.connect(_on_events)
	GameNet.action_rejected.connect(_on_action_rejected)
	if not GameNet.state.is_empty():
		_on_state_changed(GameNet.state)

func _exit_tree() -> void:
	RollHold.clear()

## Mientras ruedan los dados no se redibuja nada: al terminar, _process aplica el
## último estado (ver RollHold).
func _on_state_changed(state: Dictionary) -> void:
	if RollHold.active():
		return
	_refresh_minimap(state)
	_refresh_turn(state)

# --- Montaje del HUD de turnos -------------------------------------------------------

func _setup_turn_hud() -> void:
	_hud = get_node_or_null("GameHUD") as Control
	if _hud == null:
		push_warning("GameUI: no se encontró GameHUD")
		return
	# El HUD ocupa toda la pantalla: si no deja pasar el ratón, el tablero no recibe clics.
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := _hud.get_node_or_null("MarginContainer") as Control
	if margin != null:
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dices_panel = _hud.get_node_or_null("MarginContainer/Dices") as Control
	if _dices_panel != null:
		_dices = _dices_panel.get_node_or_null("AspectRatioContainer/dices")
		_roll_button = _dices_panel.get_node_or_null("PlayerButton") as Button
		if _roll_button != null:
			_roll_button.pressed.connect(_on_roll_pressed)
			_roll_button.focus_mode = Control.FOCUS_NONE

	var box := _hud.get_node_or_null("MarginContainer/Players/HBoxContainer")
	if box != null:
		for child in box.get_children():
			if child is PlayerCardGame:
				child.visible = false          # se muestran según cuántos jugadores haya
				_card_nodes.append(child)

	_build_turn_banner()
	_build_end_turn_button()
	_build_toast()
	_build_hover()

func _build_turn_banner() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 16.0
	panel.offset_bottom = 16.0
	_turn_label = Label.new()
	_turn_label.label_settings = LABEL_WHITE.duplicate() as LabelSettings
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.custom_minimum_size = Vector2(200, 0)
	_turn_label.text = "Conectando..."
	panel.add_child(_turn_label)

func _build_end_turn_button() -> void:
	_end_button = END_TURN_BUTTON.instantiate() as TextureButton
	_hud.add_child(_end_button)
	_end_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_end_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_end_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_end_button.set_text("Pasar")
	_end_button.tooltip_text = "Termina tu turno (pierdes el turno extra por pares)"
	_end_button.focus_mode = Control.FOCUS_NONE
	_end_button.visible = false
	_end_button.pressed.connect(_on_end_turn_pressed)

func _build_toast() -> void:
	_toast_label = Label.new()
	var settings := LABEL_WHITE.duplicate() as LabelSettings
	settings.outline_size = 4
	settings.outline_color = Color.BLACK
	_toast_label.label_settings = settings
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.visible = false
	_hud.add_child(_toast_label)
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_label.offset_top = -72.0
	_toast_label.offset_bottom = -72.0

	_flash = ColorRect.new()
	_flash.color = Color(1, 0.1, 0.1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# --- Tarjetas de jugador ---------------------------------------------------------------

## Reparte las tarjetas por asiento la primera vez que llega la lista de jugadores.
func _ensure_cards(state: Dictionary) -> void:
	if _cards_ready:
		return
	var players: Array = state.get("players", [])
	if players.is_empty():
		return
	players = players.duplicate()
	players.sort_custom(func(a, b): return int(a.get("seat", 0)) < int(b.get("seat", 0)))
	for i in _card_nodes.size():
		var card := _card_nodes[i]
		if i >= players.size():
			card.hide_card()
			continue
		var seat := int(players[i].get("seat", i))
		var pid := str(players[i].get("id", ""))
		var label := _player_name(pid)
		if pid == GameNet.me:
			label += " (tú)"
		card.setup(seat, label)
		_cards[seat] = card
	_cards_ready = true

# --- Estado del turno -----------------------------------------------------------------------

func _turn() -> Dictionary:
	var turn: Variant = GameNet.state.get("turn")
	return turn if turn is Dictionary else {}

func _is_playing() -> bool:
	return GameNet.state.get("status") == "ACTIVE"

func _has_challenge() -> bool:
	return GameNet.state.get("trivia") != null or GameNet.state.get("card") != null

func _can_roll() -> bool:
	return _is_playing() and GameNet.is_my_turn() and not bool(_turn().get("rolled", false)) \
			and not _has_challenge() and not GameNet.busy and not RollHold.active()

func _can_end_turn() -> bool:
	return _is_playing() and GameNet.is_my_turn() and bool(_turn().get("rolled", false)) \
			and not _has_challenge() and not GameNet.busy and not RollHold.active()

func _refresh_turn(state: Dictionary) -> void:
	if _hud == null or state.is_empty() or RollHold.active():
		return
	_ensure_cards(state)
	var turn := _turn()
	var playing := _is_playing()
	var active_id := str(turn.get("playerId", "")) if playing else ""
	var active_seat := int(GameNet.player(active_id).get("seat", -1)) if active_id != "" else -1
	var dice: Array = turn.get("dice", []) if turn.get("dice") is Array else []
	var consumed: Array = turn.get("consumed", []) if turn.get("consumed") is Array else []
	if active_seat >= 0 and dice.size() == 2:
		_last_dice[active_seat] = dice            # también cubre entrar a media partida
	var crowned := _crowned_by_seat(state)
	var effects := _effects_by_seat(state)

	for seat in _cards:
		var card: PlayerCardGame = _cards[seat]
		var is_active: bool = seat == active_seat
		card.set_active(is_active)
		# Cada tarjeta conserva la última tirada de su jugador; solo el del turno marca los dados gastados.
		card.show_dice(_last_dice.get(seat, []), consumed if is_active else [])
		card.set_crowned(int(crowned.get(seat, 0)))
		card.set_effects(effects.get(seat, []))

	if _dices != null:
		var my_seat := int(GameNet.player(GameNet.me).get("seat", -1))
		_dices.show_values(_last_dice.get(my_seat, []), consumed if active_id == GameNet.me else [])
	if _end_button != null:
		_end_button.visible = _can_end_turn()
	_update_turn_label()
	if state.get("status") != "ACTIVE":
		_schedule_result()

## Fichas coronadas por asiento, contadas del snapshot.
func _crowned_by_seat(state: Dictionary) -> Dictionary:
	var counts := {}
	for p in state.get("pieces", []):
		if str(p.get("status", "")) == "CROWNED":
			var seat := BoardMap.seat_of_piece(p)
			counts[seat] = int(counts.get(seat, 0)) + 1
	return counts

## Efectos activos por asiento (`players[].effects`).
func _effects_by_seat(state: Dictionary) -> Dictionary:
	var by_seat := {}
	for p in state.get("players", []):
		var list: Variant = p.get("effects")
		if list is Array and not list.is_empty():
			by_seat[int(p.get("seat", -1))] = list
	return by_seat

func _update_turn_label() -> void:
	if _turn_label == null:
		return
	if GameNet.state.is_empty():
		_turn_label.text = "Conectando..."
		return
	if not _is_playing():
		_turn_label.text = "Partida terminada"
		return
	var turn := _turn()
	var active_id := str(turn.get("playerId", ""))
	var text := ""
	if active_id == GameNet.me:
		if GameNet.state.get("trivia") != null:
			text = "Responde la trivia"
		elif GameNet.state.get("card") != null:
			text = "Elige un objetivo"
		elif not bool(turn.get("rolled", false)):
			text = "Tu turno: lanza"
		elif GameNet.legal_moves.is_empty():
			text = "Tu turno"
		else:
			text = "Mueve una ficha"
	elif GameNet.state.get("trivia") != null:
		text = "%s responde trivia" % _short_name(_player_name(active_id))
	elif GameNet.state.get("card") != null:
		text = "%s elige objetivo" % _short_name(_player_name(active_id))
	else:
		text = "Turno de " + _short_name(_player_name(active_id))
	var seconds := _seconds_left()
	if seconds >= 0:
		text += "  %ds" % seconds
	_turn_label.text = text
	var label_settings := _turn_label.label_settings
	if label_settings != null:
		label_settings.font_color = URGENT_COLOR if seconds >= 0 and seconds <= LOW_TIME else Color.WHITE

## Segundos que quedan del turno según `turn.deadline` (Unix ms del servidor). Solo
## se muestra: el servidor decide cuándo vence y pasa el turno por su cuenta.
func _seconds_left() -> int:
	var deadline := float(_turn().get("deadline", 0))
	if deadline <= 0.0:
		return -1
	return maxi(0, ceili((deadline - Time.get_unix_time_from_system() * 1000.0) / 1000.0))

func _process(delta: float) -> void:
	var holding := RollHold.active()
	if _was_holding and not holding:
		_on_state_changed(GameNet.state)          # lo que quedó en espera
		_on_legal_moves(GameNet.legal_moves)
	_was_holding = holding
	if not holding:
		_drain_events()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.2
		_update_turn_label()
	if _dices_panel != null:
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		_dices_panel.modulate = Color(1.0, 1.0, pulse) if _can_roll() else Color.WHITE
	_tick_toast(delta)
	_update_hover()

# --- Acciones del jugador ---------------------------------------------------------------------

func _on_roll_pressed() -> void:
	if not _is_playing():
		return
	if not GameNet.is_my_turn():                        # US-006 esc. 3: se bloquea fuera de turno
		_toast("No es tu turno", true)
		return
	var turn := _turn()
	if bool(turn.get("rolled", false)):
		_toast("Ya lanzaste los dados", true)
		return
	if _has_challenge():
		_toast("Hay un desafío pendiente", true)
		return
	if bool(turn.get("diceSelectionRequired", false)):
		# Ninguna carta del catálogo actual lo activa (guía §7.5); se resuelve sin pedir nada.
		var top := int(turn.get("maxDieValue", 6))
		GameNet.roll([top, top])
	else:
		GameNet.roll()

func _on_end_turn_pressed() -> void:
	if _can_end_turn():
		GameNet.end_turn()

# --- Avisos ------------------------------------------------------------------------------------------

func _on_action_rejected(code: String, message: String) -> void:
	if code in GameNet.NO_SYNC_ERRORS:
		return
	_toast(str(ERROR_TEXT.get(code, message if message != "" else code)), true)

## US-011 esc. 4: con pares y fichas en casa, si el servidor no ofrece ninguna
## liberación pero sí otros movimientos, es porque la salida está llena.
func _on_legal_moves(moves: Array) -> void:
	_update_turn_label()
	if RollHold.active() or moves.is_empty() or not GameNet.is_my_turn():
		return
	var turn := _turn()
	if not bool(turn.get("doubles", false)):
		return
	var has_free_die := false
	for used in turn.get("consumed", []):
		if not bool(used):
			has_free_die = true
	if not has_free_die:
		return
	var has_home_piece := false
	for piece in GameNet.state.get("pieces", []):
		if str(piece.get("ownerId", "")) == GameNet.me and BoardMap.is_home(piece):
			has_home_piece = true
	if not has_home_piece:
		return
	for m in moves:
		if bool(m.get("release", false)):
			return
	var version := int(GameNet.state.get("version", 0))
	if version == _exit_warned_version:
		return
	_exit_warned_version = version
	_toast("Tu salida está llena: no puedes sacar fichas")

## Los eventos se atienden en orden. Si ruedan unos dados, los siguientes esperan:
## así lo que hace un bot justo después de tirar no pisa la animación.
func _on_events(events: Array, _version: int) -> void:
	_pending_events.append_array(events)
	_drain_events()

func _drain_events() -> void:
	while not _pending_events.is_empty() and not RollHold.active():
		_handle_event(_pending_events.pop_front())

func _handle_event(e: Variant) -> void:
	var data: Dictionary = e.data if e.get("data") is Dictionary else {}
	match str(e.get("type", "")):
		"TURN_CHANGED":
			var pid := str(data.get("playerId", ""))
			if pid == GameNet.me:
				_toast("¡Turno extra!" if pid == _prev_turn_player else "¡Es tu turno!")
			elif pid != "" and pid == _prev_turn_player:
				_toast("Turno extra de " + _short_name(_player_name(pid)))   # US-006 esc. 5
			_prev_turn_player = pid
		"TURN_EXPIRED":
			var who := str(data.get("playerId", ""))
			if who == GameNet.me:
				_toast("Se acabó tu tiempo", true)
			else:
				_toast("Se acabó el tiempo de " + _short_name(_player_name(who)))
		"DICE_ROLLED":
			_on_dice_rolled(data)
		"PIECE_MOVED":
			_on_piece_moved(data)
		"PIECE_CAPTURED":
			_on_piece_captured(data)
		"CARD_PIECE_RETURNED":
			_on_card_piece_returned(data)
		"CARD_DISCARDED":
			if data.get("cardId") == null:      # con cardId lo muestra CardPanel
				_toast(GameText.discard_text(str(data.get("reason", ""))))
		"EFFECT_CONSUMED":
			_on_effect_consumed(data)
		"EFFECT_EXPIRED":
			if str(data.get("playerId", "")) == GameNet.me:
				_toast("Terminó el efecto: " + GameText.effect_name(str(data.get("effectCode", ""))))
		"GAME_FINISHED", "GAME_ABANDONED":
			_schedule_result()

func _on_dice_rolled(data: Dictionary) -> void:
	var who := str(data.get("playerId", ""))
	var values: Array = data.get("dice", []) if data.get("dice") is Array else []
	if values.size() < 2:
		return
	RollHold.start()
	_last_dice[int(GameNet.player(who).get("seat", -1))] = values
	var card: PlayerCardGame = _cards.get(int(GameNet.player(who).get("seat", -1)))
	if card != null:
		card.play_roll(values)                    # la tarjeta de quien tira (también la mía)
	if who == GameNet.me and _dices != null:
		_dices.play_roll(values)                  # y el panel grande de abajo
	if int(values[0]) == int(values[1]):
		_toast("¡Pares! Turno extra" if who == GameNet.me \
				else "¡Pares de %s!" % _short_name(_player_name(who)))

func _on_piece_moved(data: Dictionary) -> void:
	if data.get("cardId") != null:
		_on_card_piece_moved(data)
		return
	var owner_id := _owner_of_piece(str(data.get("pieceId", "")))
	if str(data.get("status", "")) == "CROWNED":         # US-015
		_toast("¡Ficha coronada!" if owner_id == GameNet.me \
				else "%s coronó una ficha" % _short_name(_player_name(owner_id)))
	elif data.get("from") == null:                        # sale de casa (US-011)
		_toast("Sacaste una ficha" if owner_id == GameNet.me \
				else "%s sacó una ficha" % _short_name(_player_name(owner_id)))
	elif owner_id == GameNet.me and data.get("to") != null:
		var from_id := int(data.get("from"))
		var to_id := int(data.get("to"))
		if Board.is_safe(to_id) and not Board.is_safe(from_id):
			_toast("Ficha a salvo en zona segura")        # US-013 esc. 1

func _on_piece_captured(data: Dictionary) -> void:
	var victim := _owner_of_piece(str(data.get("pieceId", "")))
	var killer := _owner_of_piece(GameText.s(data.get("byPieceId")))
	if data.get("cardId") != null and killer == "":        # US-010 esc. 3: captura hecha por una carta
		_on_card_piece_returned({"playerId": victim})
	elif victim == GameNet.me:                            # US-010 esc. 4: avisar al afectado
		_toast("¡Te capturaron una ficha!", true)
		_flash_screen()
	elif killer == GameNet.me:
		_toast("¡Capturaste una ficha de %s!" % _short_name(_player_name(victim)))
	else:
		_toast("%s capturó una ficha de %s" % [
				_short_name(_player_name(killer)), _short_name(_player_name(victim))])

## Una carta movió una ficha: salir de la cárcel (US-011 esc. 2), a zona segura
## (US-013 esc. 3) o a la meta (US-015 esc. 2).
func _on_card_piece_moved(data: Dictionary) -> void:
	var owner_id := _owner_of_piece(str(data.get("pieceId", "")))
	var who := "Tu ficha" if owner_id == GameNet.me else "Una ficha de %s" % _short_name(_player_name(owner_id))
	if str(data.get("status", "")) == "CROWNED":
		_toast("%s llegó a la meta por carta" % who)
	elif data.get("from") == null:
		_toast("%s salió de la cárcel por carta" % who)
	elif data.get("to") != null and Board.is_safe(int(data.get("to"))):
		_toast("%s avanzó a zona segura" % who)
	else:
		_toast("%s avanzó por carta" % who)

## Una ficha volvió a casa sin ficha atacante (carta de matar o castigo): avisa al afectado (US-010 esc. 4).
func _on_card_piece_returned(data: Dictionary) -> void:
	var victim := str(data.get("playerId", ""))
	if victim == GameNet.me:
		_toast("¡Una carta te devolvió una ficha a casa!", true)
		_flash_screen()
	else:
		_toast("Una carta devolvió una ficha de %s a casa" % _short_name(_player_name(victim)))

## Un efecto de turno se gastó (p. ej. turno perdido); el siguiente TURN_CHANGED ya viene en el lote.
func _on_effect_consumed(data: Dictionary) -> void:
	var who := str(data.get("playerId", ""))
	if str(data.get("effectCode", "")) == "SKIP_NEXT_TURN":
		_toast("Pierdes este turno" if who == GameNet.me else "%s pierde su turno" % _short_name(_player_name(who)))

## Mensajes en cola para que varios eventos de la misma jugada no se pisen.
## `urgent` descarta lo pendiente y se muestra al momento (errores, captura propia).
func _toast(text: String, urgent := false) -> void:
	if _toast_label == null or text == "":
		return
	if urgent:
		_toast_queue.clear()
		_show_toast(text)
		return
	_toast_queue.append(text)
	while _toast_queue.size() > TOAST_MAX_QUEUE:
		_toast_queue.pop_front()
	if _toast_left <= 0.0:
		_show_toast(_toast_queue.pop_front())

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_left = TOAST_TIME

func _tick_toast(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	if _toast_left > 0.0:
		return
	if _toast_queue.is_empty():
		_toast_label.visible = false
	else:
		_show_toast(_toast_queue.pop_front())

func _flash_screen() -> void:
	if _flash == null:
		return
	_flash.color.a = 0.35
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.5)

# --- Fin de la partida (US-014) -----------------------------------------------------------------------

## Pantalla de victoria para todos los jugadores. Solo hay un ganador y no se
## juega por puestos. Se muestra una vez, con un respiro tras el último movimiento.
func _schedule_result() -> void:
	if _result_scheduled or _hud == null:
		return
	_result_scheduled = true
	await get_tree().create_timer(RESULT_DELAY).timeout
	if is_inside_tree():
		_show_result()

func _show_result() -> void:
	var status := str(GameNet.state.get("status", ""))
	var winner_id := str(GameNet.state.get("winnerId", "")) if GameNet.state.get("winnerId") != null else ""
	var title := "FIN DE LA PARTIDA"
	var detail := "La partida terminó sin ganador"
	var swatch := Color(0.6, 0.6, 0.6)
	var crowned_text := ""
	if status == "FINISHED" and winner_id != "":
		var seat := int(GameNet.player(winner_id).get("seat", -1))
		if seat >= 0:
			swatch = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
		title = "¡GANASTE!" if winner_id == GameNet.me else "¡VICTORIA!"
		detail = "Ganó %s (%s)" % [_short_name(_player_name(winner_id)),
				SEAT_NAMES[posmod(seat, SEAT_NAMES.size())] if seat >= 0 else "?"]
		crowned_text = "4 fichas coronadas"

	_result_panel = Control.new()
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP     # nada debajo recibe clics
	_hud.add_child(_result_panel)
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var title_settings := LABEL_WHITE.duplicate() as LabelSettings
	title_settings.font_size = 16
	box.add_child(_result_label(title, title_settings))
	var color_block := ColorRect.new()
	color_block.color = swatch
	color_block.custom_minimum_size = Vector2(24, 24)
	color_block.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(color_block)
	box.add_child(_result_label(detail, LABEL_WHITE))
	if crowned_text != "":
		box.add_child(_result_label(crowned_text, LABEL_WHITE))
	var back := END_TURN_BUTTON.instantiate() as TextureButton
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	back.set_text("Menú")
	back.pressed.connect(_on_result_back)

func _result_label(text: String, settings: LabelSettings) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

## Vuelve al menú (el destino exacto está por confirmar).
func _on_result_back() -> void:
	GameState.leave_game()

# --- Nombres ------------------------------------------------------------------------------------------

## Game solo conoce ids; los nombres vienen de la sala (Lobby.data) si aún está.
func _player_name(pid: String) -> String:
	return GameText.player_name(pid)

func _short_name(full_name: String) -> String:
	return full_name if full_name.length() <= 10 else full_name.substr(0, 10)

## Dueño de una ficha a partir de su id "seat-{asiento}-piece-{n}"; "" si no se sabe.
func _owner_of_piece(piece_id: String) -> String:
	var parts := piece_id.split("-")
	if parts.size() < 4 or parts[0] != "seat":
		return ""
	var seat := int(parts[1])
	for p in GameNet.state.get("players", []):
		if int(p.get("seat", -1)) == seat:
			return str(p.get("id", ""))
	return ""

# --- Letrero del minimapa -------------------------------------------------------------------

func _build_hover() -> void:
	_hover = PanelContainer.new()
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.visible = false
	_hud.add_child(_hover)
	_hover_label = Label.new()
	_hover_label.label_settings = LABEL_WHITE.duplicate() as LabelSettings
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.add_child(_hover_label)

## Si el ratón pasa cerca de una casilla del minimapa, muestra qué casilla es, de qué
## tipo (carta, zona segura, corredor, corona) y qué fichas hay en ella.
func _update_hover() -> void:
	if _hover == null or _layer == null or _minimap_panel == null:
		return
	var mouse := get_viewport().get_mouse_position()
	if not _minimap_panel.is_visible_in_tree() or not _minimap_panel.get_global_rect().has_point(mouse):
		_hover.visible = false
		return
	var local := _layer.get_local_mouse_position()
	var best := -1
	var best_distance := HOVER_RADIUS
	for id in BoardMap.CELL_COUNT:
		var distance :float= _layer.map_to_local(BoardMap.minimap_cell(id)).distance_to(local)
		if distance <= best_distance:
			best = id
			best_distance = distance
	if best < 0:
		_hover.visible = false
		return
	var text := _cell_info(best)
	if text != _hover_text:
		_hover_text = text
		_hover_label.text = text
		_hover.reset_size()
	_hover.visible = true
	var limit := get_viewport().get_visible_rect().size - _hover.size
	_hover.position = Vector2(minf(mouse.x + 12.0, limit.x), minf(mouse.y + 12.0, limit.y))

func _cell_info(id: int) -> String:
	var lines := PackedStringArray(["Casilla %d" % id])
	var kind := str(Board.cell(id).get("kind", ""))
	if Board.trivia_ids.has(id):
		lines.append("Casilla de carta")
	elif Board.is_safe(id):
		lines.append("Zona segura")
	elif kind == Board.KIND_CROWN:
		lines.append("Corona")
	elif kind == Board.KIND_FINISH_LANE:
		lines.append("Corredor final")
	else:
		lines.append("Casilla común")
	var counts := {}
	for p in GameNet.state.get("pieces", []):
		var seat := BoardMap.seat_of_piece(p)
		if seat >= 0 and BoardMap.piece_cell_id(p, seat) == id:
			counts[seat] = int(counts.get(seat, 0)) + 1
	if counts.is_empty():
		lines.append("Sin fichas")
	else:
		var total := 0
		var parts := PackedStringArray()
		for seat in counts:
			total += int(counts[seat])
			parts.append("%s x%d" % [SEAT_NAMES[posmod(int(seat), SEAT_NAMES.size())], int(counts[seat])])
		lines.append("Fichas: %d (%s)" % [total, ", ".join(parts)])
	return "\n".join(lines)

# --- Minimapa (Fase 1) -----------------------------------------------------------------------------

func _refresh_minimap(state: Dictionary) -> void:
	if _pieces_root == null:
		return
	var entries: Array = []
	var group_sizes := {}
	for p in state.get("pieces", []):
		var seat := BoardMap.seat_of_piece(p)
		if seat < 0:
			continue
		var cell := Vector2i.ZERO
		var key := ""
		if BoardMap.is_home(p):
			cell = BoardMap.minimap_home(seat, int(p.get("number", 0)))
			key = "home-%s" % str(p.get("id", ""))
		else:
			var cell_id := BoardMap.piece_cell_id(p, seat)
			if not BoardMap.is_valid_id(cell_id):
				continue
			cell = BoardMap.minimap_cell(cell_id)
			key = "cell-%d" % cell_id
		group_sizes[key] = int(group_sizes.get(key, 0)) + 1
		entries.append({"piece": p, "seat": seat, "key": key, "cell": cell})

	var placed_count := {}
	var seen := {}
	for e in entries:
		var id := str(e.piece.get("id", ""))
		seen[id] = true
		var index := int(placed_count.get(e.key, 0))
		placed_count[e.key] = index + 1
		var shift := (index - (int(group_sizes[e.key]) - 1) / 2.0) * SHARED_CELL_SPACING
		var node := _piece_node(id, e.seat)
		node.position = _layer.map_to_local(e.cell) + Vector2(shift, 0)

	for id in _pieces.keys():
		if not seen.has(id):
			_pieces[id].queue_free()
			_pieces.erase(id)

func _piece_node(id: String, seat: int) -> MinimapPiece:
	if _pieces.has(id):
		return _pieces[id]
	var node := MINIMAP_PIECE.instantiate() as MinimapPiece
	node.name = id
	node.color = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	_pieces_root.add_child(node)
	_pieces[id] = node
	return node
