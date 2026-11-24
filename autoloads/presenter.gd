extends Node
## Presentador de la partida: se pone entre GameNet y lo que se dibuja (tablero y HUD).
## El servidor manda cada cambio (version) en cuanto ocurre y los bots juegan muy rapido: tirada, movimiento y
## fin de turno pueden llegar con medio segundo de diferencia. Si se dibujara todo al recibirlo, los turnos
## "avanzarian" mientras aun ruedan los dados o camina una ficha.
## Aqui cada version se encola y se REPRODUCE EN ORDEN, una a una, esperando lo que tarda en verse (dados,
## ficha caminando). Banner, tarjetas, dados y tablero muestran siempre la misma version: `shown`.
## Tus acciones (lanzar, mover, pasar) solo se habilitan cuando la cola esta vacia (idle()). Si el servidor
## se adelanta mucho, la cola acelera sola para no quedar atras (y se salta lo intermedio si es enorme).
##   state_shown(state)            ->  lo que hay que dibujar ahora
##   events_shown(events, version) ->  sus eventos
##   idle_changed(is_idle)         ->  la cola se vacio / empezo a reproducir

signal state_shown(state: Dictionary)
signal events_shown(events: Array, version: int)
signal idle_changed(is_idle: bool)

const MOVE_WAIT := 1.1          # segundos para ver caminar una ficha antes de la siguiente jugada
const SHORT_WAIT := 0.35        # cambio de turno u otros avisos
## Maximo de segundos de animacion pendiente. Los bots juegan casi sin pausa (tiradas, dobles y movimientos
## llegan juntos) y mostrarlo todo tardaria mas de lo que dura tu turno. Si lo pendiente pasa de este margen,
## las versiones mas viejas se aplican AL INSTANTE (sin dados ni caminata) y solo se animan las ultimas.
const LAG_BUDGET := 6.0
## El servidor ya espacia las jugadas de los bots (BotPacing: tirada 2.1 s, movimiento 1.3 s, fin de turno 0.5 s) y esos
## tiempos son un poco MAYORES que los de aqui (dados 1.9 s, movimiento MOVE_WAIT), asi que la cola casi no crece y
## LAG_BUDGET queda como red de seguridad. Si cambias los de alla, ajusta DICE_TIME/SETTLE (roll_holl.gd) y MOVE_WAIT.
## Ademas, una jugada no se muestra hasta que terminen las fichas que aun se mueven (por ejemplo la bajada por la
## escalera al corredor, que dura mas que MOVE_WAIT). Tope por jugada, por si algo se quedara colgado:
const MAX_ANIM_WAIT_MS := 7000
## Tu propia jugada llega primero como ACTION_ACK (estado SIN eventos) y los eventos vienen despues en el
## GAME_UPDATED. Una version sin eventos espera este margen a que lleguen antes de reproducirse.
const EVENT_GRACE_MS := 150

var shown: Dictionary = {}      # ultimo estado ya mostrado ({} = ninguno)
var _queue: Array = []          # {version, state, events}
var _wait := 0.0
var _game_id := ""
var _was_idle := true
var _played_ms := 0
## Lo registra el tablero (BoardView.animation_remaining): segundos que faltan para que terminen las fichas en movimiento.
var busy_probe: Callable = Callable()

func _ready() -> void:
	GameNet.state_changed.connect(_on_state)
	GameNet.events_received.connect(_on_events)
	GameNet.joined.connect(_on_joined)

## Estado que se esta MOSTRANDO (si aun no hay ninguno, el vivo del servidor).
func view() -> Dictionary:
	return shown if not shown.is_empty() else GameNet.state

## Sin nada que reproducir ni esperando: lo que se ve es lo ultimo que dijo el servidor.
func idle() -> bool:
	return _queue.is_empty() and _wait <= 0.0 and not _anim_busy()

## Hay fichas del tablero todavia caminando o bajando por la escalera (con tope, ver MAX_ANIM_WAIT_MS).
func _anim_busy() -> bool:
	if not busy_probe.is_valid():
		return false
	if Time.get_ticks_msec() - _played_ms > MAX_ANIM_WAIT_MS:
		return false
	return float(busy_probe.call()) > 0.02

func _reset_if_new_game() -> void:
	if GameNet.game_id != _game_id:
		_game_id = GameNet.game_id
		shown = {}
		_queue.clear()
		_wait = 0.0

func _on_state(state: Dictionary) -> void:
	_reset_if_new_game()
	var version := int(state.get("version", -1))
	if not _queue.is_empty() and version <= int(_queue.back().version):
		return
	if _queue.is_empty() and not shown.is_empty() and version <= int(shown.get("version", -1)):
		return
	var prev: Dictionary = _queue.back().state if not _queue.is_empty() else shown
	_queue.append({"version": version, "state": state, "events": [], "t": Time.get_ticks_msec(),
			"cost": _cost(state, prev)})
	_notify_idle()

func _on_events(events: Array, version: int) -> void:
	for entry in _queue:
		if int(entry.version) == version:
			(entry.events as Array).append_array(events)
			return
	if not shown.is_empty() and int(shown.get("version", -1)) == version:
		events_shown.emit(events, version)       # el estado ya salio: los eventos van detras

