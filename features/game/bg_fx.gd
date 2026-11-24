extends Node2D
## Vida para los fondos de la partida (coordenadas de pantalla 640x360, detras del mundo). Un nodo por zona,
## dentro del grupo que GameBackground mezcla entre zonas, asi que aparece y se desvanece con su fondo.
## Sprites sacados del arte de referencia con tools/gen_ref_art.py (service/assets/game/bgfx/) y los buitres de la
## pantalla de inicio (service/assets/backgrounds/login/vulture_N.png). Lo que falte se omite sin romper nada.
##   0 rojo   (lava)     los 5 buitres del login planeando en circulos, humo que sube del rio de lava y brasas
##   1 azul   (hielo)    nieve, carambanos que se sueltan del techo y se rompen al caer, y ojos que parpadean en la cueva
##   2 verde  (pantano)  luciernagas (con su resplandor), esporas y ojos entre las lianas
##   3 dorado (desierto) tornados de arena que cruzan el fondo a distintas distancias y rachas de tormenta
## Todo se actualiza solo mientras se ve.

const SCREEN := Vector2(640.0, 360.0)
const FX := "res://service/assets/game/bgfx/"
const VULTURE := "res://service/assets/backgrounds/login/vulture_%d.png"
## Buitres como en la pantalla de inicio: centro del recorrido, radios de la elipse y velocidad angular (negativa = al reves).
const VULTURES: Array = [
	{"c": Vector2(170, 112), "r": Vector2(95, 22), "sp": 0.13, "a": 0.0},
	{"c": Vector2(500, 82), "r": Vector2(110, 18), "sp": -0.10, "a": 1.0},
	{"c": Vector2(340, 58), "r": Vector2(80, 14), "sp": 0.15, "a": 2.5},
	{"c": Vector2(470, 132), "r": Vector2(130, 12), "sp": -0.08, "a": 4.0},
	{"c": Vector2(250, 40), "r": Vector2(60, 10), "sp": 0.18, "a": 5.0},
]
const GROUND_Y := 268.0                   # donde se estrellan los carambanos (suelo detras de las casas)

var kind := 0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _add: Node2D                          # luces (mezcla aditiva)
var _parts: Array = []        # particulas: {p, sp, s, a, ph}
var _eyes: Array = []         # ojos: {p, gap, period, on, ph}
var _vultures: Array = []     # {tex, fw, h, c, r, sp, a, ph}
var _smoke: Array = []        # {p, u, life, s, i}
var _smoke_tex: Array = []
var _ic: Dictionary = {}      # carambano activo: {state, x, y, v, t}
var _ic_wait := 3.0
var _ic_tex: Texture2D
var _splash_tex: Texture2D
var _debris_tex: Texture2D
var _eye_tex: Texture2D
var _eye_n := 5
var _eye_w := 1
var _eye_h := 1
var _ff_tex: Texture2D
var _glow_tex: Texture2D
var _tor_tex: Texture2D
var _tors: Array = []         # tornados: {x, y, sc, sp, a, ph}

