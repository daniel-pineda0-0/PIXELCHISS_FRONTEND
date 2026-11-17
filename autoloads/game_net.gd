extends Node
## Conexión en tiempo real con el Game Service (WebSocket por el gateway).
## Sigue GUIA_GAME_PIXELCHISS.md: el servidor es autoritativo; aquí solo se
## guarda el último estado confirmado y se mandan acciones. Las pantallas no
## hablan con el socket: escuchan estas señales y llaman a las acciones.
##
##   GameNet.state_changed.connect(...)     # estado nuevo -> redibujar
##   GameNet.events_received.connect(...)   # eventos -> animar (una vez por versión)
##   GameNet.join(GameState.game_id)
##   GameNet.roll() / move(m) / answer_trivia(i) / pick_card(c) / end_turn()
##
## Lo que resuelve por su cuenta (guía §8 y §9):
## - aplica un estado solo si su `version` >= la local;
## - deduplica eventos por versión (llegan en ACK y en GAME_UPDATED);
## - una sola acción en vuelo (`busy`), con requestId único y expectedVersion;
## - pide `legalMoves` (SYNC_REQUEST) cuando es tu turno y ya lanzaste;
## - se resincroniza ante STALE_VERSION y huecos de versión;
## - renueva el JWT a los ~12 min abriendo un segundo socket (sin ventana de
##   desconexión) y reconecta con backoff si el socket se cae.

signal joined                                   # (re)conectado y con estado vigente
signal state_changed(new_state: Dictionary)
signal legal_moves_changed(moves: Array)
signal events_received(events: Array, version: int)
signal action_rejected(code: String, message: String)
signal busy_changed(is_busy: bool)
signal status_changed(new_status: int)
signal fatal(code: String, message: String)    # no se puede seguir en esta partida
signal session_expired                         # el refresh token ya no sirve

enum Status { IDLE, CONNECTING, ONLINE, RECONNECTING }

const TOKEN_RENEW_AFTER := 12.0 * 60.0   # el JWT dura 15 min
const TOKEN_MAX_AGE := 10.0 * 60.0       # más viejo que esto se renueva antes de conectar
const ACTION_TIMEOUT := 8.0              # sin respuesta a una acción: se resincroniza
const SYNC_COOLDOWN := 0.25
const RECONNECT_DELAYS := [0.5, 1.0, 2.0, 4.0]
const RECONNECT_GIVE_UP := 90.0          # el servidor retira al jugador a los 60 s
const INBOUND_BUFFER := 262144

const SYNC_ERRORS := ["STALE_VERSION", "CONCURRENT_UPDATE", "NOT_YOUR_TURN",
		"TURN_EXPIRED", "SERVICE_UNAVAILABLE"]
const TOKEN_ERRORS := ["TOKEN_EXPIRED", "INVALID_TOKEN"]
const NO_SYNC_ERRORS := ["UNAUTHENTICATED", "JOIN_REQUIRED", "ALREADY_JOINED",
		"INVALID_JSON", "UNKNOWN_ACTION", "INVALID_ACTION", "AUTH_TIMEOUT"]
const FATAL_TEXT := {
	"NOT_MEMBER": "No eres parte de esta partida",
	"BOT_IDENTITY": "Identidad no válida para esta partida",
	"PLAYER_RETIRED": "Fuiste retirado de la partida",
	"GAME_NOT_FOUND": "La partida ya no existe",
	"INVALID_GAME_ID": "Partida no válida",
	"UNSUPPORTED_BOARD_LAYOUT": "Esta partida es de una versión anterior del tablero. Crea una nueva",
	"CONNECTION_LOST": "Se perdió la conexión con el servidor",
}

## Un socket. Durante el relevo de token hay dos a la vez.
class Link extends RefCounted:
	var peer := WebSocketPeer.new()
	var token := ""
	var opened := false
	var joined := false
	var dead := false

# --- Estado público (solo lectura desde las pantallas) ---
var game_id := ""
var me := ""                          # playerId (sub del JWT)
var state: Dictionary = {}            # último snapshot confirmado
var legal_moves: Array = []           # válidos para `state.version`
var status: Status = Status.IDLE
var busy := false                     # hay una acción esperando respuesta

# --- Interno ---
var _active: Link = null
var _next: Link = null                # relevo de token
var _closing: Array = []              # sockets cerrándose (hay que seguir haciendo poll)
var _gen := 0                         # invalida awaits viejos tras leave()/join()
var _tag := ""
var _request_counter := 0
var _pending_request := ""
var _busy_since := 0.0
var _token_at := 0.0                  # cuándo se renovó el token por última vez
var _force_token := false
var _attempt := 0
var _offline_since := 0.0
var _last_event_version := -1
var _legal_version := -1
var _sync_asked_version := -1
var _last_sync_at := -100.0

