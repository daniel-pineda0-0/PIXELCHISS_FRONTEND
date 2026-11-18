extends Control
## Tarjeta de un jugador en el HUD: color del asiento, resalte del que tiene el
## turno y, solo en ese, los dados de la tirada.

const DIM := Color(1, 1, 1, 0.55)

@onready var _circle := get_node_or_null("VBoxContainer/PlayerCard") as Control
@onready var _dice_panel := get_node_or_null("VBoxContainer/Dices") as Control
@onready var _dices := get_node_or_null("VBoxContainer/Dices/AspectRatioContainer/dices")

func setup(seat: int, tooltip := "") -> void:
	visible = true
	if _circle != null:
		_circle.modulate = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
		_circle.tooltip_text = tooltip
		_circle.mouse_filter = Control.MOUSE_FILTER_STOP
	set_active(false)

func set_active(active: bool) -> void:
	modulate = Color.WHITE if active else DIM
	if _dice_panel != null:
		_dice_panel.visible = active

## Dados de la tirada (solo se llama para el jugador activo).
func show_dice(values: Array, consumed: Array) -> void:
	if _dices != null and _dices.has_method("show_values"):
		_dices.show_values(values, consumed)

func hide_card() -> void:
	visible = false
