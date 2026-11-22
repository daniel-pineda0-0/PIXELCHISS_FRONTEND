class_name ResultScreen
extends Control
## Pantalla de victoria (US-014). game_ui decide cuándo y con qué datos; aquí solo se muestra.

signal back_pressed

@onready var _title: Label = %Title
@onready var _swatch: ColorRect = %Swatch
@onready var _detail: Label = %Detail
@onready var _crowned: Label = %Crowned
@onready var _back: TextureButton = %BackButton

func _ready() -> void:
	visible = false
	_back.set_text("Menú")
	_back.pressed.connect(func(): back_pressed.emit())

func show_result(title: String, detail: String, swatch: Color, crowned_text := "") -> void:
	_title.text = title
	_detail.text = detail
	_swatch.color = swatch
	_crowned.text = crowned_text
	_crowned.visible = crowned_text != ""
	visible = true
