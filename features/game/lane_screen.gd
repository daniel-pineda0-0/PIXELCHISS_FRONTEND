extends Node2D
## Pantalla aparte del corredor final de un asiento (7 losas y el trono con la corona).
## Vive lejos del tablero, en el mismo mundo; BoardView mueve la camara aqui con un fundido
## cuando una ficha baja por el portal. Solo dibuja y da posiciones: la logica de fichas es de BoardView.
##
## Todo flota sobre un abismo: el portal de entrada (sobre su propia isla), las 7 losas en zigzag unidas por
## cadenas y el trono con la corona (tambien en su isla). No hay suelo ni ladrillos: las cadenas cuelgan hacia
## el vacio y se desvanecen. Cada zona tiene su propio fondo (service/assets/game/lane/bg_N.png), distinto al
## del tablero, y su portal / losa / trono / corona / abismo recortados de las hojas de referencia.
## Al llegar, play_intro() hace entrar el titulo y un pulso de luz en el portal.

const FONT := preload("res://service/assets/ui/theme/PressStart2P.ttf")

const CELLS := 8
const SEAT_NAMES: Array[String] = ["ROJO", "AZUL", "VERDE", "ORO"]
const COLOR_CROWN := Color(1.0, 0.85, 0.25)
const VIEW := Vector2(640.0, 360.0) / 1.4          # lo que ve la camara (igual que BoardView.VIEW_ZOOM)
## Portal de entrada: la ficha aparece en STAIR_X/STAIR_TOP_Y (sus pies) y camina a la casilla 1.
const STAIR_X := -100.0
const STAIR_TOP_Y := 44.0
const ISLAND_C := Vector2(-110.0, 44.0)             # centro de la cara de arriba de la isla del portal
const ISLAND_W := 72.0
const PORTAL_H := 54.0
## Posicion local (donde pisa la ficha) de cada casilla: 0 junto al portal ... 7 = trono. Zigzag.
const CELL_LOCAL: Array[Vector2] = [
	Vector2(-52.0, 32.0), Vector2(-24.0, 12.0), Vector2(4.0, 34.0), Vector2(32.0, 14.0),
	Vector2(60.0, 34.0), Vector2(88.0, 14.0), Vector2(116.0, 32.0), Vector2(182.0, 52.0)]
const TILE_W := 38.0
const THRONE_ISLAND_W := 104.0
const THRONE_ISLAND_TOP := 60.0
const THRONE_W := 66.0
const THRONE_FEET_Y := 58.0
const CROWN_W := 28.0
const BOB := 1.6                    # cuanto se mecen las losas (px)
const CHAIN_END_Y := 112.0          # las cadenas cuelgan hasta aqui y se desvanecen
const CHAIN: Array[Color] = [Color(0.62, 0.3, 0.16), Color(0.72, 0.88, 0.98), Color(0.42, 0.36, 0.18), Color(0.5, 0.44, 0.36)]
## Luz propia de cada corredor (rojo: brasa, azul: hielo, verde: acido, dorado: oro).
const ACCENT: Array[Color] = [Color(1.0, 0.5, 0.2), Color(0.6, 0.9, 1.0), Color(0.6, 1.0, 0.3), Color(1.0, 0.82, 0.4)]

var seat := 0:
	set(value):
		seat = value
		queue_redraw()

var _bg: Sprite2D
var _tile: Texture2D
var _throne: Texture2D
var _crown: Texture2D
var _chasm: Texture2D
var _portal: Texture2D
var _deco: Node2D                   # portal, losas, cadenas, trono y corona (se redibuja cada cuadro)
var _title: Node2D                  # titulo (entra al llegar)
var _props: Node2D                  # flecha que vuelve al tablero
var _glow: Node2D                   # luces (mezcla aditiva)
var _clock := 0.0
var _redraw := 0.0
var _intro := 99.0                  # segundos desde que se llego (99 = ya paso)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var lp := "res://service/assets/game/lane/%s_%d.png"
	_tile = load(lp % ["tile", seat])
	_throne = load(lp % ["throne", seat])
	_crown = load(lp % ["crown", seat])
	_chasm = load(lp % ["chasm", seat])
	_portal = load(lp % ["portal", seat])
	_bg = Sprite2D.new()
	_bg.texture = load(lp % ["bg", seat])
	_bg.z_index = -50
	_bg.z_as_relative = false
	_bg.scale = Vector2.ONE * (VIEW.x * 1.08 / float(_bg.texture.get_width()))
	add_child(_bg)
	_deco = Node2D.new()
	_deco.draw.connect(_draw_deco)
	add_child(_deco)
	_title = Node2D.new()
	_title.draw.connect(_draw_title)
	add_child(_title)
	_props = Node2D.new()
	_props.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_props.draw.connect(_draw_props)
	add_child(_props)
	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_title.modulate.a = 0.0
	queue_redraw()

