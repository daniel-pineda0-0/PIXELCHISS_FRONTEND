class_name HomeSlot
extends Node2D
## Una ficha en casa, dibujada en el fondo de su zona. No es la ficha del tablero (esa se oculta mientras
## esta en casa): es un efecto vivo con el esqueleto de su color:
##   dorado  (desierto)  se deshace en arena y se vuelve a armar con un remolino
##   azul    (hielo)     esta congelado en un bloque que se agrieta, se rompe y se reconjela
##   verde   (pantano)   se disuelve en acido y vuelve a salir del charco
##   rojo    (lava)      se funde en la lava y vuelve a salir del charco
## La hoja (tools/gen_home_fx.py) trae 20 cuadros: reposo (2), deshacerse (8), restos (2), rehacerse (8).
##
## HomeCrowd lo manda con show_home() (llega o ya estaba) y hide_home() (sale a la salida del tablero).
## Si la ficha SALE, el esqueleto desaparece al instante y solo se desvanece lo que quedaba (monton,
## esquirlas o charco). Si VUELVE (captura), los restos aparecen y de ellos se rehace el esqueleto.

enum State { HIDDEN, IDLE, DESTROY, RESIDUE, REBUILD, LEAVING, ENTERING }

const SHEETS: Array[String] = ["red", "blue", "green", "gold"]      # por asiento
## Hojas nuevas (tools/gen_ref_art.py, a partir del arte de referencia): rojo = charco de lava con humo, azul = cubo de hielo,
## dorado = remolino de arena. Mismo formato de 20 cuadros; "deshacerse" es el forcejeo del esqueleto por salir y
## "rehacerse" es el camino de vuelta. Verde = jaula de lianas. Si el archivo no existe, usa la hoja vieja.
const BREAKOUT: Array[bool] = [true, true, true, true]
const COLS := 5
const ROWS := 4
const FEET := Vector2(24.0, 51.0)                # pixel del cuadro donde apoya la ficha
const SHADOW_W := 23.0
const SHADOW_H := 4.5
## Integracion con el fondo, por asiento (rojo, azul, verde, dorado). El shader home_blend.gdshader lleva la ficha
## a la paleta de su zona (luz ambiente + color de sombra); el resplandor aditivo ilumina el suelo de alrededor
## y la niebla de suelo (FOG) tapa la base de la ficha, como el suelo del fondo.
const BLEND := preload("res://features/game/home_blend.gdshader")
const AMBIENT: Array[Color] = [Color(1.0, 0.70, 0.60), Color(0.70, 0.84, 1.0), Color(0.68, 0.95, 0.62), Color(1.0, 0.86, 0.62)]
const SHADOW: Array[Color] = [Color(0.17, 0.05, 0.06), Color(0.05, 0.10, 0.20), Color(0.05, 0.14, 0.06), Color(0.22, 0.13, 0.06)]
const FOG: Array[Color] = [Color(0.12, 0.03, 0.04), Color(0.03, 0.07, 0.15), Color(0.03, 0.10, 0.04), Color(0.20, 0.12, 0.06)]
const GLOW: Array[Color] = [Color(1.0, 0.45, 0.1), Color(0.5, 0.85, 1.0), Color(0.5, 1.0, 0.3), Color(1.0, 0.8, 0.4)]
const GLOW_STRENGTH: Array[float] = [0.42, 0.24, 0.36, 0.14]
const IDLE_FRAMES: Array[int] = [0, 1]
const DESTROY_FIRST := 2
const DESTROY_COUNT := 8
const RESIDUE_FIRST := 10
const RESIDUE_COUNT := 2
const REBUILD_FIRST := 12
const REBUILD_COUNT := 8
const FPS := 9.0
const IDLE_FPS := 2.2
const WAIT_MIN := 3.5
const WAIT_MAX := 9.0
const RESIDUE_HOLD := 1.4
const FADE_TIME := 0.7
const ENTER_TIME := 0.45

