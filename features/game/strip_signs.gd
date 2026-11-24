extends Node2D
## Dibujo del suelo de un chunk: casillas con la textura de su color (normal, SALIDA con runa,
## SEGURO con escudo), la franja de ladrillo con sus rotulos y el suelo de debajo, hecho con la misma
## piedra de las casillas (mas oscura, fundida a negro) para que no se vea cortado.
##
## La casilla de entrada al corredor final (BoardMap.stairs_index(): el SEGURO del inicio del sector, cinco casillas
## antes de la salida del color) es una compuerta: cuando una ficha lista para bajar llega o se detiene ahi, la casilla
## se parte en dos y deja ver la escalera de bajada
## (hatch_<n>.png: cuadro 0 cerrado ... cuadro 3 abierto). BoardView avisa con set_open().
## Es hijo del chunk (no del TileMap, que se oculta) y trabaja en las mismas coordenadas locales
## que el TileMap del suelo. Las fichas en casa NO se dibujan aqui: viven en HomeCrowd, en el fondo.

const FONT := preload("res://service/assets/ui/theme/PressStart2P.ttf")
const HOME_CROWD := preload("res://features/game/home_crowd.gd")
const TILE_SIZE := 32.0
const BAND_H := 14.0
const FLOOR_H := 40.0                      # alto de la textura del suelo (ground_<n>.png)
const HATCH_FRAMES := 4                    # hatch_<n>.png: el ultimo cuadro es la escalera ya abierta
const HATCH_SPEED := 6.0                   # cuadros por segundo al abrir (menos al cerrar)
## Iconos de SEGURO y SALIDA: van SOBRE una casilla normal (service/assets/game/tiles/ov_*.png), asi todas las
## casillas miden y se ven igual y el icono no parece "otra casilla de otro tamano".
const OVERLAY_H := {"seguro": 24.0, "salida": 26.0}
const HATCH_HOLD := 0.45                   # segundos que sigue abierta tras irse la ficha
## indice de casilla dentro del sector -> clase
const KINDS := {0: "seguro", 5: "salida", 12: "seguro"}
const LABELS := {"seguro": "SEGURO", "salida": "SALIDA"}
## colores de la franja de ladrillo y del piso por asiento: rojo, azul, verde, dorado
const BAND := [Color(0.42, 0.22, 0.2), Color(0.25, 0.5, 0.68), Color(0.3, 0.42, 0.22), Color(0.72, 0.5, 0.28)]
const FLOOR := [Color(0.07, 0.03, 0.04), Color(0.03, 0.06, 0.12), Color(0.03, 0.07, 0.04), Color(0.1, 0.07, 0.04)]

var seat := 0
var ground: Node2D
var crowd: HomeCrowd
var _tiles := {}
var _hatch: Texture2D
var _overlays := {}                         # "seguro"/"salida" -> icono con transparencia (puede faltar)
var _drawn_t := -1.0
var _normals: Array[Texture2D] = []         # variantes de la casilla normal (a y su espejo b)
var _fringe: Texture2D                     # fleco que cuelga de la franja: carambanos, lava, lianas, arena
var _floor: Texture2D
var _open_target := false
var _open_t := 0.0                         # 0 cerrada ... 1 abierta
var _hold := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR     # las casillas se reducen: se ven mejor suavizadas
	for kind in ["normal", "salida", "seguro"]:
		_tiles[kind] = load("res://service/assets/game/tiles/tile_%d_%s.png" % [seat, kind])
	# "c" es la casilla "a" girada 180 grados (la luz queda de cabeza): no se usa. "b" es el espejo horizontal.
	for v in ["a", "b"]:
		var path := "res://service/assets/game/tiles/tile_%d_normal_%s.png" % [seat, v]
		_normals.append(load(path) if ResourceLoader.exists(path) else _tiles["normal"])
	for kind in ["seguro", "salida"]:
		var opath := "res://service/assets/game/tiles/ov_%s_%d.png" % [kind, seat]
		if ResourceLoader.exists(opath):
			_overlays[kind] = load(opath)
	var fpath := "res://service/assets/game/tiles/fringe_%d.png" % seat
	if ResourceLoader.exists(fpath):
		_fringe = load(fpath)
	_hatch = load("res://service/assets/game/hatch_%d.png" % seat)
	_floor = load("res://service/assets/game/ground_%d.png" % seat)
	if not Board.finished.is_connected(_on_board_loaded):
		Board.finished.connect(_on_board_loaded)          # si la casilla de la escalera difiere del valor de respaldo
	crowd = HOME_CROWD.new()
	crowd.seat = seat
	crowd.ground = ground
	add_child(crowd)
	queue_redraw()

