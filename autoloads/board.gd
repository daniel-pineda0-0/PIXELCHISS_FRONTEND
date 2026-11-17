extends Node
## Tablero de la partida, tal como lo define el servidor (GET /api/game/board).
## Se pide una sola vez y se guarda: no cambia durante la partida.
##
## Nada de la geometría está escrito aquí a propósito (nº de casillas, seguros,
## trivia, rutas): el servidor puede cambiar el tablero (p. ej. de 96 a 100
## casillas) y el cliente lo sigue sin tocar código. Para saber dónde dibujar
## una ficha se usa siempre `cell_at_progress`, nunca una fórmula local.

signal finished(ok: bool)

const KIND_TRACK := "TRACK"              # recorrido común
const KIND_EXIT := "EXIT"                # salida de cada ficha
const KIND_FINISH_LANE := "FINISH_LANE"  # corredor hacia la meta
const KIND_CROWN := "CROWN"              # meta / corona

var is_loaded := false
var layout := ""                 # versión del tablero, p. ej. "v1"
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
	var r: Dictionary = await Api.request(HTTPClient.METHOD_GET, "/api/game/board")
	var ok: bool = r.ok and r.data is Dictionary and _parse(r.data)
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

## Cuántos pasos tiene la ruta (progreso máximo = corona).
func last_progress(seat: int, piece_number: int) -> int:
	return route(seat, piece_number).size() - 1

# --- Interno ---

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
