class_name PlayerCardGame
extends Control
## Tarjeta de un jugador en el HUD: color del asiento, resalte del que tiene el
## turno y, solo en ese, los dados de la tirada.

const DIM := Color(1, 1, 1, 0.6)
## Bloque de ladrillo detras de cada tarjeta: el mismo material que el panel de los menus y los botones,
## teñido con el color del asiento (mas vivo en quien tiene el turno).
const BRICK := preload("res://service/assets/ui/theme/panel_brick.png")
const BLOCK_PAD := Vector2(3.0, 3.0)
## Un avatar por asiento (los mismos de la sala): calavera con cuernos del color del asiento.
const AVATARS: Array[Texture2D] = [
	preload("res://service/assets/ui/avatars/avatar_red.png"),
	preload("res://service/assets/ui/avatars/avatar_blue.png"),
	preload("res://service/assets/ui/avatars/avatar_green.png"),
	preload("res://service/assets/ui/avatars/avatar_gold.png"),
]

@onready var _circle: Control = %PlayerCard
@onready var _avatar: TextureRect = %Avatar
@onready var _dice_panel: Control = %Dices
@onready var _dices = %DiceRoll
@onready var _crown_label: Label = %CrownLabel
@onready var _effect_label: Label = %EffectLabel

var _active := false
var _pulse := 0.0
var _seat_color := Color.WHITE
var _block: StyleBoxTexture
var _retire_ms := -1.0                 # retireAt (ms Unix) si el jugador está desconectado
var _conn_label: Label

func _ready() -> void:
	set_process(false)
	if _effect_label != null:                  # etiqueta de «desconectado»: copia de la de efectos
		_conn_label = _effect_label.duplicate() as Label
		_conn_label.unique_name_in_owner = false
		_conn_label.visible = false
		_conn_label.clip_text = false
		_conn_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_conn_label.self_modulate = Color(1.0, 0.5, 0.45)
		_effect_label.get_parent().add_child(_conn_label)
	_block = StyleBoxTexture.new()
	_block.texture = BRICK
	_block.texture_margin_left = 6.0
	_block.texture_margin_right = 6.0
	_block.texture_margin_top = 6.0
	_block.texture_margin_bottom = 6.0
	_block.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_block.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE

func setup(seat: int, tooltip := "") -> void:
	visible = true
	_seat_color = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	_crown_label.self_modulate = _seat_color.lerp(Color.WHITE, 0.45)
	queue_redraw()
	if _circle != null:
		# solo el aro toma el color del asiento: self_modulate no se hereda, el avatar se ve con sus colores
		_circle.self_modulate = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
		_circle.tooltip_text = tooltip
		_circle.mouse_filter = Control.MOUSE_FILTER_STOP
	if _avatar != null:
		_avatar.texture = AVATARS[posmod(seat, AVATARS.size())]
	set_active(false)
	if _dice_panel != null:
		_dice_panel.visible = true

## Solo atenúa a quien no tiene el turno. Los dados de la tarjeta se quedan
## siempre visibles con el valor de la última tirada de ese jugador.
func set_active(active: bool) -> void:
	_active = active
	modulate = Color.WHITE if active else DIM
	set_process(active or _retire_ms > 0.0)
	queue_redraw()

## Marca al jugador como desconectado con cuenta atrás hasta `retire_ms` (ms Unix); -1 lo quita.
func set_disconnected(retire_ms: float) -> void:
	_retire_ms = retire_ms
	set_process(_active or _retire_ms > 0.0)
	_update_conn_label()

func _update_conn_label() -> void:
	if _conn_label == null:
		return
	_conn_label.visible = _retire_ms > 0.0
	if _retire_ms > 0.0:
		var secs := maxi(0, ceili((_retire_ms - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
		_conn_label.text = "SIN CONEXION %ds" % secs
		_conn_label.tooltip_text = "Desconectado: se retira de la partida si no vuelve a tiempo"

func _process(delta: float) -> void:
	_pulse += delta
	if _retire_ms > 0.0:
		_update_conn_label()
	if _active:
		queue_redraw()

## Bloque de ladrillo de la tarjeta y, en quien tiene el turno, un aro pulsante del color del asiento.
func _draw() -> void:
	if _block != null:
		var tint := Color(0.78, 0.78, 0.84).lerp(_seat_color, 0.42 if _active else 0.22)
		_block.modulate_color = tint.lightened(0.12) if _active else tint
		_block.draw(get_canvas_item(), Rect2(-BLOCK_PAD, Vector2(size.x, size.y) + BLOCK_PAD * 2.0))
		# filete del color del asiento en el borde de arriba del bloque
		draw_rect(Rect2(-BLOCK_PAD.x + 2.0, -BLOCK_PAD.y + 2.0, size.x + BLOCK_PAD.x * 2.0 - 4.0, 2.0),
				Color(_seat_color.r, _seat_color.g, _seat_color.b, 0.9 if _active else 0.5))
	if not _active or _circle == null:
		return
	var center := _circle.get_global_rect().get_center() - get_global_rect().position
	var radius := _circle.size.x * 0.5
	var k := 0.5 + 0.5 * sin(_pulse * 4.0)
	var c := _seat_color.lerp(Color.WHITE, 0.35)
	draw_arc(center, radius + 4.0, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.20 + 0.15 * k), 3.0)
	draw_arc(center, radius + 1.5, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.75 + 0.25 * k), 1.5)

## Últimos dados de este jugador (vacío = aún no ha tirado).
func show_dice(values: Array, consumed: Array) -> void:
	if _dices != null and _dices.has_method("show_values"):
		_dices.show_values(values, consumed)

## Anima la tirada (evento DICE_ROLLED) en los dados de esta tarjeta.
func play_roll(values: Array) -> void:
	if _dices != null and _dices.has_method("play_roll"):
		_dices.play_roll(values)

## Fichas coronadas de este jugador, de 4 (US-015).
func set_crowned(count: int, total := 4) -> void:
	_crown_label.text = "%d/%d" % [count, total]

## Efectos activos del jugador (`players[].effects`, p. ej. turno perdido): etiqueta corta
## bajo la tarjeta y detalle en el tooltip; sin efectos, la etiqueta se oculta.
func set_effects(effects: Array) -> void:
	_effect_label.visible = not effects.is_empty()
	if effects.is_empty():
		return
	_effect_label.text = GameText.effects_tags(effects)
	_effect_label.tooltip_text = GameText.effects_tooltip(effects)

func hide_card() -> void:
	visible = false