func _on_board_loaded(_ok: bool) -> void:
	queue_redraw()

## Abre o cierra la compuerta del seguro de la escalera (BoardView: hay una ficha encima o pasando).
func set_open(open: bool) -> void:
	if open:
		_hold = HATCH_HOLD
	_open_target = open or _hold > 0.0

func _process(delta: float) -> void:
	if not _open_target and _open_t <= 0.0:
		return
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_open_target = false
	var speed := HATCH_SPEED / float(HATCH_FRAMES - 1)
	_open_t = move_toward(_open_t, 1.0 if _open_target else 0.0, delta * speed * (1.0 if _open_target else 0.7))
	if not is_equal_approx(_open_t, _drawn_t):
		_drawn_t = _open_t
		queue_redraw()

func _draw() -> void:
	var first: Vector2 = ground.map_to_local(BoardMap.PLAYER_GROUND_TRACK[0])
	var last: Vector2 = ground.map_to_local(BoardMap.PLAYER_GROUND_TRACK[BoardMap.SECTOR - 1])
	var left := last.x - TILE_SIZE / 2.0 - 1.0
	var width := first.x - last.x + TILE_SIZE + 2.0
	var bottom := first.y + TILE_SIZE / 2.0              # borde inferior de las casillas
	# suelo: la piedra de las casillas, oscurecida y fundida a negro, y debajo el color mas oscuro
	var below := bottom + BAND_H
	draw_texture_rect(_floor, Rect2(left, below, width, FLOOR_H), true)
	draw_rect(Rect2(left, below + FLOOR_H, width, 500.0), FLOOR[seat])
	draw_rect(Rect2(left, below, width, 3.0), Color(0, 0, 0, 0.35))     # sombra bajo el ladrillo
	# franja de ladrillo
	draw_rect(Rect2(left, bottom, width, BAND_H), BAND[seat])
	for row in 2:
		var y := bottom + 7.0 * row
		draw_line(Vector2(left, y), Vector2(left + width, y), BAND[seat].darkened(0.35), 1.0)
		for bx in range(int(left) + (row % 2) * 16, int(left + width), 32):
			draw_line(Vector2(bx, y), Vector2(bx, y + 7.0), BAND[seat].darkened(0.35), 1.0)
	draw_rect(Rect2(left, bottom + BAND_H - 2.0, width, 2.0), BAND[seat].darkened(0.55))
	if _fringe != null:                       # fleco colgando de la franja sobre el suelo
		draw_texture_rect(_fringe, Rect2(left, below - 2.0, width, _fringe.get_height()), true)
	# casillas
	var stairs_index := BoardMap.stairs_index()
	for i in BoardMap.SECTOR:
		var c: Vector2 = ground.map_to_local(BoardMap.PLAYER_GROUND_TRACK[i])
		var kind: String = KINDS.get(i, "normal")
		var rect := Rect2(c.x - TILE_SIZE / 2.0, c.y - TILE_SIZE / 2.0, TILE_SIZE, TILE_SIZE)
		var layers := _cell_layers(i, kind, rect)
		var open := 0.0
		if i == stairs_index:
			open = _open_t
			if open > 0.01:                    # debajo de las dos mitades que se separan: la escalera
				var size := _hatch.get_height()
				draw_texture_rect_region(_hatch, rect, Rect2((HATCH_FRAMES - 1) * size, 0, size, size))
		_draw_layers(layers, rect, open)
		_draw_edges(rect, i)
		if LABELS.has(kind):
			var text: String = LABELS[kind]
			draw_string_outline(FONT, Vector2(c.x - 24.0, bottom + 11.0), text,
					HORIZONTAL_ALIGNMENT_CENTER, 48.0, 8, 4, Color.BLACK)
			draw_string(FONT, Vector2(c.x - 24.0, bottom + 11.0), text,
					HORIZONTAL_ALIGNMENT_CENTER, 48.0, 8, Color.WHITE)

