class_name ResultScreen
extends Control
## Pantalla de victoria (US-014). game_ui decide cuándo y con qué datos; aquí solo se muestra.
## Misma estética que la ventana de opciones (settings_screen.tscn): tema pixel_theme, velo oscuro,
## panel centrado, título de 16 px, separadores y botón estándar.

signal back_pressed

@onready var _panel: Control = %Panel
@onready var _title: Label = %Title
@onready var _swatch: ColorRect = %Swatch
@onready var _detail: Label = %Detail
@onready var _crowned: Label = %Crowned
@onready var _back: Button = %BackButton

func _ready() -> void:
	visible = false
	_back.pressed.connect(func(): back_pressed.emit())

func show_result(title: String, detail: String, swatch: Color, crowned_text := "") -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", swatch.lerp(Color.WHITE, 0.35))
	_detail.text = detail
	_swatch.color = swatch
	_crowned.text = crowned_text
	_crowned.visible = crowned_text != ""
	visible = true
	# entrada: el panel crece un poco desde el centro y el velo se aclara
	await get_tree().process_frame
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.85, 0.85)
	modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
