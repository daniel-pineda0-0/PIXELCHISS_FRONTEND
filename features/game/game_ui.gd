extends CanvasLayer
## HUD de la partida.
## US-020: minimapa con las fichas de todos los jugadores y botones para recorrer
## los chunks del tablero (game.gd los conecta a BoardView).
## Reglas v4-100: confirma sola la animación de tus dados (si no, el servidor no abre el
## movimiento), muestra el reloj de cada fase (lanzar 60 s, confirmar 10 s, mover 30 s),
## los intentos de salida, la suma de dados, SOPLAR y la coronación con tres pares.
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
const SEAT_NAMES := ["Rojo", "Azul", "Verde", "Amarillo"]
const RESULT_DELAY := 1.2           # deja ver el último movimiento antes de la pantalla final
const LOW_TIME := 10                # segundos: el cronómetro se pone rojo

## Texto para el jugador de los rechazos del servidor (guía §10). Los que no están
## aquí se muestran con el mensaje que mande el servidor.
const ERROR_TEXT := {
	"NOT_YOUR_TURN": "No es tu turno",
	"TURN_EXPIRED": "Se acabó el tiempo del turno",
	"ALREADY_ROLLED": "Ya lanzaste los dados",
	"ROLL_REQUIRED": "Primero lanza los dados",
	"ANIMATION_PENDING": "Espera a que terminen los dados",
	"STALE_ROLL": "Esa tirada ya no está vigente",
	"CROWN_CHOICE_REQUIRED": "Primero elige qué ficha coronar",
	"NO_CROWN_CHOICE": "No hay coronación pendiente",
	"INVALID_CROWN_PIECE": "Esa ficha no se puede coronar",
	"HOME_RELEASE_AUTOMATIC": "Las fichas salen solas al sacar pares",
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
	"PIECE_CAPTURE_LOCKED": "Esa ficha ya capturó en esta tirada",
	"PIECE_RELEASED_THIS_ROLL": "La ficha que acaba de salir no puede moverse en esta tirada",
	"STALE_ORIGIN": "El tablero cambió, intenta de nuevo",
	"INVALID_DESTINATION": "Ese movimiento ya no es válido",
	"NOT_YOUR_PIECE": "Esa ficha no es tuya",
	"DOUBLES_REQUIRED": "Necesitas sacar pares",
	"UNAUTHORIZED_DICE": "No puedes elegir los dados",
}

# Nodos de game_ui.tscn: se piden por nombre único (%), no por ruta. Si reorganizas el HUD,
# mientras conserve el nombre único, nada se rompe.
@onready var _hud: Control = %GameHUD
@onready var _hud_margin: Control = %HUDMargin
@onready var _minimap_panel: Control = %MiniMap
@onready var _layer: TileMapLayer = %TileMapLayer   # las fichas del minimapa van dentro, así comparten su transformación
@onready var _pieces_root: Node2D = %MiniPieces
@onready var _dices_panel: Control = %Dices          # panel grande de abajo: dados del turno + botón de lanzar
@onready var _dices = %MainDices                     # dices.gd (show_values / play_roll / clear)
@onready var _roll_button: Button = %PlayerButton
@onready var _left_button: Button = %ButtonL
@onready var _right_button: Button = %ButtonR
@onready var _player_cards_box: HBoxContainer = %PlayerCards
@onready var _turn_banner: TurnBanner = %TurnBanner
@onready var _end_button: TextureButton = %EndTurnButton
@onready var _toaster: Toast = %Toast
@onready var _hover: CellTooltip = %CellTooltip      # letrero al pasar el ratón por una casilla del minimapa
@onready var _result_screen: ResultScreen = %ResultScreen

var _pieces := {}                   # id de ficha -> MinimapPiece
var _card_nodes: Array[PlayerCardGame] = []  # tarjetas del HUD, en el orden de la escena
var _cards := {}                    # asiento -> PlayerCardGame
var _cards_ready := false
var _tick := 0.0
var _confirmed_roll := ""           # rollId cuya animación ya confirmé
var _confirm_tries := {}            # rollId -> intentos de confirmación (para no reintentar sin fin)
var _end_armed_version := -1         # versión en la que ya avisé "puedes capturar" antes de pasar
var _result_scheduled := false
var _last_dice := {}                # asiento -> últimos dados que sacó (se conservan entre turnos)
var _pending_events: Array = []     # eventos en espera mientras ruedan los dados
var _was_holding := false