var _renew_timer := Timer.new()
var _retry_timer := Timer.new()

func _ready() -> void:
	_renew_timer.one_shot = true
	_renew_timer.timeout.connect(_on_renew_timeout)
	add_child(_renew_timer)
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_connect_active)
	add_child(_retry_timer)

# --- Conexión ---

## Entra a la partida: conecta, AUTH, JOIN_GAME y recibe el estado.
func join(gid: String) -> void:
	_shutdown()
	game_id = gid
	state = {}
	legal_moves = []
	_tag = "%08x" % randi()
	_request_counter = 0
	_last_event_version = -1
	_legal_version = -1
	_sync_asked_version = -1
	_attempt = 0
	_force_token = false
	_offline_since = 0.0
	_set_busy(false)
	_set_status(Status.CONNECTING)
	_connect_active()

## Cierra todo y olvida la partida.
func leave() -> void:
	_shutdown()
	game_id = ""
	me = ""
	state = {}
	_clear_legal()
	_set_busy(false)

# --- Acciones (devuelven false si no se pudo enviar ahora) ---

func roll(chosen_dice: Array = []) -> bool:
	var extra := {}
	if chosen_dice.size() > 0:       # solo si turn.diceSelectionRequired
		extra["chosenDice"] = chosen_dice.map(func(d): return int(d))
	return _act("ROLL_DICE", extra)

## `m` es un elemento de `legal_moves`; se copia tal cual, no se calcula nada.
func move(m: Dictionary) -> bool:
	return _act("MOVE_REQUEST", {
		"pieceId": m.get("pieceId"),
		"dieIndex": int(m.get("dieIndex", 0)),
		"dieValue": int(m.get("dieValue", 0)),
		"fromPosition": _int_or_null(m.get("from")),
		"targetPosition": _int_or_null(m.get("to")),
	})

func answer_trivia(answer_index: int) -> bool:
	var trivia := _dict(state, "trivia")
	if trivia.is_empty():
		return false
	return _act("TRIVIA_ANSWER", {"challengeId": trivia.get("id"), "answerIndex": answer_index})

## `choice` es un elemento de `state.card.choices`.
func pick_card(choice: Dictionary) -> bool:
	var card := _dict(state, "card")
	if card.is_empty():
		return false
	return _act("CARD_TARGET", {
		"challengeId": card.get("id"),
		"pieceId": choice.get("pieceId"),
		"targetPieceId": choice.get("targetPieceId"),
		"targetPlayerId": choice.get("targetPlayerId"),
		"targetPosition": _int_or_null(choice.get("targetPosition")),
	})

func end_turn() -> bool:
	return _act("END_TURN")

## Pide el snapshot vigente + legalMoves. No lleva requestId ni versión.
## Ignora llamadas pegadas (p. ej. un ERROR que dispara otro): evita bucles.
func sync() -> void:
	if _now() - _last_sync_at < SYNC_COOLDOWN:
		return
	_send_sync()

func _send_sync() -> void:
	if _active == null or not _active.opened:
		return
	_last_sync_at = _now()
	_send_on(_active, {"type": "SYNC_REQUEST", "gameId": game_id})

# --- Consultas para la UI ---

func is_my_turn() -> bool:
	return state.get("status") == "ACTIVE" and str(_dict(state, "turn").get("playerId", "")) == me

## Datos de un jugador del snapshot ({} si no está).
func player(player_id: String) -> Dictionary:
	for p in state.get("players", []):
		if str(p.get("id", "")) == player_id:
			return p
	return {}

func status_name() -> String:
	return Status.keys()[status]

# --- Envío ---

func _act(type: String, extra: Dictionary = {}) -> bool:
	if busy or _active == null or not _active.joined or state.is_empty():
		return false
	_request_counter += 1
	var rid := "%s-%s-%d" % [type.to_lower().replace("_", "-"), _tag, _request_counter]
	var msg := {
		"type": type,
		"gameId": game_id,
		"requestId": rid,
		"expectedVersion": int(state.get("version", 0)),
	}
	msg.merge(extra)
	_set_busy(true)
	_pending_request = rid
	_send_on(_active, msg)
	return true

func _send_on(link: Link, msg: Dictionary) -> void:
	link.peer.send_text(JSON.stringify(msg))

# --- Ciclo de los sockets ---

func _process(_delta: float) -> void:
	for i in range(_closing.size() - 1, -1, -1):
		var old: Link = _closing[i]
		old.peer.poll()                     # el cierre necesita poll() para completarse
		if old.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closing.remove_at(i)
	if status == Status.IDLE:
		return
	for link in [_active, _next]:
		if link != null:
			_poll(link)
	if busy and _now() - _busy_since > ACTION_TIMEOUT:
		_set_busy(false)
		sync()