var state := State.HIDDEN
var _sprite: Sprite2D
var _shadow: Polygon2D
var _glow: Sprite2D
var _front: Node2D
var _seat := 0
var _clock := 0.0
var _redraw := 0.0
var _phase := 0.0
var _time := 0.0
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _new_art := false

func setup(seat: int) -> void:
	_rng.randomize()
	_seat = posmod(seat, 4)
	_phase = _rng.randf() * TAU
	_build_glow()
	# sombra de contacto en el suelo: asienta la ficha en el fondo (el acido y la lava ya traen su charco)
	_shadow = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * SHADOW_W, sin(a) * SHADOW_H))
	_shadow.polygon = pts
	_shadow.color = Color(0, 0, 0, 0.30)
	_shadow.visible = true
	add_child(_shadow)
	_sprite = Sprite2D.new()
	var sheet: String = SHEETS[posmod(seat, SHEETS.size())]
	var path := "res://service/assets/game/home/home_%s.png" % sheet
	var path_new := "res://service/assets/game/home/home_%s_breakout.png" % sheet
	if BREAKOUT[_seat] and ResourceLoader.exists(path_new):
		path = path_new
		_new_art = true
	_sprite.texture = load(path)
	_sprite.hframes = COLS
	_sprite.vframes = ROWS
	_sprite.centered = false
	if _new_art:                       # hojas al doble de resolucion: se dibujan a la mitad, mas nitidas
		_sprite.scale = Vector2(0.5, 0.5)
		_sprite.offset = -FEET * 2.0
	else:
		_sprite.offset = -FEET
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = BLEND
	mat.set_shader_parameter("ambient", AMBIENT[_seat])
	mat.set_shader_parameter("shadow_tint", SHADOW[_seat])
	if _new_art:                       # el arte nuevo ya trae su luz: solo un toque para asentarlo en el fondo
		mat.set_shader_parameter("amount", 0.22)
		mat.set_shader_parameter("sat", 1.0)
		mat.set_shader_parameter("lift", 0.06)
		mat.set_shader_parameter("cap", 1.0)
	_sprite.material = mat
	add_child(_sprite)
	# vegetacion, rocas y particulas DELANTE de la ficha: tapan su base y la hunden en el suelo
	_front = Node2D.new()
	_front.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_front.draw.connect(_draw_front)
	add_child(_front)
	visible = false

func _build_glow() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_glow = Sprite2D.new()
	_glow.texture = tex
	_glow.scale = Vector2(1.7, 0.6)
	_glow.position = Vector2(0, -2)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.modulate = Color(GLOW[_seat].r, GLOW[_seat].g, GLOW[_seat].b, GLOW_STRENGTH[_seat])
	add_child(_glow)

## La ficha esta (o vuelve a estar) en casa. `instant` = ya estaba al abrir la partida: sin entrada.
func show_home(instant := false) -> void:
	if is_present():
		return
	visible = true
	modulate = Color.WHITE
	if instant:
		_enter_idle(_rng.randf_range(0.0, WAIT_MAX))     # cada hueco arranca en un punto distinto del ciclo
		return
	state = State.ENTERING
	_time = 0.0
	modulate.a = 0.0
	_set_frame(RESIDUE_FIRST)

## La ficha salio a la calle: el esqueleto ya no esta, se desvanecen los restos.
func hide_home() -> void:
	if state == State.HIDDEN or state == State.LEAVING:
		return
	state = State.LEAVING
	_time = 0.0
	_set_frame(RESIDUE_FIRST)

func is_present() -> bool:
	return state != State.HIDDEN and state != State.LEAVING