func _ready() -> void:
	# El HUD ocupa toda la pantalla: si no deja pasar el ratón, el tablero no recibe clics.
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_left_button.button_down.connect(func(): view_step.emit(-1))
	_left_button.button_up.connect(func(): view_step.emit(0))
	_right_button.button_down.connect(func(): view_step.emit(1))
	_right_button.button_up.connect(func(): view_step.emit(0))

	_roll_button.pressed.connect(_on_roll_pressed)
	_roll_button.focus_mode = Control.FOCUS_NONE
	_end_button.pressed.connect(_on_end_turn_pressed)
	_result_screen.back_pressed.connect(_on_result_back)

	for child in _player_cards_box.get_children():
		if child is PlayerCardGame:
			child.visible = false          # se muestran según cuántos jugadores haya
			_card_nodes.append(child)

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
	RollHold.observe(state)           # una tirada nueva pausa el redibujo hasta que paren los dados
	if RollHold.active():
		return
	_refresh_minimap(state)
	_refresh_turn(state)

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
	# END_TURN exige tirada confirmada y ninguna elección de corona pendiente (guía §6.7).
	return _is_playing() and GameNet.is_my_turn() and bool(_turn().get("rolled", false)) \
			and GameNet.animation_status() == "COMPLETED" \
			and not bool(_turn().get("crownChoiceRequired", false)) \
			and not _has_challenge() and not GameNet.busy and not RollHold.active()

## ¿Tengo alguna ficha en el tablero? Sin ellas, cada tirada sin par es un intento de salida.
func _has_board_piece(pid: String) -> bool:
	for piece in GameNet.state.get("pieces", []):
		if str(piece.get("ownerId", "")) == pid and str(piece.get("status", "")) == "BOARD":
			return true
	return false

func _has_home_piece(pid: String) -> bool:
	for piece in GameNet.state.get("pieces", []):
		if str(piece.get("ownerId", "")) == pid and BoardMap.is_home(piece):
			return true
	return false

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
	if GameNet.state.is_empty():
		_turn_banner.set_message("Conectando...")
		return
	if not _is_playing():
		_turn_banner.set_message("Partida terminada")
		return
	var turn := _turn()
	var active_id := str(turn.get("playerId", ""))
	var mine := active_id == GameNet.me
	var who := _short_name(_player_name(active_id))
	var rolled := bool(turn.get("rolled", false))
	var choosing_crown := bool(turn.get("crownChoiceRequired", false))
	var text := ""
	if GameNet.state.get("trivia") != null:
		text = "Responde la trivia" if mine else "%s responde trivia" % who
	elif GameNet.state.get("card") != null:
		text = "Elige un objetivo" if mine else "%s elige objetivo" % who
	elif rolled and GameNet.animation_status() == "WAITING":
		text = "Tus dados..." if mine else "Dados de %s" % who
	elif choosing_crown:
		text = "Tres pares: elige qué coronar" if mine else "%s elige qué coronar" % who
	elif mine:
		if not rolled:
			text = "Tu turno: lanza"
			if not _has_board_piece(GameNet.me) and _has_home_piece(GameNet.me):
				var attempt := clampi(int(turn.get("homeAttempts", 0)) + 1, 1, 3)
				text += " (%d/3)" % attempt            # tres intentos para sacar par sin fichas en juego
		elif GameNet.legal_moves.is_empty():
			text = "Tu turno"
		else:
			text = "Mueve una ficha"
	else:
		text = "Turno de " + who
	var seconds := _seconds_left()
	if seconds >= 0:
		text += "  %ds" % seconds
	_turn_banner.set_message(text, seconds >= 0 and seconds <= LOW_TIME)

## Plazo (Unix ms) del reloj que corresponde a la fase actual (guía §8.1). `turn.deadline` por sí
## solo no sirve: cambia de significado y durante una trivia NO es un reloj activo. 0 = sin reloj.
##   trivia pendiente        → trivia.deadline        (15 s propios; el movimiento queda pausado)
##   carta pendiente         → card.deadline          (15 s)
##   sin lanzar              → turn.deadline          (60 s)
##   esperando confirmación  → turn.animationDeadline (10 s)
##   moviendo                → turn.deadline          (30 s desde confirmar, si movementStartedAt != null)
## Las liberaciones por par y el tercer par no abren reloj de movimiento: ahí no se muestra nada.
func _active_deadline() -> float:
	var state := GameNet.state
	var turn := _turn()
	if state.get("trivia") is Dictionary:
		return float(state.trivia.get("deadline", 0))
	if state.get("card") is Dictionary:
		return float(state.card.get("deadline", 0))
	if not bool(turn.get("rolled", false)):
		return float(turn.get("deadline", 0))
	match GameNet.animation_status():
		"WAITING":
			return float(turn.get("animationDeadline", 0))
		"COMPLETED":
			return float(turn.get("deadline", 0)) if turn.get("movementStartedAt") != null else 0.0
	return 0.0

## Segundos que quedan del reloj de la fase. Solo se muestra: el servidor decide cuándo vence y
## pasa el turno por su cuenta (no se cierra nada desde aquí). -1 = sin reloj.
func _seconds_left() -> int:
	var deadline := _active_deadline()
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
		_auto_confirm_animation()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.2
		_update_turn_label()
	if _dices_panel != null:
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		_dices_panel.modulate = Color(1.0, 1.0, pulse) if _can_roll() else Color.WHITE
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

