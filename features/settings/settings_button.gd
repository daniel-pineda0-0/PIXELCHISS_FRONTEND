extends CanvasLayer
## Boton de ajustes (la tuerca) en la esquina superior derecha. Se instancia en
## cualquier pantalla (login, menu, sala...) y abre settings_screen encima sin
## cambiar de escena, asi no se pierde la sala ni el polling.

const SETTINGS_SCENE := preload("res://features/settings/settings_screen.tscn")

@onready var open_button: TextureButton = %OpenButton

var _screen: Control = null

func _ready() -> void:
	open_button.pressed.connect(_open)

func _open() -> void:
	if is_instance_valid(_screen):
		return
	_screen = SETTINGS_SCENE.instantiate()
	add_child(_screen)