## Solo se anima mientras la camara esta en este corredor (el resto del tiempo no cuesta nada).
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null or cam.global_position.distance_to(view_center()) > 400.0:
		return
	_clock += delta
	_intro += delta
	_redraw += delta
	_deco.queue_redraw()                # cada cuadro: las fichas se mecen con las losas
	var tin := clampf(_intro / 0.5, 0.0, 1.0)
	var tout := clampf((_intro - 3.2) / 0.8, 0.0, 1.0)
	_title.modulate.a = tin * (1.0 - tout * 0.75)
	_title.position.y = (1.0 - tin) * -10.0
	if _redraw >= 0.05:
		_redraw = 0.0
		_props.queue_redraw()
		_glow.queue_redraw()

## BoardView lo llama cuando la camara llega aqui.
func play_intro() -> void:
	_intro = 0.0

## Casilla n (0 = junto al portal, 7 = trono) en coordenadas del mundo.
func cell_pos(index: int) -> Vector2:
	return to_global(_cell_local(index))

## Posicion local con el vaiven de la losa (el trono no se mece).
func _cell_local(index: int) -> Vector2:
	var i := clampi(index, 0, CELLS - 1)
	var p: Vector2 = CELL_LOCAL[i]
	if i < CELLS - 1:
		p.y += sin(_clock * 1.6 + i * 1.3) * BOB
	return p

## Donde aparece la ficha al bajar: delante del portal.
func stairs_top() -> Vector2:
	return to_global(Vector2(STAIR_X, STAIR_TOP_Y))

## Flecha que sube (sobre el portal, local): tocarla o tocar el portal devuelve al tablero.
func arrow_pos() -> Vector2:
	return Vector2(ISLAND_C.x - 10.0, ISLAND_C.y - PORTAL_H - 14.0)

func stairs_hit(world_pos: Vector2) -> bool:
	return stairs_top().distance_to(world_pos) <= 28.0 or to_global(arrow_pos()).distance_to(world_pos) <= 22.0

func view_center() -> Vector2:
	return to_global(Vector2.ZERO)

func _draw() -> void:
	pass

func _draw_title() -> void:
	var col: Color = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	_banner("CORREDOR FINAL - %s" % SEAT_NAMES[posmod(seat, BoardMap.SEATS)],
			Vector2(40.0, -44.0), 196.0, col.lerp(Color.WHITE, 0.4), _title)

