extends Control
## Ventana de ajustes (superpuesta). Solo pinta los controles y llama a
## Settings; "Cerrar sesion" limpia Lobby, Session y GameState y vuelve al
## login pasando por la pantalla de carga.

signal closed

const CONFIRM_TIME := 3.0
const LOGOUT_TEXT := "Cerrar sesion"
const LOGOUT_CONFIRM_TEXT := "Seguro?"

@onready var master_slider: HSlider = %MasterSlider
@onready var master_value: Label = %MasterValue
@onready var music_slider: HSlider = %MusicSlider
@onready var music_value: Label = %MusicValue
@onready var sfx_slider: HSlider = %SfxSlider
@onready var sfx_value: Label = %SfxValue
@onready var mute_check: CheckBox = %MuteCheck
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var vsync_check: CheckBox = %VsyncCheck
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var player_label: Label = %PlayerLabel
@onready var logout_button: Button = %LogoutButton
@onready var close_button = %CloseButton          # JoinButton (tiene set_text)

var _resolutions: Array[Vector2i] = []
var _confirming := false
var _logging_out := false

func _ready() -> void:
	close_button.set_text("Back")
	close_button.pressed.connect(close)

	_bind_slider(master_slider, master_value, Settings.BUS_MASTER)
	_bind_slider(music_slider, music_value, Settings.BUS_MUSIC)
	_bind_slider(sfx_slider, sfx_value, Settings.BUS_SFX)

	mute_check.set_pressed_no_signal(Settings.muted)
	mute_check.toggled.connect(func(on: bool): Settings.set_muted(on); Settings.save())

	fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.set_pressed_no_signal(Settings.vsync)
	vsync_check.toggled.connect(func(on: bool): Settings.set_vsync(on); Settings.save())

	_build_resolutions()
	resolution_option.disabled = Settings.fullscreen
	resolution_option.item_selected.connect(_on_resolution_selected)

	var player_name: String = str(Session.profile.get("displayName", "-"))
	player_label.text = "Jugador: " + player_name
	logout_button.text = LOGOUT_TEXT
	logout_button.pressed.connect(_on_logout_pressed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _logging_out:
		get_viewport().set_input_as_handled()
		close()

## Guarda y vuelve a la pantalla anterior.
func close() -> void:
	Settings.save()
	closed.emit()
	queue_free()

# --- Audio ---

func _bind_slider(slider: HSlider, value_label: Label, bus: String) -> void:
	slider.set_value_no_signal(Settings.volumes[bus])
	value_label.text = _percent(Settings.volumes[bus])
	slider.value_changed.connect(func(value: float):
		Settings.set_volume(bus, value)
		value_label.text = _percent(value))
	slider.drag_ended.connect(func(_changed: bool): Settings.save())

func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)

# --- Pantalla ---

func _build_resolutions() -> void:
	_resolutions = Settings.available_resolutions()
	resolution_option.clear()
	for res in _resolutions:
		resolution_option.add_item("%dx%d" % [res.x, res.y])
	var current := _resolutions.find(Settings.resolution)
	resolution_option.select(maxi(current, 0))

func _on_fullscreen_toggled(on: bool) -> void:
	Settings.set_fullscreen(on)
	Settings.save()
	resolution_option.disabled = on

func _on_resolution_selected(index: int) -> void:
	Settings.set_resolution(_resolutions[index])
	Settings.save()

# --- Cuenta ---

## La primera pulsacion pide confirmar; la segunda cierra la sesion.
func _on_logout_pressed() -> void:
	if _logging_out:
		return
	if not _confirming:
		_confirming = true
		logout_button.text = LOGOUT_CONFIRM_TEXT
		get_tree().create_timer(CONFIRM_TIME).timeout.connect(_reset_logout_button)
		return
	_logging_out = true
	logout_button.disabled = true
	close_button.disabled = true
	Settings.save()
	await Lobby.leave()          # sale de la sala si estaba en una
	await Session.logout()
	Lobby.clear()
	GameState.reset()
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

func _reset_logout_button() -> void:
	if _logging_out:
		return
	_confirming = false
	logout_button.text = LOGOUT_TEXT