func _tex(file: String) -> Texture2D:
	var path := FX + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _ready() -> void:
	_rng.seed = 7919 * (kind + 1)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_add = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add.material = mat
	_add.draw.connect(_draw_add)
	add_child(_add)
	_glow_tex = _tex("glow.png")
	match kind:
		0:
			_make_parts(40, 120.0, 360.0)
			for i in VULTURES.size():
				var path := VULTURE % (i + 1)
				if not ResourceLoader.exists(path):
					continue
				var tex := load(path) as Texture2D
				var d: Dictionary = VULTURES[i]
				_vultures.append({"tex": tex, "fw": tex.get_width() / 4, "h": tex.get_height(), "c": d.c, "r": d.r,
						"sp": d.sp, "a": d.a, "ph": _rng.randf() * 10.0, "scale": 1.0})   # escala 1: pixeles nitidos
			for n in ["smoke_1.png", "smoke_2.png"]:
				var st := _tex(n)
				if st != null:
					_smoke_tex.append(st)
			for i in 0:                                          # el humo ya lo traen las fichas y el fondo
				_smoke.append({"p": Vector2(_rng.randf_range(230.0, 420.0), GROUND_Y + _rng.randf_range(-8.0, 8.0)),
						"u": _rng.randf(), "life": _rng.randf_range(4.0, 7.0), "s": _rng.randf_range(0.7, 1.1), "i": i})
		1:
			_make_parts(60, 0.0, 360.0)
			_make_eyes([Vector2(34, 150), Vector2(88, 208), Vector2(22, 262), Vector2(122, 118), Vector2(150, 248)])
			_ic_tex = _tex("icicle_fall.png")
			_splash_tex = _tex("icicle_splash.png")
			_debris_tex = _tex("icicle_debris.png")
			_load_eyes()
		2:
			_make_parts(26, 70.0, 320.0)
			_make_eyes([Vector2(58, 150), Vector2(300, 118), Vector2(560, 205), Vector2(430, 92)])
			_ff_tex = _tex("firefly.png")
			_load_eyes()
		3:
			_make_parts(80, 90.0, 350.0)
			_tor_tex = _tex("tornado.png")
			# lejos (chico, translucido, lento) a cerca (grande, mas visible): como en el arte de referencia
			# el fondo ya trae sus tornados pintados: sin tornados extra (se veian fantasmales)
			for d in []:
				_tors.append({"x": d[0], "y": d[1], "sc": d[2], "sp": d[3], "a": d[4], "ph": _rng.randf() * 6.0})

func _load_eyes() -> void:
	_eye_tex = _tex("eyes.png")
	if _eye_tex != null:
		_eye_w = _eye_tex.get_width() / _eye_n
		_eye_h = _eye_tex.get_height()

func _make_parts(n: int, y_min: float, y_max: float) -> void:
	for i in n:
		_parts.append({"p": Vector2(_rng.randf_range(0.0, 640.0), _rng.randf_range(y_min, y_max)),
				"sp": _rng.randf(), "s": _rng.randf_range(1.0, 2.2), "a": _rng.randf_range(0.35, 0.95), "ph": _rng.randf() * TAU})

func _make_eyes(spots: Array) -> void:
	for spot in spots:
		_eyes.append({"p": spot, "gap": _rng.randf_range(7.0, 10.0), "period": _rng.randf_range(6.0, 11.0),
				"on": _rng.randf_range(2.4, 3.6), "ph": _rng.randf_range(0.0, 10.0)})

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	match kind:
		0:
			_step_rise(delta, 14.0, 34.0, 80.0, 370.0)
			for v in _vultures:
				v.a += float(v.sp) * delta
			for s in _smoke:
				s.u += delta / float(s.life)
				var p: Vector2 = s.p
				p.y -= 11.0 * delta
				p.x += (3.0 + sin(_t * 0.6 + float(s.i))) * delta
				s.p = p
				if float(s.u) >= 1.0:
					s.u = 0.0
					s.life = _rng.randf_range(4.0, 7.0)
					s.p = Vector2(_rng.randf_range(230.0, 420.0), GROUND_Y + _rng.randf_range(-8.0, 8.0))
		1:
			_step_fall(delta, 12.0, 24.0)
			_step_icicle(delta)
		2:
			_step_rise(delta, 5.0, 11.0, 40.0, 340.0)
		3:
			var m := _storm_mul()
			for q in _parts:
				var p: Vector2 = q.p
				p.x -= (80.0 + float(q.sp) * 160.0) * m * delta
				p.y += sin(_t * 1.3 + float(q.ph)) * 8.0 * delta
				if p.x < -30.0:
					p = Vector2(670.0, _rng.randf_range(90.0, 350.0))
				q.p = p
			for tn in _tors:
				tn.x -= float(tn.sp) * (0.7 + 0.3 * m) * delta
				if float(tn.x) < -90.0:
					tn.x = 730.0
	queue_redraw()
	_add.queue_redraw()

