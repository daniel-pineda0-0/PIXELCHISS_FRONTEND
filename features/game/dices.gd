extends Node2D
## Dos dados. show_values() los deja fijos (el ya usado, atenuado); play_roll() los
## agita un momento y los deja en los valores que mandó el servidor.

const ROLL_TIME := 0.7
const FRAME_TIME := 0.07
const USED_TINT := Color(0.45, 0.45, 0.45)

var _sprites: Array[AnimatedSprite2D] = []
var _values: Array = []
var _consumed: Array = []
var _rolling := 0.0
var _tick := 0.0

func _ready() -> void:
	for node_name in ["Dice", "Dice2"]:
		var sprite := get_node_or_null(node_name) as AnimatedSprite2D
		if sprite != null:
			sprite.stop()
			_sprites.append(sprite)
	_apply()

## Valores 1-6 de los dos dados; `consumed[i]` atenúa el que ya se usó.
func show_values(values: Array, consumed: Array = []) -> void:
	_values = values
	_consumed = consumed
	if _rolling <= 0.0:
		_apply()

func clear() -> void:
	show_values([])

func play_roll(values: Array) -> void:
	_values = values
	_consumed = []
	_rolling = ROLL_TIME
	_tick = 0.0

func _process(delta: float) -> void:
	if _rolling <= 0.0:
		return
	_rolling -= delta
	_tick -= delta
	if _rolling <= 0.0:
		_apply()
		return
	if _tick <= 0.0:
		_tick = FRAME_TIME
		for sprite in _sprites:
			sprite.visible = true
			sprite.modulate = Color.WHITE
			sprite.frame = randi() % 6

func _apply() -> void:
	for i in _sprites.size():
		var sprite := _sprites[i]
		if i < _values.size():
			sprite.visible = true
			sprite.frame = clampi(int(_values[i]) - 1, 0, 5)
			var used := i < _consumed.size() and bool(_consumed[i])
			sprite.modulate = USED_TINT if used else Color.WHITE
		else:
			sprite.visible = false