## Termina de animar tu tirada: avisa al servidor para que empiece el reloj de movimiento.
## Espera a que paren los dados y a que se hayan atendido los eventos de la tirada. También
## cubre volver a la partida con la animación aún pendiente: confirma de inmediato.
func _auto_confirm_animation() -> void:
	if RollHold.active() or not _pending_events.is_empty() or GameNet.busy:
		return
	if not GameNet.awaiting_animation_confirmation():
		return
	var roll_id := str(_turn().get("rollId", ""))
	if roll_id == _confirmed_roll:
		return
	var tries := int(_confirm_tries.get(roll_id, 0))
	if tries >= 3:
		return
	if GameNet.confirm_animation():
		_confirmed_roll = roll_id
		_confirm_tries[roll_id] = tries + 1

func _can_capture() -> bool:
	for m in GameNet.legal_moves:
		if bool(m.get("capture", false)):
			return true
	return false

## SOPLAR: si pasas con una captura posible, el servidor devuelve a casa una ficha tuya.
## La primera pulsación avisa; la segunda, en la misma jugada, pasa de verdad.
func _on_end_turn_pressed() -> void:
	if not _can_end_turn():
		return
	var version := int(GameNet.state.get("version", 0))
	if _end_armed_version != version and _can_capture():
		_end_armed_version = version
		_toast("¡Puedes capturar! Pasar puede costarte una ficha", true)
		return
	GameNet.end_turn()

# --- Avisos ------------------------------------------------------------------------------------------

func _on_action_rejected(code: String, message: String) -> void:
	if code in ["STALE_ROLL", "TURN_EXPIRED", "STALE_VERSION", "ANIMATION_PENDING"]:
		_confirmed_roll = ""                  # tras el sync se puede reintentar la confirmación
	if code in GameNet.NO_SYNC_ERRORS:
		return
	_toast(str(ERROR_TEXT.get(code, message if message != "" else code)), true)

func _on_legal_moves(_moves: Array) -> void:
	_update_turn_label()

## Los eventos se atienden en orden. Si ruedan unos dados, los siguientes esperan:
## así lo que hace un bot justo después de tirar no pisa la animación.
func _on_events(events: Array, _version: int) -> void:
	# Las salidas automáticas llegan una por ficha: se resumen en un solo aviso por jugador.
	var released := {}
	for e in events:
		if str(e.get("type", "")) == "PIECE_RELEASED":
			var d: Variant = e.get("data")
			var owner_id := _owner_of_piece(str(d.get("pieceId", ""))) if d is Dictionary else ""
			released[owner_id] = int(released.get(owner_id, 0)) + 1
		else:
			_pending_events.append(e)
	for owner_id in released:
		_pending_events.append({"type": "RELEASE_SUMMARY",
				"data": {"ownerId": owner_id, "count": released[owner_id]}})
	_drain_events()

## La tirada nueva se atiende aunque haya una pausa en curso (es la que la provoca); el
## resto de eventos espera a que paren los dados.
func _drain_events() -> void:
	while not _pending_events.is_empty():
		var next: Variant = _pending_events[0]
		if RollHold.active() and str(next.get("type", "")) != "DICE_ROLLED":
			break
		_handle_event(_pending_events.pop_front())

func _handle_event(e: Variant) -> void:
	var data: Dictionary = e.data if e.get("data") is Dictionary else {}
	match str(e.get("type", "")):
		"TURN_CHANGED":
			if str(data.get("playerId", "")) == GameNet.me:
				_toast("¡Es tu turno!")
		"ROLL_AVAILABLE":
			_on_roll_available(data)
		"TURN_EXPIRED":
			var who := str(data.get("playerId", ""))
			var no_confirm := str(data.get("reason", "")) == "ANIMATION_TIMEOUT"
			if who == GameNet.me:
				_toast("No confirmaste los dados a tiempo" if no_confirm else "Se acabó tu tiempo", true)
			else:
				_toast("Se acabó el tiempo de " + _short_name(_player_name(who)))
		"RELEASE_SUMMARY":
			_on_release_summary(data)
		"PIECE_BLOWN":
			_on_piece_blown(data)
		"BLOW_AMBIGUOUS":
			var first: Variant = data.get("pieceIds")
			if first is Array and not first.is_empty() and _owner_of_piece(str(first[0])) == GameNet.me:
				_toast("Había varias capturas: esta vez nadie pierde ficha")
		"CROWN_CHOICE_REQUIRED":
			var chooser := str(data.get("playerId", ""))
			_toast("¡Tres pares! Elige una ficha para coronar" if chooser == GameNet.me \
					else "¡Tres pares de %s!" % _short_name(_player_name(chooser)))
		"PIECE_CROWNED":
			var crown_owner := _owner_of_piece(str(data.get("pieceId", "")))
			_toast("¡Coronaste una ficha con tres pares!" if crown_owner == GameNet.me \
					else "%s coronó una ficha con tres pares" % _short_name(_player_name(crown_owner)))
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
		_toast("¡Pares!" if who == GameNet.me else "¡Pares de %s!" % _short_name(_player_name(who)))