## Intensidad de la tormenta de arena (0 calma, 1 racha fuerte): sube y baja despacio.
func _storm_gust() -> float:
	return 0.5 + 0.5 * sin(_t * 0.35 - 1.0)

func _storm_mul() -> float:
	return 0.6 + 1.6 * _storm_gust()

func _step_rise(delta: float, v_min: float, v_range: float, top: float, bottom: float) -> void:
	for q in _parts:
		var p: Vector2 = q.p
		p.y -= (v_min + float(q.sp) * v_range) * delta * 0.5
		p.x += sin(_t * 0.8 + float(q.ph)) * 6.0 * delta
		if p.y < top:
			p = Vector2(_rng.randf_range(0.0, 640.0), bottom)
		q.p = p

func _step_fall(delta: float, v_min: float, v_range: float) -> void:
	for q in _parts:
		var p: Vector2 = q.p
		p.y += (v_min + float(q.sp) * v_range) * delta
		p.x += sin(_t * 0.9 + float(q.ph)) * 9.0 * delta
		if p.y > 370.0:
			p = Vector2(_rng.randf_range(0.0, 640.0), -6.0)
		q.p = p

## Carambano: avisa con polvo en el techo, cae con la estela del sprite, se rompe en el suelo y deja restos.
func _step_icicle(delta: float) -> void:
	if _ic_tex == null:
		return
	if _ic.is_empty():
		_ic_wait -= delta
		if _ic_wait <= 0.0:
			var left := _rng.randf() < 0.5
			_ic = {"state": "warn", "x": _rng.randf_range(24.0, 150.0) if left else _rng.randf_range(490.0, 616.0),
					"y": -float(_ic_tex.get_height()), "v": 0.0, "t": 0.0}
		return
	_ic.t += delta
	match String(_ic.state):
		"warn":
			if float(_ic.t) >= 0.9:
				_ic.state = "fall"
				_ic.t = 0.0
		"fall":
			_ic.v += 520.0 * delta
			_ic.y += float(_ic.v) * delta
			if float(_ic.y) + float(_ic_tex.get_height()) >= GROUND_Y:
				_ic.state = "hit"
				_ic.t = 0.0
		"hit":
			if float(_ic.t) >= 1.5:
				_ic = {}
				_ic_wait = _rng.randf_range(5.0, 10.0)

func _draw() -> void:
	match kind:
		0: _draw_lava()
		1: _draw_ice()
		2: _draw_swamp()
		3: _draw_sand()

# --- Lava: buitres del login, humo y brasas ---------------------------------------------------------

func _draw_lava() -> void:
	for q in _parts:
		var p: Vector2 = q.p
		var fade := clampf((p.y - 80.0) / 140.0, 0.0, 1.0)
		var s: float = q.s
		draw_rect(Rect2(p, Vector2(s, s)), Color(1.0, 0.55, 0.2, float(q.a) * fade))
	for s in _smoke:
		if _smoke_tex.is_empty():
			break
		var tex: Texture2D = _smoke_tex[int(s.i) % _smoke_tex.size()]
		var u: float = s.u
		var sz := Vector2(tex.get_size()) * float(s.s) * lerpf(0.8, 1.7, u)
		var a := 0.34 * sin(PI * u)
		var p: Vector2 = s.p
		draw_texture_rect(tex, Rect2(p - Vector2(sz.x * 0.5, sz.y), sz), false, Color(1, 1, 1, a))
	for v in _vultures:
		_draw_vulture(v)

