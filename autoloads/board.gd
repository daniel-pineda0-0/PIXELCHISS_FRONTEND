extends Node
## Tablero de la partida, tal como lo define el servidor (GET /api/game/board).
## Se pide una sola vez y se guarda: no cambia durante la partida.
##
## Los seguros, la trivia y las rutas se leen del servidor, no se escriben aquí.
## Para saber en qué casilla está una ficha se usa siempre `cell_at_progress`,
## nunca una fórmula local. Lo único fijo es la versión de tablero que el
## cliente sabe dibujar (EXPECTED_*): si el servidor cambia de layout, el mapa
## de coordenadas de Godot hay que rehacerlo y aquí se avisa en vez de pintar mal.

signal finished(ok: bool)

const EXPECTED_LAYOUT := "v4-100"
const EXPECTED_CELLS := 100

const KIND_TRACK := "TRACK"              # recorrido común (0-67)
const KIND_FINISH_LANE := "FINISH_LANE"  # corredor final privado (68-99)
const KIND_CROWN := "CROWN"              # corona, última casilla de cada corredor
# Las casas no son casillas: una ficha HOME tiene position null y progress -1.

var is_loaded := false
var load_error := ""             # motivo legible si ensure_loaded() devolvió false
var layout := ""                 # versión del tablero, p. ej. "v4-100"
var cell_count := 0
var track_count := 0             # casillas del recorrido común
var cells: Array = []            # [{id, kind, safe, protectedCell, capacity}]
var safe_ids: Array = []
var trivia_ids: Array = []

var _by_id := {}                 # int id -> Dictionary
var _routes := {}                # int asiento -> Array (por ficha) de Array[int]
var _loading := false

## Descarga el tablero si aún no está. Devuelve true si queda disponible.
func ensure_loaded() -> bool:
	if is_loaded:
		return true
	if _loading:
		return await finished
	_loading = true
	load_error = ""
	var r: Dictionary = await Api.request(HTTPClient.METHOD_GET, "/api/game/board")
	var ok: bool = r.ok and r.data is Dictionary and _parse(r.data)
	if ok and not _is_supported():
		ok = false
		load_error = "El servidor usa otro tablero (%s, %d casillas); esta versión del juego espera %s" % [
				layout, cell_count, EXPECTED_LAYOUT]
		push_error("Board: " + load_error)
	elif not ok:
		load_error = "No se pudo cargar el tablero"
	_loading = false
	is_loaded = ok
	finished.emit(ok)
	return ok

# --- Consultas ---

## Casilla por id ({} si no existe).
func cell(id: int) -> Dictionary:
	return _by_id.get(id, {})

func is_safe(id: int) -> bool:
	return id in safe_ids

func is_trivia(id: int) -> bool:
	return id in trivia_ids

## Ids físicos que recorre la ficha `piece_number` del `seat`, por progreso.
## route[progreso] es el id de casilla; [] si no hay ruta.
func route(seat: int, piece_number: int) -> Array:
	var per_piece: Array = _routes.get(seat, [])
	if piece_number < 0 or piece_number >= per_piece.size():
		return []
	return per_piece[piece_number]

## Id de casilla de una ficha en `progress`; -1 si no tiene casilla (en casa
## o fuera de ruta).
func cell_at_progress(seat: int, piece_number: int, progress: int) -> int:
	var path := route(seat, piece_number)
	if progress < 0 or progress >= path.size():
		return -1
	return path[progress]

## Salida de un color (v4-100: 5, 22, 39, 56): un seguro de capacidad 4. El JSON del
## tablero no trae un campo aparte, así que se distingue de un seguro normal (capacidad
## 2) por su capacidad.
func is_exit(id: int) -> bool:
	var c := cell(id)
	return c.get("kind") == KIND_TRACK and bool(c.get("safe", false)) and int(c.get("capacity", 0)) >= 4

## Progreso de la corona. La ruta tiene un id por progreso; la salida aparece en el
## progreso 0 y otra vez en el 68 (vuelta completa), así que NUNCA se deduce el
## progreso de la posición: se usa `piece.progress` del estado.
func last_progress(seat: int, piece_number: int) -> int:
	return route(seat, piece_number).size() - 1

# --- Interno ---

func _is_supported() -> bool:
	return layout == EXPECTED_LAYOUT and cell_count == EXPECTED_CELLS and cells.size() == EXPECTED_CELLS

func _parse(d: Dictionary) -> bool:
	if not (d.get("cells") is Array and d.get("routes") is Dictionary):
		push_error("Board: respuesta sin cells/routes")
		return false
	layout = str(d.get("layout", ""))
	cells = d.cells
	cell_count = int(d.get("cellCount", cells.size()))
	safe_ids = _ints(d.get("safe", []))
	trivia_ids = _ints(d.get("trivia", []))

	_by_id.clear()
	track_count = 0
	for c in cells:
		_by_id[int(c.id)] = c
		if c.get("kind") == KIND_TRACK:
			track_count += 1

	_routes.clear()
	for seat_key in d.routes:
		var per_piece: Array = []
		for path in d.routes[seat_key]:
			per_piece.append(_ints(path))
		_routes[int(seat_key)] = per_piece

	if cell_count != cells.size():
		push_warning("Board: cellCount=%d pero hay %d casillas" % [cell_count, cells.size()])
	return not _routes.is_empty()

## JSON entrega los números como float; los ids se manejan como int.
func _ints(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(int(v))
	return out
