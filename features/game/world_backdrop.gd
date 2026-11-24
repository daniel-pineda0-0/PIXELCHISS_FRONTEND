class_name WorldBackdrop
extends Node2D
## Fondo de una zona PEGADO AL MUNDO: se mueve junto con las fichas en casa y la franja de casillas de su chunk,
## asi lo que se pinta detras (el charco de lava, el arco, el castillo) siempre queda donde salen las fichas.
## El arte se disena en coordenadas de pantalla (640x360) con la camara centrada en el chunk, asi que este nodo se
## escala por 1 / zoom y se centra en el chunk; bg_fx y la neblina viven dentro en esas mismas coordenadas.
## Las imagenes bg_wide_N.png traen 125 px extra a cada lado (espejo, desenfocado y oscuro, con el borde que se
## desvanece): entre dos zonas vecinas el fondo se funde con niebla en vez de cortarse en seco.
## BoardView lo coloca cada cuadro (la copia del anillo mas cercana a la camara) y lo oculta si queda lejos.

const SCREEN := Vector2(640.0, 360.0)
const ZOOM := 1.4                         # igual que BoardView.VIEW_ZOOM
const TEX := "res://service/assets/backgrounds/game/bg_wide_%d.png"
const BG_FX := preload("res://features/game/bg_fx.gd")
const HAZE: Array[Color] = [Color(0.09, 0.02, 0.03), Color(0.02, 0.05, 0.12), Color(0.02, 0.07, 0.03), Color(0.13, 0.08, 0.04)]
const HAZE_ALPHAS: Array[float] = [0.34, 0.7, 0.7, 0.62]
const HAZE_TOP := 190.0

var seat := 0
var _sprite: Sprite2D
var _t := 0.0

func _ready() -> void:
	z_index = -50
	z_as_relative = false
	scale = Vector2.ONE / ZOOM
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite = Sprite2D.new()
	_sprite.texture = load(TEX % seat)
	_sprite.scale = Vector2.ONE * (SCREEN.y / float(_sprite.texture.get_height()))
	add_child(_sprite)
	var screen := Node2D.new()                # coordenadas de pantalla: (0,0) arriba a la izquierda
	screen.position = -SCREEN * 0.5
	add_child(screen)
	var haze := Polygon2D.new()
	var c := HAZE[seat]
	var clear := Color(c.r, c.g, c.b, 0.0)
	var dark := Color(c.r, c.g, c.b, HAZE_ALPHAS[seat])
	var mid := Color(c.r, c.g, c.b, HAZE_ALPHAS[seat] * 0.35)
	var y_mid := HAZE_TOP + (SCREEN.y - HAZE_TOP) * 0.5
	var x0 := -130.0
	var x1 := SCREEN.x + 130.0
	haze.polygon = PackedVector2Array([Vector2(x0, HAZE_TOP), Vector2(x1, HAZE_TOP), Vector2(x1, y_mid),
			Vector2(x1, SCREEN.y), Vector2(x0, SCREEN.y), Vector2(x0, y_mid)])
	haze.vertex_colors = PackedColorArray([clear, clear, mid, dark, dark, mid])
	screen.add_child(haze)
	var fx = BG_FX.new()
	fx.kind = seat
	screen.add_child(fx)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var k := 0.965 + 0.035 * (0.5 + 0.5 * sin(_t * 1.7) * sin(_t * 0.9 + 1.0))   # respira como el fondo de pantalla
	_sprite.modulate = Color(k, k, k)
