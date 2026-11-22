class_name TurnBanner
extends PanelContainer
## Panel del turno (arriba al centro). game_ui solo le pasa el texto.

const URGENT_COLOR := Color(1.0, 0.45, 0.4)

@onready var _label: Label = %Label

func set_message(text: String, urgent := false) -> void:
	_label.text = text
	_label.label_settings.font_color = URGENT_COLOR if urgent else Color.WHITE