func _poll(link: Link) -> void:
	if link.dead:
		return
	link.peer.poll()                        # obligatorio cada frame (ping/pong, cierres)
	match link.peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not link.opened:
				link.opened = true
				_send_on(link, {"type": "AUTH", "token": link.token})   # primer mensaje < 10 s
			_drain(link)
		WebSocketPeer.STATE_CLOSED:
			_drain(link)
			_on_link_closed(link)

func _drain(link: Link) -> void:
	while not link.dead and link.peer.get_available_packet_count() > 0:
		var text := link.peer.get_packet().get_string_from_utf8()
		var msg: Variant = JSON.parse_string(text)
		if msg is Dictionary:
			_handle(link, msg)

func _open_link(token: String) -> Link:
	var link := Link.new()
	link.token = token
	link.peer.inbound_buffer_size = INBOUND_BUFFER
	if link.peer.connect_to_url(Config.WS_URL) != OK:    # sin query string ni headers
		return null
	return link

func _connect_active() -> void:
	var gen := _gen
	var ok := await _ensure_token(_force_token)
	if gen != _gen:
		return
	_force_token = false
	if not ok:
		_expire()
		return
	var link := _open_link(Session.access_token)
	if link == null:
		_schedule_reconnect(false)
		return
	_active = link

func _on_link_closed(link: Link) -> void:
	if link.dead:
		return
	link.dead = true
	if link == _next:                       # el relevo falló: se reintenta luego
		_next = null
		_schedule_renew(30.0)
		return
	if link != _active:
		return
	_active = null
	if _next != null:                       # había un relevo en marcha: pasa a ser el activo
		_active = _next
		_next = null
		_go_offline()
		return
	_schedule_reconnect(false)

func _go_offline() -> void:
	if status != Status.RECONNECTING:
		_offline_since = _now()
		_set_status(Status.RECONNECTING)

func _schedule_reconnect(force_token: bool) -> void:
	if status == Status.IDLE:
		return
	_go_offline()
	if _now() - _offline_since > RECONNECT_GIVE_UP:
		_fatal("CONNECTION_LOST")
		return
	_force_token = _force_token or force_token
	var delay: float = RECONNECT_DELAYS[mini(_attempt, RECONNECT_DELAYS.size() - 1)]
	_attempt += 1
	_retry_timer.start(delay)

func _reconnect_now() -> void:
	if _active != null:
		_retire(_active)
		_active = null
	_schedule_reconnect(true)

# --- Token (el JWT dura 15 min y el socket muere al expirar) ---

## true si hay un access token usable. Renueva si es viejo o si `force`.
func _ensure_token(force: bool) -> bool:
	if force or _token_at == 0.0 or _now() - _token_at > TOKEN_MAX_AGE:
		if await Session.refresh():
			_token_at = _now()
		elif Session.access_token == "":    # Session.clear(): el refresh token ya no vale
			return false
		# Si falló por red se sigue con el token que haya.
	return Session.access_token != ""

func _schedule_renew(seconds: float) -> void:
	_renew_timer.start(maxf(seconds, 1.0))

func _schedule_next_renew() -> void:
	_schedule_renew(TOKEN_RENEW_AFTER - (_now() - _token_at))

func _on_renew_timeout() -> void:
	if _next != null:                       # el relevo anterior quedó atascado
		_retire(_next)
		_next = null
		_schedule_renew(30.0)
		return
	if status != Status.ONLINE or _active == null:
		_schedule_renew(10.0)
		return
	var gen := _gen
	var before := _token_at
	var ok := await _ensure_token(true)
	if gen != _gen:
		return
	if not ok:
		_expire()
		return
	if _token_at == before:                 # no se pudo renovar (red): reintentar pronto
		_schedule_renew(30.0)
		return
	_next = _open_link(Session.access_token)
	_schedule_renew(15.0 if _next != null else 30.0)

## El socket nuevo ya tiene estado: pasa a ser el activo y se cierra el viejo.
func _promote_next() -> void:
	var old := _active
	_active = _next
	_next = null
	if old != null:
		_retire(old)
	_schedule_next_renew()

# --- Mensajes del servidor ---

func _handle(link: Link, m: Dictionary) -> void:
	match str(m.get("type", "")):
		"AUTHENTICATED":
			me = str(m.get("playerId", ""))
			_send_on(link, {"type": "JOIN_GAME", "gameId": game_id})
		"GAME_STATE":
			_on_game_state(link, m)
		"ACTION_ACK":
			_on_update(m, false)
		"GAME_UPDATED":
			_on_update(m, true)
		"ERROR":
			_on_error(link, m)