## Isla, portal, abismo, cadenas, losas numeradas, trono y corona.
func _draw_deco() -> void:
	var col: Color = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	var chain: Color = CHAIN[posmod(seat, CHAIN.size())]
	var ci := _deco
	ci.draw_texture_rect(_chasm, Rect2(-150.0, 24.0, 420.0, 96.0), false, Color(1, 1, 1, 0.9))
	var tiles: Array[Vector2] = []
	for i in CELLS - 1:
		tiles.append(_cell_local(i))
	var th := TILE_W * float(_tile.get_height()) / float(_tile.get_width())
	var isl_h := ISLAND_W * float(_tile.get_height()) / float(_tile.get_width())
	var tis_h := THRONE_ISLAND_W * float(_tile.get_height()) / float(_tile.get_width())
	var tisl := Vector2(CELL_LOCAL[CELLS - 1].x, THRONE_ISLAND_TOP)
	_chain(ci, ISLAND_C + Vector2(24.0, 12.0), tiles[0] + Vector2(-6.0, 9.0), 6.0, chain, false)
	for i in tiles.size():
		var p := tiles[i]
		var low := p + Vector2(0.0, 9.0)
		if i + 1 < tiles.size():
			_chain(ci, low + Vector2(6.0, 0.0), tiles[i + 1] + Vector2(-6.0, 9.0), 7.0, chain, false)
		_chain(ci, low + Vector2(-8.0, 0.0), Vector2(p.x - 13.0, CHAIN_END_Y), 0.0, chain, true)
		if i % 2 == 1:
			_chain(ci, low + Vector2(8.0, 0.0), Vector2(p.x + 14.0, CHAIN_END_Y), 0.0, chain, true)
	_chain(ci, tiles[tiles.size() - 1] + Vector2(8.0, 9.0), tisl + Vector2(-40.0, 12.0), 8.0, chain, false)
	_chain(ci, ISLAND_C + Vector2(-26.0, 12.0), Vector2(ISLAND_C.x - 34.0, CHAIN_END_Y), 0.0, chain, true)
	_chain(ci, tisl + Vector2(-34.0, 24.0), Vector2(tisl.x - 40.0, CHAIN_END_Y), 0.0, chain, true)
	_chain(ci, tisl + Vector2(34.0, 24.0), Vector2(tisl.x + 40.0, CHAIN_END_Y), 0.0, chain, true)
	ci.draw_texture_rect(_tile, Rect2(ISLAND_C.x - ISLAND_W * 0.5, ISLAND_C.y - isl_h * 0.32, ISLAND_W, isl_h), false)
	var pw := PORTAL_H * float(_portal.get_width()) / float(_portal.get_height())
	var pbottom := ISLAND_C.y - 2.0
	ci.draw_texture_rect(_portal, Rect2(ISLAND_C.x - 14.0 - pw * 0.5, pbottom - PORTAL_H, pw, PORTAL_H), false)
	for i in tiles.size():
		var p := tiles[i]
		ci.draw_texture_rect(_tile, Rect2(p.x - TILE_W * 0.5, p.y - th * 0.32, TILE_W, th), false)
		ci.draw_rect(Rect2(p.x - 6.0, p.y - 6.0, 12.0, 11.0), Color(0.02, 0.02, 0.04, 0.55))
		ci.draw_rect(Rect2(p.x - 6.0, p.y - 6.0, 12.0, 1.0), col.lerp(Color.WHITE, 0.4))
		ci.draw_string_outline(FONT, Vector2(p.x - 6.0, p.y + 3.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 12.0, 8, 3, Color.BLACK)
		ci.draw_string(FONT, Vector2(p.x - 6.0, p.y + 3.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 12.0, 8, col.lerp(Color.WHITE, 0.8))
	ci.draw_texture_rect(_tile, Rect2(tisl.x - THRONE_ISLAND_W * 0.5, tisl.y - tis_h * 0.32, THRONE_ISLAND_W, tis_h), false)
	var tc := CELL_LOCAL[CELLS - 1]
	var tw := THRONE_W
	var thh := tw * float(_throne.get_height()) / float(_throne.get_width())
	ci.draw_texture_rect(_throne, Rect2(tc.x - tw * 0.5, THRONE_FEET_Y - thh, tw, thh), false)
	var cw := CROWN_W
	var chh := cw * float(_crown.get_height()) / float(_crown.get_width())
	var cy := THRONE_FEET_Y - thh - 4.0 + sin(_clock * 2.0) * 2.5
	ci.draw_texture_rect(_crown, Rect2(tc.x - cw * 0.5, cy - chh, cw, chh), false)
	_banner("CORONA", Vector2(tc.x, cy - chh - 11.0), 58.0, COLOR_CROWN, ci)

## Cadena de eslabones entre dos puntos (sag = cuanto cuelga en el medio). Con fade se desvanece hacia el final.
func _chain(ci: CanvasItem, a: Vector2, b: Vector2, sag: float, color: Color, fade: bool) -> void:
	var n := maxi(int(a.distance_to(b) / 3.5), 2)
	for k in n + 1:
		var t := float(k) / float(n)
		var p := a.lerp(b, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t))
		var c := color.darkened(0.45) if k % 2 == 1 else color
		if fade:
			c.a = 1.0 - t * t
		ci.draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), c)