## Mismo ciclo de aleteo que en el login: planea (cuadro 0) y bate las alas (cuadros 1 a 3).
func _draw_vulture(v: Dictionary) -> void:
	var ang: float = v.a
	var r: Vector2 = v.r
	var c: Vector2 = v.c
	var ph: float = v.ph
	var pos := c + Vector2(cos(ang) * r.x, sin(ang) * r.y + sin(_t * 1.6 + ph) * 2.0)
	var vel_x := -sin(ang) * r.x * float(v.sp)
	var u := fposmod(_t * 5.0 * (0.85 + 0.3 * fposmod(ph, 1.0)) + ph, 7.0)
	var frame := 0 if u < 4.0 else (1 if u < 5.0 else (2 if u < 6.0 else 3))
	var fw: int = v.fw
	var h: int = v.h
	var sc: float = v.scale
	var tex: Texture2D = v.tex
	var w := float(fw) * sc
	var hh := float(h) * sc
	var flip := vel_x < 0.0
	var rect := Rect2(pos.x + (w * 0.5 if flip else -w * 0.5), pos.y - hh * 0.5, -w if flip else w, hh)
	draw_texture_rect_region(tex, rect, Rect2(frame * fw, 0, fw, h), Color(1.0, 0.92, 0.92, 1.0))

# --- Hielo: nieve, carambanos y ojos -----------------------------------------------------------------

func _draw_ice() -> void:
	for q in _parts:
		var p: Vector2 = q.p
		var s: float = q.s
		draw_rect(Rect2(p, Vector2(s, s)), Color(0.9, 0.97, 1.0, float(q.a) * 0.8))
	if _ic_tex == null or _ic.is_empty():
		return
	var x: float = _ic.x
	var t: float = _ic.t
	match String(_ic.state):
		"warn":                       # polvo y esquirlas que se desprenden del techo antes de caer
			for i in 7:
				var yy := 2.0 + fposmod(t * (14.0 + i * 3.0) + i * 5.0, 22.0)
				var xx := x + sin(float(i) * 2.1 + t * 9.0) * 7.0
				draw_rect(Rect2(xx, yy, 1.5, 1.5), Color(0.9, 0.97, 1.0, 0.55 * minf(t * 3.0, 1.0)))
		"fall":
			draw_texture(_ic_tex, Vector2(x - _ic_tex.get_width() * 0.5, float(_ic.y)))
		"hit":
			if _splash_tex != null:
				var k := clampf(t / 0.45, 0.0, 1.0)
				var sz := Vector2(_splash_tex.get_size()) * lerpf(0.7, 1.0, k)
				var a := 1.0 - smoothstep(0.25, 0.6, t)
				draw_texture_rect(_splash_tex, Rect2(x - sz.x * 0.5, GROUND_Y - sz.y + 2.0, sz.x, sz.y), false, Color(1, 1, 1, a))
			if _debris_tex != null:
				var da := (1.0 - smoothstep(0.9, 1.5, t)) * smoothstep(0.1, 0.35, t)
				draw_texture(_debris_tex, Vector2(x - _debris_tex.get_width() * 0.5, GROUND_Y - _debris_tex.get_height() + 3.0),
						Color(1, 1, 1, da))

## Un par de ojos que se abre, parpadea y se cierra; cada par tiene su propio ritmo (sprite de referencia, aditivo).
func _draw_eyes_add(e: Dictionary, tint: Color, cell: int) -> void:
	if _eye_tex == null:
		return
	var period: float = e.period
	var on: float = e.on
	var cyc := fposmod(_t + float(e.ph), period)
	if cyc > on:
		return
	var u := cyc / on
	var a := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.82, 1.0, u))
	var blink := 0.12 if fposmod(_t * 0.9 + float(e.ph), 3.3) > 3.1 else 1.0
	var c: Vector2 = e.p
	var w := float(_eye_w) * 0.7
	var h := float(_eye_h) * 0.7 * blink
	_add.draw_texture_rect_region(_eye_tex, Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h),
			Rect2(cell * _eye_w, 0, _eye_w, _eye_h), Color(tint.r, tint.g, tint.b, a))

# --- Pantano: luciernagas, esporas y ojos ---------------------------------------------------------

func _draw_swamp() -> void:
	for q in _parts:
		if float(q.sp) < 0.55:
			var base: Vector2 = q.p
			var ph: float = q.ph
			var p := base + Vector2(sin(_t * 0.5 + ph) * 22.0, cos(_t * 0.7 + ph * 1.3) * 14.0)
			var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 2.1 + ph))
			draw_rect(Rect2(p, Vector2(1.5, 1.5)), Color(0.6, 1.0, 0.4, 0.4 * a))