func _on_piece_moved(data: Dictionary) -> void:
	if data.get("cardId") != null:
		_on_card_piece_moved(data)
		return
	var owner_id := _owner_of_piece(str(data.get("pieceId", "")))
	if str(data.get("status", "")) == "CROWNED":         # US-015
		_toast("¡Ficha coronada!" if owner_id == GameNet.me \
				else "%s coronó una ficha" % _short_name(_player_name(owner_id)))
	elif owner_id == GameNet.me and data.get("from") != null and data.get("to") != null:
		var from_id := int(data.get("from"))
		var to_id := int(data.get("to"))
		if Board.is_safe(to_id) and not Board.is_safe(from_id):
			_toast("Ficha a salvo en zona segura")        # US-013 esc. 1

func _on_piece_captured(data: Dictionary) -> void:
	var victim := _owner_of_piece(str(data.get("pieceId", "")))
	if str(data.get("reason", "")) == "HOME_RELEASE":        # salieron en la casilla de otro color
		if victim == GameNet.me:
			_toast("Tu ficha volvió a casa: ocupaba una salida ajena", true)
			_flash_screen()
		else:
			_toast("%s perdió una ficha: salieron en su casilla" % _short_name(_player_name(victim)))
		return
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

## Salida automática con pares (US-011): una sola línea por jugador.
func _on_release_summary(data: Dictionary) -> void:
	var owner_id := str(data.get("ownerId", ""))
	var count := int(data.get("count", 0))
	if count <= 0:
		return
	var many := "fichas" if count > 1 else "ficha"
	_toast("Sacaste %d %s" % [count, many] if owner_id == GameNet.me \
			else "%s sacó %d %s" % [_short_name(_player_name(owner_id)), count, many])

## Otra tirada en el mismo turno (pares o intento de salida). Solo avisa al jugador.
func _on_roll_available(data: Dictionary) -> void:
	if str(data.get("playerId", "")) != GameNet.me:
		return
	if not _has_board_piece(GameNet.me) and _has_home_piece(GameNet.me):
		var attempt := clampi(int(_turn().get("homeAttempts", 0)) + 1, 1, 3)
		_toast("Sin par: intento %d de 3, tira otra vez" % attempt)
	else:
		_toast("Tira otra vez")

## SOPLAR: no capturaste teniendo una captura legal y una ficha tuya vuelve a casa.
func _on_piece_blown(data: Dictionary) -> void:
	var owner_id := str(data.get("playerId", ""))
	if owner_id == GameNet.me:
		_toast("¡Soplaron tu ficha! Debías capturar", true)
		_flash_screen()
	else:
		_toast("%s perdió una ficha por no capturar" % _short_name(_player_name(owner_id)))

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

## Avisos y destello rojo: la cola y los tiempos viven en Toast (ui/toast.gd).
func _toast(text: String, urgent := false) -> void:
	_toaster.show_message(text, urgent)

func _flash_screen() -> void:
	_toaster.flash()

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

	_result_screen.show_result(title, detail, swatch, crowned_text)

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

## Si el ratón pasa cerca de una casilla del minimapa, muestra qué casilla es, de qué
## tipo (carta, zona segura, corredor, corona) y qué fichas hay en ella.
func _update_hover() -> void:
	var mouse := get_viewport().get_mouse_position()
	if not _minimap_panel.is_visible_in_tree() or not _minimap_panel.get_global_rect().has_point(mouse):
		_hover.hide_info()
		return
	var local := _layer.get_local_mouse_position()
	var best := -1
	var best_distance := HOVER_RADIUS
	for id in BoardMap.CELL_COUNT:
		var distance: float = _layer.map_to_local(BoardMap.minimap_cell(id)).distance_to(local)
		if distance <= best_distance:
			best = id
			best_distance = distance
	if best < 0:
		_hover.hide_info()
		return
	_hover.show_info(_cell_info(best), mouse)

func _cell_info(id: int) -> String:
	var lines := PackedStringArray(["Casilla %d" % id])
	var kind := str(Board.cell(id).get("kind", ""))
	if Board.trivia_ids.has(id):
		lines.append("Casilla de carta")
	elif Board.is_exit(id):
		lines.append("Salida (caben 4 fichas)")
	elif Board.is_safe(id):
		lines.append("Zona segura (caben 2 fichas)")
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