## Reconexion: se muestra de golpe lo ultimo (no se reproduce lo que paso mientras no estabas).
func _on_joined() -> void:
	_reset_if_new_game()
	_queue.clear()
	_wait = 0.0
	if not GameNet.state.is_empty():
		_play({"version": int(GameNet.state.get("version", 0)), "state": GameNet.state, "events": []}, false)
	_notify_idle()

func _process(delta: float) -> void:
	_wait = maxf(0.0, _wait - delta)
	if _wait <= 0.0 and not _anim_busy():
		_trim_backlog()                                     # solo entre animaciones: nunca con unos dados rodando
		while _wait <= 0.0 and not _queue.is_empty():
			if not _ready_check(_queue[0]):
				break
			_play(_queue.pop_front(), not shown.is_empty())     # el primer estado (entrar a la partida) no espera
	_notify_idle()

## Si hay mas animacion pendiente de la que cabe en LAG_BUDGET, las versiones mas viejas se muestran al
## instante (sin dados ni caminata, sin sus eventos) hasta que lo pendiente quepa. Siempre queda al menos una.
func _trim_backlog() -> void:
	var backlog := 0.0
	for entry in _queue:
		backlog += float(entry.get("cost", 0.0))
	while backlog > LAG_BUDGET and _queue.size() > 1:
		var old: Dictionary = _queue.pop_front()
		backlog -= float(old.get("cost", 0.0))
		old["events"] = []
		if OS.is_debug_build():
			print("[presenter] %6d ms salta v%d (atraso %.1fs)" % [Time.get_ticks_msec() % 1000000, int(old.version), backlog])
		_play(old, false)

## Lo que tardara en verse este cambio respecto al anterior, calculado solo con el estado (los eventos
## pueden llegar despues): tirada nueva, fichas distintas o cambio de turno.
func _cost(state: Dictionary, prev: Dictionary) -> float:
	if prev.is_empty():
		return 0.0
	var c := 0.0
	var rid := _roll_id(state)
	if rid != "" and rid != _roll_id(prev):
		c += RollHold.DURATION
	if str(state.get("pieces", [])) != str(prev.get("pieces", [])):
		c += MOVE_WAIT
	elif _turn_player(state) != _turn_player(prev):
		c += SHORT_WAIT
	return c

## La version esta lista para mostrarse: ya trae sus eventos, o ya espero lo razonable por ellos.
func _ready_check(entry: Dictionary) -> bool:
	if shown.is_empty() or not (entry.events as Array).is_empty():
		return true
	var rid := _roll_id(entry.state)
	if rid != "" and rid != _roll_id(shown):
		return true                                 # una tirada nueva se ve en el estado: los dados salen ya
	return Time.get_ticks_msec() - int(entry.get("t", 0)) >= EVENT_GRACE_MS

func _notify_idle() -> void:
	var now_idle := idle()
	if now_idle != _was_idle:
		_was_idle = now_idle
		idle_changed.emit(now_idle)

func _play(entry: Dictionary, wait_after: bool) -> void:
	var state: Dictionary = entry.state
	var events: Array = entry.events
	var new_roll := _roll_id(state) != "" and _roll_id(state) != _roll_id(shown)
	var rolled := _has(events, "DICE_ROLLED") or new_roll
	var moved := _has(events, "PIECE_MOVED") or _has(events, "PIECE_CAPTURED") or _has(events, "PIECE_RELEASED") \
			or _has(events, "PIECE_BLOWN") or _has(events, "CARD_PIECE_RETURNED") or _has(events, "PIECE_CROWNED")
	if not shown.is_empty():
		if str(state.get("pieces", [])) != str(shown.get("pieces", [])):
			moved = true                            # tambien se nota en el estado, aunque los eventos no hayan llegado
	var turn_changed := _has(events, "TURN_CHANGED") or _turn_player(state) != _turn_player(shown)
	if OS.is_debug_build():
		print("[presenter] %6d ms v%d rolled=%s moved=%s turn=%s cola=%d" % [Time.get_ticks_msec() % 1000000, int(entry.version), rolled, moved,
				_turn_player(state), _queue.size()])
	if rolled and wait_after:
		RollHold.begin()                            # el tablero y el HUD retienen sus cambios mientras ruedan los dados
	shown = state
	_played_ms = Time.get_ticks_msec()
	state_shown.emit(state)
	if not events.is_empty():
		events_shown.emit(events, int(entry.version))
	if not wait_after:
		return
	var t := 0.0
	if rolled:
		t += RollHold.DURATION
	if moved:
		t += MOVE_WAIT
	elif (turn_changed or not events.is_empty()) and not rolled:
		t += SHORT_WAIT
	_wait = t

static func _has(events: Array, type: String) -> bool:
	for e in events:
		if str(e.get("type", "")) == type:
			return true
	return false

static func _turn_player(state: Dictionary) -> String:
	var turn: Variant = state.get("turn")
	return str(turn.get("playerId", "")) if turn is Dictionary else ""

static func _roll_id(state: Dictionary) -> String:
	var turn: Variant = state.get("turn")
	if turn is Dictionary and turn.get("rollId") != null:
		return str(turn.get("rollId"))
	return ""
