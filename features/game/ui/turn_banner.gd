class_name TurnBanner
extends PanelContainer
## Panel del turno (arriba al centro). game_ui solo le pasa el texto.
## Tu turno se ve distinto al de un bot o de otro jugador: la placa late en dorado con una flecha;
## cuando juega otro, el texto toma el color de su asiento.

const URGENT_COLOR := Color(1.0, 0.45, 0.4)
const MINE_COLOR := Color(1.0, 0.9, 0.35)

@onready var _label: Label = %Label

var _mine := false
var _t := 0.0

func set_message(text: String, urgent := false, mine := false, tint := Color.WHITE) -> void:
	_mine = mine
	_label.text = ("▶ " + text) if mine else text
	var color := tint.lerp(Color.WHITE, 0.35)
	if mine:
		color = MINE_COLOR
	if urgent:
		color = URGENT_COLOR
	_label.label_settings.font_color = color
	if not mine:
		modulate = Color.WHITE

func _process(delta: float) -> void:
	if _mine:
		_t += delta
		var k := 0.5 + 0.5 * sin(_t * 5.0)
		modulate = Color(1.0, 0.95 + 0.05 * k, 0.75 + 0.25 * k)
