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

static func start() -> void:
	_until_ms = Time.get_ticks_msec() + int(DURATION * 1000.0)

static func active() -> bool:
	return Time.get_ticks_msec() < _until_ms

static func clear() -> void:
	_until_ms = 0
