class_name PieceHalo
extends Node2D
## Aro a los pies de una ficha. Cada estado es un Sprite2D de PieceHalo.tscn:
##  Protected = azul (seguro o corredor) | Crowned = dorado | Movable = amarillo que late |
##  Selected = blanco (ficha elegida).

var safe_cell := false:             # protegida (zona segura o corredor)
	set(value):
		safe_cell = value
		_refresh()
var movable := false:               # se puede mover ahora
	set(value):
		movable = value
		_refresh()
var crowned := false:               # ya coronada (US-015)
	set(value):
		crowned = value
		_refresh()
var selected := false:              # es la ficha elegida
	set(value):
		selected = value
		_refresh()

var _time := 0.0

@onready var _protected: Sprite2D = %Protected
@onready var _crowned: Sprite2D = %Crowned
@onready var _movable: Sprite2D = %Movable
@onready var _selected: Sprite2D = %Selected

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	_crowned.visible = crowned
	_protected.visible = safe_cell and not crowned     # la corona manda sobre el seguro
	_movable.visible = movable
	_selected.visible = selected
	set_process(movable)

func _process(delta: float) -> void:
	_time += delta
	_movable.modulate.a = 0.55 + 0.45 * sin(_time * 5.0)