func _on_game_state(link: Link, m: Dictionary) -> void:
	var snap := _dict(m, "state")
	if snap.is_empty():
		return
	link.joined = true
	if link == _next:
		_promote_next()
	var was_online := status == Status.ONLINE
	var v := int(snap.get("version", -1))
	var local := int(state.get("version", -1))
	if state.is_empty() or v > local:
		_set_state(snap)
	if state.is_empty() or v >= local:
		_set_legal(_arr(m, "legalMoves"), v)
	_attempt = 0
	_offline_since = 0.0
	if not was_online:
		_set_busy(false)                    # lo que estuviera en vuelo ya no cuenta
		_set_status(Status.ONLINE)
		_schedule_next_renew()
		joined.emit()
	_maybe_request_legal_moves()

## ACTION_ACK (solo a quien actuó) y GAME_UPDATED (a todos) traen `state`.
func _on_update(m: Dictionary, with_events: bool) -> void:
	var snap := _dict(m, "state")
	if snap.is_empty():
		return
	var v := int(snap.get("version", -1))
	var local := int(state.get("version", -1))
	var rid: Variant = m.get("requestId")
	if busy and rid is String and rid == _pending_request:
		_set_busy(false)
	var gap := with_events and local >= 0 and v > local + 1   # Pub/Sub no guarda historia
	if v > local:
		_set_state(snap)
		_clear_legal()
	if with_events and v > _last_event_version:
		_last_event_version = v
		var events := _arr(m, "events")
		if not events.is_empty():
			events_received.emit(events, v)
	if gap:
		sync()
	_maybe_request_legal_moves()

func _on_error(link: Link, m: Dictionary) -> void:
	var code := str(m.get("code", ""))
	var message := str(m.get("message", ""))
	if link == _next:                       # un fallo del relevo no afecta la partida
		_retire(_next)
		_next = null
		_schedule_renew(30.0)
		return
	_set_busy(false)                        # un ERROR no cambia nada: se puede volver a actuar
	if code in FATAL_TEXT:
		_fatal(code)
		return
	if code in TOKEN_ERRORS:
		_reconnect_now()
		return
	if code == "JOIN_REQUIRED":
		_send_on(link, {"type": "JOIN_GAME", "gameId": game_id})
		return
	action_rejected.emit(code, message)
	if code in NO_SYNC_ERRORS:
		push_warning("GameNet: %s %s" % [code, message])
		return
	if code not in SYNC_ERRORS:
		push_warning("GameNet: %s %s (bug del cliente?)" % [code, message])
	sync()

func _fatal(code: String) -> void:
	_shutdown()
	fatal.emit(code, FATAL_TEXT.get(code, "Error en la partida (%s)" % code))

func _expire() -> void:
	leave()
	session_expired.emit()

# --- Estado ---

func _set_state(snap: Dictionary) -> void:
	state = snap
	state_changed.emit(state)

func _set_legal(moves: Array, version: int) -> void:
	legal_moves = moves
	_legal_version = version
	legal_moves_changed.emit(legal_moves)

func _clear_legal() -> void:
	_legal_version = -1
	if legal_moves.is_empty():
		return
	legal_moves = []
	legal_moves_changed.emit(legal_moves)

## `legalMoves` solo viaja en GAME_STATE: se piden con SYNC_REQUEST cuando
## es tu turno, ya lanzaste y no hay trivia ni carta pendiente.
func _maybe_request_legal_moves() -> void:
	if state.is_empty() or state.get("status") != "ACTIVE" or not is_my_turn():
		return
	var turn := _dict(state, "turn")
	if not bool(turn.get("rolled", false)):
		return
	if state.get("trivia") != null or state.get("card") != null:
		return
	var v := int(state.get("version", -1))
	if _legal_version == v or _sync_asked_version == v:
		return
	_sync_asked_version = v
	_send_sync()                            # sin cooldown: es una vez por versión

func _set_busy(value: bool) -> void:
	if value:
		_busy_since = _now()
	else:
		_pending_request = ""
	if busy == value:
		return
	busy = value
	busy_changed.emit(busy)

func _set_status(new_status: Status) -> void:
	if status == new_status:
		return
	status = new_status
	status_changed.emit(status)

func _shutdown() -> void:
	_gen += 1
	_renew_timer.stop()
	_retry_timer.stop()
	for link in [_active, _next]:
		if link != null:
			_retire(link)
	_active = null
	_next = null
	_set_status(Status.IDLE)

## Cierra un socket y sigue haciéndole poll() hasta que termine el cierre.
func _retire(link: Link) -> void:
	link.dead = true
	if link.peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		link.peer.close(1000, "bye")
		_closing.append(link)

# --- Utilidades ---

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## JSON entrega todos los números como float y el servidor espera enteros.
func _int_or_null(v: Variant) -> Variant:
	if v == null:
		return null
	return int(v)

func _dict(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key)
	return v if v is Dictionary else {}

func _arr(d: Dictionary, key: String) -> Array:
	var v: Variant = d.get(key)
	return v if v is Array else []