## La flecha que vuelve al tablero (bobbing).
func _draw_props() -> void:
	var col: Color = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	var bob := sin(_clock * 3.0) * 2.5
	var c := arrow_pos() + Vector2(0.0, bob)
	var ac := col.lerp(Color.WHITE, 0.55)
	var out := Color(0, 0, 0, 0.8)
	_props.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(10, 4), c + Vector2(-10, 4)]), out)
	_props.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(8, 3), c + Vector2(-8, 3)]), ac)
	_props.draw_rect(Rect2(c.x - 2.0, c.y + 3.0, 4.0, 5.0), ac)

## Luces aditivas: pulso del portal, ola sobre las losas, corona y motas.
func _draw_glow() -> void:
	var accent: Color = ACCENT[posmod(seat, ACCENT.size())]
	var pulse := 0.85 + 0.15 * sin(_clock * 2.2)
	var pc := Vector2(ISLAND_C.x - 14.0, ISLAND_C.y - PORTAL_H * 0.5)
	_glow.draw_circle(pc, 26.0, Color(accent.r, accent.g, accent.b, 0.06 * pulse))
	_glow.draw_circle(pc, 14.0, Color(accent.r, accent.g, accent.b, 0.08 * pulse))
	if _intro < 1.2:
		var u := _intro / 1.2
		_glow.draw_arc(pc, 8.0 + 60.0 * u, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, 0.55 * (1.0 - u)), 3.0)
		_glow.draw_circle(pc, 30.0 * (1.0 - u), Color(1.0, 1.0, 1.0, 0.25 * (1.0 - u)))
	for i in CELLS - 1:
		var k := 0.5 + 0.5 * sin(_clock * 3.0 - i * 0.75)
		var cp := _cell_local(i)
		_glow.draw_circle(cp + Vector2(0.0, 2.0), 15.0, Color(accent.r, accent.g, accent.b, 0.02 + 0.09 * k * k))
	var tc := CELL_LOCAL[CELLS - 1]
	var cc := Vector2(tc.x, THRONE_FEET_Y - 62.0)
	_glow.draw_circle(cc, 30.0, Color(1.0, 0.85, 0.3, 0.07 * pulse))
	_glow.draw_circle(cc, 16.0, Color(1.0, 0.85, 0.3, 0.09 * pulse))
	for r in 8:
		var a := _clock * 0.5 + TAU * r / 8.0
		_glow.draw_line(cc + Vector2(cos(a), sin(a)) * 18.0, cc + Vector2(cos(a), sin(a)) * (32.0 + 6.0 * sin(_clock * 2.0 + r)),
				Color(1.0, 0.9, 0.4, 0.16), 2.0)
	for sp in 5:
		var a := _clock * 1.3 + TAU * sp / 5.0
		var p := cc + Vector2(cos(a) * 22.0, sin(a) * 15.0)
		_glow.draw_rect(Rect2(p, Vector2(1.5, 1.5)), Color(1.0, 0.95, 0.6, 0.8))
	for i in 18:
		var x := -240.0 + fposmod(i * 37.3 + _clock * (3.0 + (i % 4)), 480.0)
		var y := 100.0 - fposmod(i * 23.7 + _clock * (4.0 + (i % 3) * 2.0), 220.0)
		var tw := 0.5 + 0.5 * sin(_clock * 2.0 + i)
		_glow.draw_rect(Rect2(x, y, 1.5, 1.5), Color(accent.r, accent.g, accent.b, 0.25 + 0.45 * tw))

func _label(text: String, center: Vector2, width: float, color: Color, ci: CanvasItem = self) -> void:
	var pos := Vector2(center.x - width / 2.0, center.y)
	ci.draw_string_outline(FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, 8, 4, Color.BLACK)
	ci.draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, 8, color)

func _banner(text: String, center: Vector2, width: float, color: Color, ci: CanvasItem = self) -> void:
	var r := Rect2(center.x - width * 0.5, center.y - 9.0, width, 14.0)
	ci.draw_rect(r, Color(0.03, 0.02, 0.04, 0.62))
	ci.draw_rect(Rect2(r.position, Vector2(width, 1.0)), color)
	ci.draw_rect(Rect2(r.position + Vector2(0.0, 13.0), Vector2(width, 1.0)), color.darkened(0.55))
	_label(text, Vector2(center.x, center.y), width, color, ci)