# --- Desierto: tornados y tormenta de arena ---------------------------------------------------------

func _draw_sand() -> void:
	var g := _storm_gust()
	var m := _storm_mul()
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.95, 0.78, 0.45, 0.03 + 0.09 * g))
	for i in 3:
		var cx := 760.0 - fposmod(_t * (14.0 + i * 7.0) * m + i * 230.0, 900.0)
		var cy := 205.0 + i * 42.0
		var w := 150.0 + i * 20.0
		var h := 16.0 + g * 12.0
		var pts := PackedVector2Array()
		for k in 18:
			var a := TAU * k / 18.0
			pts.append(Vector2(cx + cos(a) * w, cy + sin(a) * h))
		draw_colored_polygon(pts, Color(0.98, 0.82, 0.5, 0.05 + 0.08 * g))
	if _tor_tex != null:
		var fw := _tor_tex.get_width() / 6
		var fh := _tor_tex.get_height()
		for tn in _tors:
			var sc: float = tn.sc
			var frame := int(_t * 6.0 + float(tn.ph)) % 6
			var w := float(fw) * sc
			var h := float(fh) * sc
			var p := Vector2(float(tn.x), float(tn.y))
			var shadow := PackedVector2Array()
			for k in 14:
				var a := TAU * k / 14.0
				shadow.append(p + Vector2(cos(a) * w * 0.4, sin(a) * 3.0 * sc))
			draw_colored_polygon(shadow, Color(0.35, 0.22, 0.08, 0.16 * float(tn.a)))
			draw_texture_rect_region(_tor_tex, Rect2(p.x - w * 0.5, p.y - h, w, h), Rect2(frame * fw, 0, fw, fh),
					Color(1, 1, 1, float(tn.a) * (0.75 + 0.25 * g)))
	for q in _parts:
		var p: Vector2 = q.p
		var ln := (4.0 + float(q.s) * 5.0) * (0.7 + 0.3 * m)
		draw_rect(Rect2(p, Vector2(ln, 1.0 if float(q.s) < 1.7 else 2.0)),
				Color(0.98, 0.87, 0.6, float(q.a) * (0.35 + 0.65 * g)))

# --- Luces aditivas: resplandor del rio de lava, ojos y luciernagas -----------------------------------

func _draw_add() -> void:
	match kind:
		0:
			# el rio de lava respira: resplandor ancho sobre el suelo donde salen las fichas
			var k := 0.6 + 0.4 * sin(_t * 1.3)
			var river := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				river.append(Vector2(330.0 + cos(a) * 150.0, 262.0 + sin(a) * 22.0))
			_add.draw_colored_polygon(river, Color(1.0, 0.38, 0.08, 0.055 * k))
		1:
			for e in _eyes:
				_draw_eyes_add(e, Color(1.0, 1.0, 1.0), 4)
		2:
			for e in _eyes:
				_draw_eyes_add(e, Color(1.0, 1.0, 0.7), 3)
			for q in _parts:
				if float(q.sp) < 0.55 or _ff_tex == null:
					continue
				var base: Vector2 = q.p
				var ph: float = q.ph
				var p := base + Vector2(sin(_t * 0.5 + ph) * 22.0, cos(_t * 0.7 + ph * 1.3) * 14.0)
				var a := 0.35 + 0.65 * (0.5 + 0.5 * sin(_t * 2.1 + ph))
				if _glow_tex != null:
					_add.draw_texture_rect(_glow_tex, Rect2(p - Vector2(15, 15), Vector2(30, 30)), false, Color(0.9, 1.0, 0.4, 0.5 * a))
				var frame := int(_t * 2.5 + ph) % 4
				_add.draw_texture_rect_region(_ff_tex, Rect2(p - Vector2(11, 11), Vector2(22, 22)),
						Rect2(frame * 48, 0, 48, 48), Color(1, 1, 1, 0.55 + 0.45 * a))
