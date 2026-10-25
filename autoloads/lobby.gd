extends Node
## Estado de la sala actual y llamadas a lobby-service (vía gateway).
## Las pantallas solo pintan Lobby.data y escuchan sus señales; el servidor
## decide qué es válido y Lobby devuelve su mensaje de error tal cual.
##
## El lobby no tiene WebSocket: se consulta GET /api/lobbies/{code} cada
## POLL_INTERVAL y solo se avisa si `version` cambió. Un jugador expulsado se
## entera porque esa consulta le devuelve 403.

signal changed(lobby: Dictionary)
signal maps_loaded(maps: Array)
signal started(lobby: Dictionary)
signal left(reason: String)          # salida forzada: "kicked" o "closed"
signal session_expired

const STATUS_WAITING := "WAITING"
const STATUS_STARTED := "STARTED"
const POLL_INTERVAL := 1.5
const SEATS_BY_COUNT := {1: [0], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3]}   # igual que lobby-service
const KICKED_NOTICE := "Fuiste expulsado de la sala"
const CLOSED_NOTICE := "La sala ya no existe"

var data: Dictionary = {}
var maps: Array = []
var notice := ""                     # mensaje para mostrar en el menú al volver

var _poll_timer := Timer.new()
var _polling := false
var _start_emitted := false

func _ready() -> void:
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)

# --- Consultas de estado ---

func in_lobby() -> bool:
	return not data.is_empty()

func my_id() -> String:
	return str(int(Session.profile.get("id", 0)))

func is_host() -> bool:
	return in_lobby() and str(data.host_id) == my_id()

func me() -> Dictionary:
	for player in data.get("players", []):
		if player.user_id == my_id():
			return player
	return {}

## Mapa por el que votó el jugador; "" si aún no votó (el servidor manda null).
func my_vote() -> String:
	var voted = me().get("voted_map_id")
	return voted if voted is String else ""

## Mapa que va ganando; "" si nadie votó o hay empate (se sortea al iniciar).
func leading_map_id() -> String:
	var best := 0
	var leader := ""
	var tie := false
	for map_id in data.get("map_votes", {}):
		var count := int(data.map_votes[map_id])
		if count > best:
			best = count
			leader = map_id
			tie = false
		elif count == best and count > 0:
			tie = true
	return "" if tie else leader

## Asiento (color) del jugador en la posición `index`; el servidor reparte
## los asientos según cuántos participantes hay (US-016).
func seat_of(index: int, count: int) -> int:
	var seats: Array = SEATS_BY_COUNT.get(count, SEATS_BY_COUNT[4])
	return seats[min(index, seats.size() - 1)]

# --- Acciones. Todas devuelven {ok, status, data, error} ---

func create() -> Dictionary:
	var r := await _call(HTTPClient.METHOD_POST, "/api/lobbies")
	return _enter(r)

func join(code: String) -> Dictionary:
	var r := await _call(HTTPClient.METHOD_POST, "/api/lobbies/%s/join" % code.strip_edges().to_upper())
	return _enter(r)

func fetch_maps() -> bool:
	var r := await _call(HTTPClient.METHOD_GET, "/api/lobbies/maps")
	if r.ok:
		maps = r.data
		maps_loaded.emit(maps)
	return r.ok

func set_ready(is_ready: bool) -> Dictionary:
	return _apply_result(await _call(HTTPClient.METHOD_PUT, _path("ready"), {"ready": is_ready}))

func vote(map_id: String) -> Dictionary:
	return _apply_result(await _call(HTTPClient.METHOD_PUT, _path("vote"), {"map_id": map_id}))

func add_bot() -> Dictionary:
	return _apply_result(await _call(HTTPClient.METHOD_POST, _path("bots")))

func remove_bot(bot_id: String) -> Dictionary:
	return _apply_result(await _call(HTTPClient.METHOD_DELETE, _path("bots/" + bot_id)))

func kick(user_id: String) -> Dictionary:
	return _apply_result(await _call(HTTPClient.METHOD_DELETE, _path("players/" + user_id)))

func start() -> Dictionary:
	return _apply_result(await _call(HTTPClient.METHOD_POST, _path("start")))

## Salida voluntaria. Con la partida iniciada el servidor no deja salir
## (409): solo se limpia lo local.
func leave() -> void:
	if in_lobby() and data.status == STATUS_WAITING:
		await _call(HTTPClient.METHOD_POST, _path("leave"))
	_clear()

## Olvida la sala sin avisar al servidor (sesión vencida o cierre de sesión).
func clear() -> void:
	_clear()

# --- Internos ---

func _path(suffix: String) -> String:
	return "/api/lobbies/%s/%s" % [data.get("code", ""), suffix]

func _call(method: int, path: String, body: Variant = null) -> Dictionary:
	var r: Dictionary = await Api.request(method, path, body)
	r.error = "" if r.ok else _error_text(r)
	if r.status == 401:
		session_expired.emit()
	return r

func _error_text(r: Dictionary) -> String:
	if r.status == 0:
		return "No se pudo conectar con el servidor"
	if r.data is Dictionary and r.data.get("detail") is String:
		return r.data.detail
	return "Error inesperado (%d)" % r.status

func _enter(r: Dictionary) -> Dictionary:
	if r.ok:
		_start_emitted = false
		data = {}
		_set_lobby(r.data)
		_poll_timer.start()
	return r

func _apply_result(r: Dictionary) -> Dictionary:
	if r.ok and in_lobby():
		_set_lobby(r.data)
	return r

func _set_lobby(lobby: Dictionary) -> void:
	if in_lobby() and lobby.code != data.code:
		return
	if in_lobby() and int(lobby.version) < int(data.version):
		return                                  # respuesta atrasada
	var is_new := not in_lobby() or int(lobby.version) != int(data.version)
	data = lobby
	if is_new:
		changed.emit(data)
	if data.status == STATUS_STARTED and not _start_emitted:
		_start_emitted = true
		_poll_timer.stop()
		started.emit(data)

func _poll() -> void:
	if _polling or not in_lobby() or data.status != STATUS_WAITING:
		return
	_polling = true
	var code: String = data.code
	var r := await _call(HTTPClient.METHOD_GET, "/api/lobbies/" + code)
	_polling = false
	if not in_lobby() or data.code != code:
		return
	if r.ok:
		_set_lobby(r.data)
	elif r.status == 403:
		_forced_out(KICKED_NOTICE, "kicked")
	elif r.status == 404:
		_forced_out(CLOSED_NOTICE, "closed")

func _forced_out(text: String, reason: String) -> void:
	notice = text
	_clear()
	left.emit(reason)

func _clear() -> void:
	_poll_timer.stop()
	data = {}
	_start_emitted = false
