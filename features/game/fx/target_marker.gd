class_name TargetMarker
extends Node2D
## Destino de un movimiento legal (o de una carta): círculo que late + número del dado.
## BoardView solo rellena los datos; el dibujo vive en TargetMarker.tscn.

var move: Dictionary = {}           # elemento de legalMoves (o de card.choices si is_card)
var is_card := false                # destino de una carta (CARD_TARGET) y no de un movimiento
var chunk := 0                      # chunk y celda donde se coloca
var cell := Vector2i.ZERO

var label := "":                    # "4", "2" o "4+2" (suma de los dados)
	set(value):
		label = value
		_apply()
var color := Color.WHITE:
	set(value):
		color = value
		_apply()

var _time := 0.0

@onready var _disc: Sprite2D = %Disc
@onready var _ring: Sprite2D = %Ring
@onready var _label: Label = %Label

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_node_ready():           # BoardView asigna antes de add_child: se aplica en _ready
		return
	_disc.modulate = Color(color, 0.35)
	_ring.modulate = Color(color, 0.95)
	_label.text = label
	_label.label_settings.font_size = 8 if label.length() <= 2 else 6

func _process(delta: float) -> void:
	_time += delta
	var s := (11.0 + sin(_time * 6.0) * 1.2) / 32.0       # el radio late como antes
	_disc.scale = Vector2(s, s)
	_ring.scale = Vector2(s, s)
