class_name RollHold
extends RefCounted
## Pausa visual mientras ruedan los dados (propios, de otro jugador o de un bot).
## Mientras esta activa, el tablero y el HUD no muestran movimientos, capturas ni
## cambios de turno: se guardan y se aplican al terminar. El servidor sigue su
## ritmo; solo se retrasa lo que se dibuja.
##
## El Presenter (autoload) decide cuando empieza cada tirada (una a una y en orden): aqui solo se
## marca la pausa mientras ruedan los dados.

## Lo que ruedan los dados (DiceOverlay) y lo que se queda el resultado a la vista.
const DICE_TIME := 1.3
const SETTLE := 0.6
const DURATION := DICE_TIME + SETTLE

static var _until_ms := 0

## Sin efecto: antes la pausa arrancaba al ver un estado nuevo; ahora la inicia el Presenter con begin().
static func observe(_state: Dictionary) -> void:
	pass

## Arranca la pausa de unos dados: SIEMPRE desde cero. Lo llama el Presenter justo antes de mostrar cada
## tirada; si una tirada sigue a otra (dobles) la pausa no puede heredar el final de la anterior.
static func begin() -> void:
	_until_ms = Time.get_ticks_msec() + int(DURATION * 1000.0)

## Compatibilidad (la UI lo llama al ver DICE_ROLLED): devuelve 0 y solo asegura la pausa si no hay una activa.
static func start(_immediate := false) -> float:
	if not active():
		begin()
	return 0.0

static func active() -> bool:
	return Time.get_ticks_msec() < _until_ms

static func clear() -> void:
	_until_ms = 0
