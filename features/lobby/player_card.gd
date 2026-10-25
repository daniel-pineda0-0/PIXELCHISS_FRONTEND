extends Control
## Tarjeta de un participante de la sala (US-016). Solo pinta; las acciones
## se avisan por señal y las resuelve la sala.
##
## Para el anfitrión la tarjeta es clicable: sobre un jugador o un bot muestra
## el botón Kick (US-017, US-005); sobre un cupo libre añade un bot.

signal kick_requested(user_id: String)
signal remove_bot_requested(bot_id: String)
signal add_bot_requested

enum Action { NONE, ADD_BOT, REMOVE_BOT, KICK }

const KICK_BUTTON_SCENE := preload("res://features/lobby/kick_button.tscn")

# Rojo, azul, verde, amarillo: mismo orden de asientos que usa el Game.
# (el círculo es gris, por eso los tonos van más claros)
const SEAT_COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.45),
	Color(0.5, 0.65, 1.0),
	Color(0.5, 0.95, 0.5),
	Color(1.0, 1.0, 0.5),
]
const EMPTY_COLOR := Color(1, 1, 1, 0.3)
const READY_COLOR := Color(0.6, 1.0, 0.6)
const WAITING_COLOR := Color(0.75, 0.75, 0.75)
const KICK_TIME := 3.0
const NAME_MAX := 12

@onready var name_label:Label=%NameLabel
@onready var crown:TextureRect=%Crown
@onready var color_circle:TextureRect=%ColorCircle
@onready var avatar:TextureRect=%Avatar
@onready var player_button: Button = $PlayerButton

var _action := Action.NONE
var _target_id := ""
var _kick_button: Button
var _kick_timer := Timer.new()

func _ready() -> void:
	_kick_button = KICK_BUTTON_SCENE.instantiate()
	_kick_button.visible = false
	_kick_button.pressed.connect(_on_kick_button_pressed)
	add_child(_kick_button)                 # al final: queda por encima de PlayerButton
	_kick_timer.one_shot = true
	_kick_timer.wait_time = KICK_TIME
	_kick_timer.timeout.connect(_hide_kick)
	add_child(_kick_timer)
	show_empty(false)

func show_player(player: Dictionary, seat: int, can_manage: bool, is_me: bool) -> void:
	var is_bot: bool = player.is_bot
	var is_host: bool = player.role == "HOST"
	name_label.text = _short_name(player.display_name, is_me)
	crown.self_modulate = Color.WHITE if is_host else Color.TRANSPARENT
	color_circle.self_modulate = SEAT_COLORS[seat]
	# El estado se lee en el color del nombre: blanco anfitrión, verde listo, gris espera.
	if is_host:
		name_label.self_modulate = Color.WHITE
	elif not is_bot and player.ready:
		name_label.self_modulate = READY_COLOR
	else:
		name_label.self_modulate = WAITING_COLOR
	if can_manage and not is_me:
		_set_action(Action.REMOVE_BOT if is_bot else Action.KICK, player.user_id)
	else:
		_set_action(Action.NONE)

## Cupo libre. El anfitrión puede llenarlo con un bot (US-005).
func show_empty(can_add_bot: bool) -> void:
	name_label.text = "+ Bot" if can_add_bot else "Esperando..."
	name_label.self_modulate = Color.WHITE if can_add_bot else WAITING_COLOR
	crown.self_modulate = Color.TRANSPARENT
	color_circle.self_modulate = EMPTY_COLOR
	_set_action(Action.ADD_BOT if can_add_bot else Action.NONE)

func _short_name(display_name: String, is_me: bool) -> String:
	if is_me:
		return display_name.left(NAME_MAX - 5) + " (tu)"
	return display_name.left(NAME_MAX)

func _set_action(action: Action, target_id := "") -> void:
	if action != _action or target_id != _target_id:
		_hide_kick()
	_action = action
	_target_id = target_id
	player_button.disabled = action == Action.NONE
	player_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if action == Action.NONE else Control.MOUSE_FILTER_STOP

func _show_kick() -> void:
	_kick_button.text = "Kick" if _action == Action.KICK else "Quitar"
	_kick_button.visible = true
	_kick_button.reset_size()
	_kick_button.position = Vector2((size.x - _kick_button.size.x) / 2.0, size.y - _kick_button.size.y)
	_kick_timer.start()

func _hide_kick() -> void:
	_kick_timer.stop()
	if _kick_button:
		_kick_button.visible = false

func _on_player_button_pressed() -> void:
	match _action:
		Action.ADD_BOT:
			add_bot_requested.emit()
		Action.KICK, Action.REMOVE_BOT:
			# La expulsión es definitiva: primero se muestra Kick y ahí se confirma.
			if _kick_button.visible:
				_hide_kick()
			else:
				_show_kick()

func _on_kick_button_pressed() -> void:
	_hide_kick()
	if _action == Action.KICK:
		kick_requested.emit(_target_id)
	elif _action == Action.REMOVE_BOT:
		remove_bot_requested.emit(_target_id)