## Capas de una casilla: [textura, rectangulo destino]. Seguro y salida = casilla normal + icono encima
## (si falta el icono, la casilla completa de siempre).
func _cell_layers(i: int, kind: String, rect: Rect2) -> Array:
	if kind == "normal" or not _overlays.has(kind):
		var tex: Texture2D = _tiles[kind]
		if kind == "normal":
			tex = _normals[(i * 7 + seat * 3 + floori(i / 3.0)) % _normals.size()]
		return [[tex, rect]]
	var base: Texture2D = _normals[(i * 7 + seat * 3 + floori(i / 3.0)) % _normals.size()]
	var icon: Texture2D = _overlays[kind]
	var h: float = OVERLAY_H[kind]
	var w := h * float(icon.get_width()) / float(icon.get_height())
	var center := rect.get_center() + Vector2(0.0, -1.0)
	return [[base, rect], [icon, Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))]]

## Dibuja las capas. Con open > 0 cada capa se parte por la mitad y las dos mitades se deslizan hacia los lados
## (se recortan en la casilla): la compuerta que se abre y deja ver la escalera.
func _draw_layers(layers: Array, cell: Rect2, open: float) -> void:
	for layer in layers:
		var tex: Texture2D = layer[0]
		var dest: Rect2 = layer[1]
		if open <= 0.001:
			draw_texture_rect(tex, dest, false)
			continue
		var shift := open * cell.size.x * 0.5
		var half := dest.size.x * 0.5
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		_draw_half(tex, Rect2(dest.position, Vector2(half, dest.size.y)), Rect2(0.0, 0.0, tw * 0.5, th), -shift, cell)
		_draw_half(tex, Rect2(dest.position + Vector2(half, 0.0), Vector2(half, dest.size.y)),
				Rect2(tw * 0.5, 0.0, tw * 0.5, th), shift, cell)

func _draw_half(tex: Texture2D, dest: Rect2, src: Rect2, shift: float, clip: Rect2) -> void:
	var moved := Rect2(dest.position + Vector2(shift, 0.0), dest.size)
	var inter := moved.intersection(clip)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return
	var f0 := (inter.position.x - moved.position.x) / moved.size.x
	var f1 := (inter.end.x - moved.position.x) / moved.size.x
	draw_texture_rect_region(tex, inter, Rect2(src.position.x + src.size.x * f0, src.position.y,
			src.size.x * (f1 - f0), src.size.y))

## Cortes finos entre casillas (una ranura oscura con un reflejo) y un tinte alterno muy suave, para contar
## las casillas de un vistazo sin romper el dibujo.
func _draw_edges(rect: Rect2, i: int) -> void:
	if i % 2 == 1:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.06))
	draw_rect(Rect2(rect.position, Vector2(1.0, rect.size.y)), Color(0.0, 0.0, 0.0, 0.4))
	draw_rect(Rect2(rect.position + Vector2(1.0, 0.0), Vector2(1.0, rect.size.y)), Color(1.0, 1.0, 1.0, 0.08))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), Color(1.0, 1.0, 1.0, 0.1))
	draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y - 1.0), Vector2(rect.size.x, 1.0)), Color(0.0, 0.0, 0.0, 0.25))
