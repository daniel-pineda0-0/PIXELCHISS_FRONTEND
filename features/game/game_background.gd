extends CanvasLayer
## Fondo de la partida. Un fondo por asiento (rojo: castillo en lava, azul: castillo de hielo,
## verde: pantano acido, dorado: desierto). BoardView avisa entre que dos zonas esta la camara y
## cuanto: asi el fondo se mezcla de forma continua al recorrer el tablero, sin cortes.
## Sobre cada fondo va una neblina de suelo: degradado del color oscuro de la zona que sube desde abajo,
## para que la franja de casillas no quede pegada sobre la ilustracion sino apoyada en un suelo que se
## funde con ella (el suelo de strip_signs.gd termina en ese mismo color).
## Cada zona tiene ademas su animacion (bg_fx.gd): buitres en la lava, ojos en el hielo, luciernagas en el pantano
## y tormenta de arena en el desierto. Ya no hay esqueletos decorativos aqui: las fichas en casa viven en el suelo del tablero (HomeCrowd).
## Queda detras del mundo y no se mueve con la camara.

const SCREEN := Vector2(640.0, 360.0)
const TEXTURES: Array[Texture2D] = [
	preload("res://service/assets/backgrounds/game/bg_red.png"),
	preload("res://service/assets/backgrounds/game/bg_blue.png"),
	preload("res://service/assets/backgrounds/game/bg_green.png"),
	preload("res://service/assets/backgrounds/game/bg_gold.png"),
]
## Color de la neblina de suelo por zona: rojo, azul, verde, dorado (parecido al FLOOR de strip_signs.gd).
const HAZE: Array[Color] = [Color(0.09, 0.02, 0.03), Color(0.02, 0.05, 0.12), Color(0.02, 0.07, 0.03), Color(0.13, 0.08, 0.04)]
const HAZE_TOP := 190.0                       # y de pantalla donde empieza a notarse
const HAZE_ALPHA := 0.78                      # opacidad abajo del todo
## por asiento: en la lava la neblina es mas suave para que el rio de lava siga brillando donde salen las fichas
const HAZE_ALPHAS: Array[float] = [0.34, 0.7, 0.7, 0.62]

@onready var sprite: Sprite2D = $Sprite

var _top: Sprite2D
var _a := -1
var _b := -1
var _mix := 0.0
var _t := 0.0
var _groups: Array[Node2D] = []

func _ready() -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_top = Sprite2D.new()
	_top.centered = false
	_top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_top.visible = false
	add_child(_top)
	for seat in TEXTURES.size():
		var group := Node2D.new()
		add_child(group)
		_groups.append(group)
		var haze := Polygon2D.new()
		var clear := Color(HAZE[seat].r, HAZE[seat].g, HAZE[seat].b, 0.0)
		var dark := Color(HAZE[seat].r, HAZE[seat].g, HAZE[seat].b, HAZE_ALPHAS[seat])
		var mid := Color(HAZE[seat].r, HAZE[seat].g, HAZE[seat].b, HAZE_ALPHAS[seat] * 0.35)
		var y_mid := HAZE_TOP + (SCREEN.y - HAZE_TOP) * 0.5
		haze.polygon = PackedVector2Array([
			Vector2(0, HAZE_TOP), Vector2(SCREEN.x, HAZE_TOP),
			Vector2(SCREEN.x, y_mid), Vector2(SCREEN.x, SCREEN.y),
			Vector2(0, SCREEN.y), Vector2(0, y_mid)])
		haze.vertex_colors = PackedColorArray([clear, clear, mid, dark, dark, mid])
		group.add_child(haze)
		# la vida del fondo (buitres, brasas, nieve...) vive ahora en WorldBackdrop, pegada al mundo
	set_blend(0, 0, 0.0)

func set_seat(seat: int) -> void:
	set_blend(seat, seat, 0.0)

## Mezcla del fondo de `a` hacia el de `b`; mix de 0 a 1.
func set_blend(a: int, b: int, mix: float) -> void:
	a = posmod(a, TEXTURES.size())
	b = posmod(b, TEXTURES.size())
	if a != _a:
		_a = a
		_fit(sprite, TEXTURES[a])
	if b != _b:
		_b = b
		_fit(_top, TEXTURES[b])
	_mix = mix if a != b else 0.0
	_top.visible = _mix > 0.001
	for seat in _groups.size():
		var alpha := 0.0
		if a == b:
			alpha = 1.0 if seat == a else 0.0
		elif seat == a:
			alpha = 1.0 - _mix
		elif seat == b:
			alpha = _mix
		var group := _groups[seat]
		group.modulate = Color(1.0, 1.0, 1.0, alpha)
		group.visible = alpha > 0.01

## Ajusta cualquier fondo (de la resolucion que sea) a la pantalla de 640x360.
func _fit(target: Sprite2D, texture: Texture2D) -> void:
	target.texture = texture
	target.scale = Vector2(SCREEN.x / texture.get_width(), SCREEN.y / texture.get_height())

func _process(delta: float) -> void:
	_t += delta
	var k := 0.965 + 0.035 * (0.5 + 0.5 * sin(_t * 1.7) * sin(_t * 0.9 + 1.0))
	sprite.modulate = Color(k, k, k)
	_top.modulate = Color(k, k, k, _mix)
