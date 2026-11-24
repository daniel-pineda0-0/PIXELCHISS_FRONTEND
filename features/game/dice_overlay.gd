class_name DiceOverlay
extends Control
## Lanzamiento de dados a pantalla completa: los dos dados caen desde arriba, rebotan con sombra,
## giran, parpadean caras y se asientan en el valor del servidor con un destello (dorado si son pares).
## Debajo, quien tiro y la suma. Solo dibuja: no recibe clics. DICE_TIME / SETTLE vienen de RollHold.

const SHEET := preload("res://service/assets/ui/icons/dice_sprites.png")
const FONT := preload("res://service/assets/ui/theme/PressStart2P.ttf")
const FACE := 16.0
const SCALE := 5.0
const GOLD := Color(1.0, 0.85, 0.25)

var _values: Array = []
var _label := ""
var _color := Color.WHITE
var _t := 99.0
var _seeds: Array[float] = [0.0, 0.0]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 50
	set_process(false)
	visible = false

func play(values: Array, who_label: String, color: Color) -> void:
	if values.size() < 2:
		return
	_values = values
	_label = who_label
	_color = color
	_t = 0.0
	_seeds = [randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)]
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	if _t > RollHold.DURATION:
		visible = false
		set_process(false)
	queue_redraw()

## 0..1 del vuelo; con rebotes decrecientes (3). Devuelve la altura sobre el suelo (0 = apoyado).
static func _bounce(u: float) -> float:
	if u >= 1.0:
		return 0.0
	# tres arcos: el primero alto (caida), luego dos rebotes cada vez mas bajos
	var edges: Array[float] = [0.0, 0.46, 0.74, 0.92, 1.0]
	var peaks: Array[float] = [1.0, 0.34, 0.12, 0.04]
	for i in 4:
		if u < edges[i + 1]:
			var k := (u - edges[i]) / (edges[i + 1] - edges[i])
			var arc := 4.0 * k * (1.0 - k) if i > 0 else 1.0 - k * k    # el primero arranca arriba y cae
			return arc * peaks[i]
	return 0.0

func _draw() -> void:
	var size_px := get_viewport_rect().size if get_viewport() != null else size
	var floor_y := size_px.y * 0.46
	var cx := size_px.x * 0.5
	var fly := clampf(_t / RollHold.DICE_TIME, 0.0, 1.0)
	var settled := _t >= RollHold.DICE_TIME
	var fade := 1.0 - clampf((_t - (RollHold.DURATION - 0.35)) / 0.35, 0.0, 1.0)
	var doubles := int(_values[0]) == int(_values[1])
	var accent := GOLD if doubles else _color.lerp(Color.WHITE, 0.35)
	# velo suave que oscurece un poco el tablero para que los dados destaquen
	draw_rect(Rect2(Vector2.ZERO, size_px), Color(0.0, 0.0, 0.04, 0.38 * fade * clampf(_t / 0.18, 0.0, 1.0)))
	var d := FACE * SCALE
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var land_x := cx + side * (d * 0.72 + 6.0)
		var start_x := cx + side * size_px.x * (0.34 + 0.08 * _seeds[i])
		var x := lerpf(start_x, land_x, 1.0 - pow(1.0 - fly, 2.2))
		var h := _bounce(fly) * size_px.y * 0.52
		var pos := Vector2(x, floor_y - h)
		var spin := (1.0 - fly) * (7.0 + 3.0 * absf(_seeds[i])) * side * -1.0
		var squash := 1.0
		# aplastamiento al tocar el suelo (cada rebote)
		for edge: float in [0.46, 0.74, 0.92]:
			var near := absf(fly - edge)
			if near < 0.025:
				squash = 1.0 - 0.22 * (1.0 - near / 0.025)
		# sombra: mas chica y tenue cuanto mas alto
		var sh := clampf(1.0 - h / (size_px.y * 0.55), 0.25, 1.0)
		draw_set_transform(Vector2(x, floor_y + d * 0.5 + 4.0), 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, d * 0.62 * sh, Color(0, 0, 0, 0.45 * sh * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# cara: parpadea hasta el ultimo rebote y luego queda el valor real
		var face := clampi(int(_values[i]) - 1, 0, 5)
		if fly < 0.9:
			face = int(floor(_t * 18.0 + i * 3.0)) % 6
		draw_set_transform(pos, spin, Vector2(1.0 / squash, squash))
		var dst := Rect2(-d * 0.5 - 3.0, -d * 0.5 - 3.0, d + 6.0, d + 6.0)
		draw_rect(dst, Color(0.02, 0.02, 0.05, 0.85 * fade))                       # marco oscuro
		draw_rect(Rect2(dst.position + Vector2(2, 2), dst.size - Vector2(4, 4)), Color(accent, 0.0 if not settled else 0.9 * fade), false, 2.0)
		draw_texture_rect_region(SHEET, Rect2(-d * 0.5, -d * 0.5, d, d), Rect2(face * FACE, 0.0, FACE, FACE), Color(1, 1, 1, fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# destello y anillo al asentarse
	if settled:
		var u := clampf((_t - RollHold.DICE_TIME) / 0.45, 0.0, 1.0)
		for side: float in [-1.0, 1.0]:
			var p := Vector2(cx + side * (d * 0.72 + 6.0), floor_y)
			draw_arc(p, d * 0.5 + 90.0 * u, 0.0, TAU, 48, Color(accent, 0.7 * (1.0 - u) * fade), 3.0)
		if doubles:
			for r in 10:
				var a := TAU * r / 10.0 + _t * 0.6
				var p0 := Vector2(cx, floor_y) + Vector2(cos(a), sin(a)) * (d * 1.5)
				var p1 := Vector2(cx, floor_y) + Vector2(cos(a), sin(a)) * (d * 1.5 + 26.0 + 10.0 * sin(_t * 8.0 + r))
				draw_line(p0, p1, Color(GOLD, 0.65 * fade), 3.0)
	# quien tiro y la suma
	if settled:
		var total := int(_values[0]) + int(_values[1])
		var text := "%s  %d + %d = %d" % [_label, int(_values[0]), int(_values[1]), total]
		var ty := floor_y + d * 0.5 + 44.0
		var w := 360.0
		draw_rect(Rect2(cx - w * 0.5, ty - 16.0, w, 24.0), Color(0.03, 0.02, 0.05, 0.75 * fade))
		draw_rect(Rect2(cx - w * 0.5, ty - 16.0, w, 2.0), Color(accent, fade))
		draw_string_outline(FONT, Vector2(cx - w * 0.5, ty), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, 4, Color(0, 0, 0, fade))
		draw_string(FONT, Vector2(cx - w * 0.5, ty), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(accent.lerp(Color.WHITE, 0.4), fade))
