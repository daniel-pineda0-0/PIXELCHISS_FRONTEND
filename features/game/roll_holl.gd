class_name RollHold
extends RefCounted
## Pausa visual mientras ruedan los dados (propios, de otro jugador o de un bot).
## Mientras está activa, el tablero y el HUD no muestran movimientos, capturas ni
## cambios de turno: se guardan y se aplican al terminar. El servidor sigue su
## ritmo; solo se retrasa lo que se dibuja. Un bot que juega al instante no pisa
## la animación de los dados.

## Animación de los dados (Dices.ROLL_TIME = 0.7 s) + un instante para ver el resultado.
const DURATION := 0.95

static var _until_ms := 0
static var _observed := false
static var _last_roll_id := ""

## Con las reglas v4-100 el estado de una tirada ya trae las fichas liberadas (y sus
## capturas) ANTES de que llegue el evento DICE_ROLLED. Para que no aparezcan mientras
## ruedan los dados, la pausa también arranca al ver una `turn.rollId` nueva en el estado.
## Idempotente: puede llamarse desde varios sitios con el mismo estado. El primer estado
## que se ve (entrar a una partida en curso) no pausa.
static func observe(state: Dictionary) -> void:
	var turn: Variant = state.get("turn")
	var roll_id := ""
	if turn is Dictionary and turn.get("rollId") != null:
		roll_id = str(turn.get("rollId"))
	if not _observed:
		_observed = true
		_last_roll_id = roll_id
		return
	if roll_id != "" and roll_id != _last_roll_id:
		_last_roll_id = roll_id
		start()

static func start() -> void:
	_until_ms = Time.get_ticks_msec() + int(DURATION * 1000.0)

static func active() -> bool:
	return Time.get_ticks_msec() < _until_ms

static func clear() -> void:
	_until_ms = 0
	_observed = false
	_last_roll_id = ""