func _process(delta: float) -> void:
	if state == State.HIDDEN:
		return
	_time += delta
	_clock += delta
	_redraw += delta
	if _redraw >= 0.07:
		_redraw = 0.0
		_front.queue_redraw()
	if _glow != null:
		var flick := 0.82 + 0.18 * sin(_clock * 2.6 + _phase) + 0.06 * sin(_clock * 7.3 + _phase * 2.0)
		_glow.modulate.a = GLOW_STRENGTH[_seat] * flick * (0.55 if _new_art else 1.0)
	match state:
		State.IDLE:
			_set_frame(IDLE_FRAMES[int(_time * IDLE_FPS) % IDLE_FRAMES.size()])
			_wait -= delta
			if _wait <= 0.0:
				state = State.DESTROY
				_time = 0.0
		State.DESTROY:
			var i := int(_time * FPS)
			if i >= DESTROY_COUNT:
				state = State.RESIDUE
				_time = 0.0
				_set_frame(RESIDUE_FIRST)
			else:
				_set_frame(DESTROY_FIRST + i)
		State.RESIDUE:
			_set_frame(RESIDUE_FIRST + int(_time * 3.0) % RESIDUE_COUNT)
			if _time >= RESIDUE_HOLD:
				state = State.REBUILD
				_time = 0.0
		State.REBUILD:
			var i := int(_time * FPS)
			if i >= REBUILD_COUNT:
				_enter_idle(_rng.randf_range(WAIT_MIN, WAIT_MAX))
			else:
				_set_frame(REBUILD_FIRST + i)
		State.LEAVING:
			_set_frame(RESIDUE_FIRST + int(_time * 3.0) % RESIDUE_COUNT)
			modulate.a = 1.0 - clampf(_time / FADE_TIME, 0.0, 1.0)
			if _time >= FADE_TIME:
				state = State.HIDDEN
				visible = false
		State.ENTERING:
			modulate.a = clampf(_time / ENTER_TIME, 0.0, 1.0)
			_set_frame(RESIDUE_FIRST + int(_time * 3.0) % RESIDUE_COUNT)
			if _time >= ENTER_TIME:
				state = State.REBUILD
				_time = 0.0
				modulate.a = 1.0

func _enter_idle(wait: float) -> void:
	state = State.IDLE
	_time = 0.0
	_wait = wait
	_set_frame(IDLE_FRAMES[0])

func _set_frame(index: int) -> void:
	if _sprite != null:
		_sprite.frame = clampi(index, 0, COLS * ROWS - 1)

# --- Detalles delante de la ficha: la hunden en el suelo del fondo ----------------------------------
# Todo en tonos oscuros del propio fondo (no colores vivos): son siluetas de primer plano, no pegatinas.

func _draw_front() -> void:
	if _new_art:                       # el charco, el cubo y el remolino ya traen su base: solo niebla suave y particulas
		_fog(0.2)
		match _seat:
			0: _rise(Color(1.0, 0.6, 0.2), 5, 30.0, 14.0)
			1: _rise(Color(0.8, 0.94, 1.0), 3, 22.0, 12.0)
			2: _rise(Color(0.7, 1.0, 0.4), 4, 26.0, 12.0)           # esporas y luciernagas
		return
	_fog()
	match _seat:
		0:
			_stone(Vector2(-27, 2), 6.0, 4.0, Color(0.09, 0.04, 0.05), Color(0.95, 0.42, 0.14))
			_stone(Vector2(28, 3), 5.0, 3.5, Color(0.08, 0.03, 0.04), Color(0.9, 0.38, 0.12))
			_stone(Vector2(-9, 5), 3.0, 2.0, Color(0.10, 0.05, 0.05), Color(0.95, 0.42, 0.14))
			_rise(Color(1.0, 0.6, 0.2), 4, 30.0, 12.0)            # brasas que suben del charco
		1:
			_drift(Color(0.30, 0.46, 0.62), Color(0.14, 0.24, 0.40))
			_crystal(Vector2(-25, 1), 5.0)
			_crystal(Vector2(26, 2), 4.0)
			_rise(Color(0.8, 0.94, 1.0), 3, 22.0, 14.0)           # vaho helado
		2:
			for i in 8:
				var x := -26.0 + i * 7.4 + sin(float(i) * 2.3) * 1.5
				var h := 5.0 + fposmod(float(i) * 3.7, 6.0)
				var sway := sin(_clock * 1.4 + float(i) + _phase) * 1.3
				_front.draw_line(Vector2(x, 4), Vector2(x + sway, 4.0 - h), Color(0.02, 0.07, 0.03), 2.0)
				_front.draw_line(Vector2(x + sway * 0.5, 4.0 - h * 0.5), Vector2(x + sway, 4.0 - h), Color(0.10, 0.25, 0.10), 1.0)
			_rise(Color(0.7, 1.0, 0.4), 4, 26.0, 10.0)            # burbujas de acido
		3:
			_dune()
			_pebble(Vector2(-23, 3))
			_pebble(Vector2(19, 4))
			_pebble(Vector2(30, 2))

