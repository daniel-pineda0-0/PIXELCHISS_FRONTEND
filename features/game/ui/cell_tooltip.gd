class_name CellTooltip
extends PanelContainer
## Cuadro de información de una casilla del minimapa. Sigue al ratón dentro de la pantalla.

@onready var _label: Label = %Label

var _text := ""

func show_info(text: String, mouse: Vector2) -> void:
	if text != _text:
		_text = text
		_label.text = text
		reset_size()
	visible = true
	var limit := get_viewport().get_visible_rect().size - size
	position = Vector2(minf(mouse.x + 12.0, limit.x), minf(mouse.y + 12.0, limit.y))

func hide_info() -> void:
	visible = false