## Niebla del suelo: degradado del color oscuro de la zona delante de los pies de la ficha.
func _fog(strength := 0.5) -> void:
	var c := FOG[_seat]
	var clear := Color(c.r, c.g, c.b, 0.0)
	var dense := Color(c.r, c.g, c.b, strength)
	_front.draw_polygon(PackedVector2Array([Vector2(-34, -14), Vector2(34, -14), Vector2(34, 8), Vector2(-34, 8)]),
			PackedColorArray([clear, clear, dense, dense]))

func _stone(p: Vector2, w: float, h: float, body: Color, rim: Color) -> void:
	_front.draw_colored_polygon(PackedVector2Array([
		p + Vector2(-w, 0), p + Vector2(-w * 0.6, -h), p + Vector2(w * 0.2, -h * 1.2), p + Vector2(w, 0)]), body)
	_front.draw_line(p + Vector2(-w * 0.6, -h), p + Vector2(w * 0.2, -h * 1.2), Color(rim.r, rim.g, rim.b, 0.7), 1.0)

func _crystal(p: Vector2, h: float) -> void:
	_front.draw_colored_polygon(PackedVector2Array([
		p + Vector2(-1.5, 0), p + Vector2(0, -h), p + Vector2(1.5, 0)]), Color(0.38, 0.58, 0.78))
	_front.draw_line(p + Vector2(0, -h), p + Vector2(-1.5, 0), Color(0.85, 0.95, 1.0, 0.8), 1.0)

func _arc_pts(rx: float, ry: float, cy: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := PI + PI * i / float(n)
		pts.append(Vector2(cos(a) * rx, cy + sin(a) * ry))
	return pts

func _drift(top: Color, shade: Color) -> void:
	_front.draw_colored_polygon(_arc_pts(29.0, 4.0, 4.0, 12), shade)
	_front.draw_colored_polygon(_arc_pts(27.0, 3.0, 3.0, 12), top)

func _dune() -> void:
	var pts := _arc_pts(31.0, 4.5, 5.0, 14)
	_front.draw_colored_polygon(pts, Color(0.50, 0.36, 0.20))
	_front.draw_polyline(pts, Color(0.72, 0.55, 0.32), 1.0)

func _pebble(p: Vector2) -> void:
	_front.draw_rect(Rect2(p, Vector2(2, 1)), Color(0.30, 0.21, 0.12))
	_front.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 1)), Color(0.42, 0.30, 0.17))

## Particulas que suben y se apagan (brasas, burbujas, vaho).
func _rise(color: Color, count: int, height: float, spread: float) -> void:
	for i in count:
		var u := fposmod(_clock * 0.45 + float(i) / float(count) + _phase * 0.1, 1.0)
		var x := -spread + float(i) * (spread * 2.0 / float(maxi(count - 1, 1))) + sin(_clock * 1.7 + float(i) * 2.0) * 3.0
		var y := -6.0 - u * height
		_front.draw_rect(Rect2(x, y, 1.5, 1.5), Color(color.r, color.g, color.b, (1.0 - u) * 0.9))
