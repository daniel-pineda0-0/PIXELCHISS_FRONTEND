class_name BoardMap
extends RefCounted
## Traduce los ids de casilla del servidor (0-99, tablero v3-100) a celdas de los
## dos dibujos del tablero: la franja del mundo (un chunk por asiento) y el minimapa.
## Solo datos y cuentas. Para saber en qué casilla está una ficha: piece_cell_id().
##
## Ids: 0-67 recorrido (sector de 17 por asiento; la salida del asiento es 17*asiento,
## y es también donde acaba la vuelta). 68-99 corredores (8 por asiento, la corona es
## el último). Las casas no son casillas: una ficha HOME se dibuja en minimap_home() o
## en la celda de PrisonCell de su chunk.

const SEATS := 4
const SECTOR := 17
const TRACK_COUNT := 68
const LANE_LEN := 8
const LANE_BASE := 68
const CELL_COUNT := 100

## Rojo, azul, verde, amarillo (asientos 0-3).
const SEAT_COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.45), Color(0.5, 0.65, 1.0),
	Color(0.5, 0.95, 0.55), Color(1.0, 0.92, 0.4),
]

# --- Minimapa -----------------------------------------------------------------

const MINIMAP_PLAYER1_CARCEL: Array[Vector2i] = [
	Vector2i(4, -5), Vector2i(4, -4), Vector2i(5, -5), Vector2i(5, -4)
]

const MINIMAP_PLAYER2_CARCEL: Array[Vector2i] = [
	Vector2i(-4, -6), Vector2i(-4, -7), Vector2i(-5, -6), Vector2i(-5, -7)
]

const MINIMAP_PLAYER3_CARCEL: Array[Vector2i] = [
	Vector2i(-6, 2), Vector2i(-6, 3), Vector2i(-7, 2), Vector2i(-7, 3)
]

const MINIMAP_PLAYER4_CARCEL: Array[Vector2i] = [
	Vector2i(3, 4), Vector2i(3, 5), Vector2i(2, 4), Vector2i(2, 5)
]

const MINIMAP_ARRIVALS_CORRIDOR_P1: Array[Vector2i] = [
	Vector2i(8, -1), Vector2i(7, -1), Vector2i(6, -1), Vector2i(5, -1),
	Vector2i(4, -1), Vector2i(3, -1), Vector2i(2, -1), Vector2i(1, -1)
]

const MINIMAP_ARRIVALS_CORRIDOR_P2: Array[Vector2i] = [
	Vector2i(-1, -10), Vector2i(-1, -9), Vector2i(-1, -8), Vector2i(-1, -7),
	Vector2i(-1, -6), Vector2i(-1, -5), Vector2i(-1, -4), Vector2i(-1, -3)
]

const MINIMAP_ARRIVALS_CORRIDOR_P3: Array[Vector2i] = [
	Vector2i(-10, -1), Vector2i(-9, -1), Vector2i(-8, -1), Vector2i(-7, -1),
	Vector2i(-6, -1), Vector2i(-5, -1), Vector2i(-4, -1), Vector2i(-3, -1)
]

const MINIMAP_ARRIVALS_CORRIDOR_P4: Array[Vector2i] = [
	Vector2i(-1, 8), Vector2i(-1, 7), Vector2i(-1, 6), Vector2i(-1, 5),
	Vector2i(-1, 4), Vector2i(-1, 3), Vector2i(-1, 2), Vector2i(-1, 1)
]

const MINIMAP_TRACK: Array[Vector2i] = [
	Vector2i(9, -1), # seguro de entrada a corredor final de p1 (índice 0)
	Vector2i(9, -2),
	Vector2i(8, -2),
	Vector2i(7, -2),
	Vector2i(6, -2),
	Vector2i(5, -2), # salida de p1 (índice 5)
	Vector2i(4, -2),
	Vector2i(3, -2),
	Vector2i(2, -3),
	Vector2i(1, -4),
	Vector2i(0, -5),
	Vector2i(0, -6),
	Vector2i(0, -7), # seguro de p1 (índice 12)
	Vector2i(0, -8),
	Vector2i(0, -9),
	Vector2i(0, -10),
	Vector2i(0, -11),
	Vector2i(-1, -11), # seguro de entrada a corredor final de p2 (índice 17)
	Vector2i(-2, -11),
	Vector2i(-2, -10),
	Vector2i(-2, -9),
	Vector2i(-2, -8),
	Vector2i(-2, -7), # salida de p2 (índice 22)
	Vector2i(-2, -6),
	Vector2i(-2, -5),
	Vector2i(-3, -4),
	Vector2i(-4, -3),
	Vector2i(-5, -2),
	Vector2i(-6, -2),
	Vector2i(-7, -2), # seguro de p2 (índice 29)
	Vector2i(-8, -2),
	Vector2i(-9, -2),
	Vector2i(-10, -2),
	Vector2i(-11, -2),
	Vector2i(-11, -1), # seguro de entrada a corredor final de p3 (índice 34)
	Vector2i(-11, 0),
	Vector2i(-10, 0),
	Vector2i(-9, 0),
	Vector2i(-8, 0),
	Vector2i(-7, 0), # salida de p3 (índice 39)
	Vector2i(-6, 0),
	Vector2i(-5, 0),
	Vector2i(-4, 1),
	Vector2i(-3, 2),
	Vector2i(-2, 3),
	Vector2i(-2, 4),
	Vector2i(-2, 5), # seguro de p3 (índice 46)
	Vector2i(-2, 6),
	Vector2i(-2, 7),
	Vector2i(-2, 8),
	Vector2i(-2, 9),
	Vector2i(-1, 9), # seguro de entrada a corredor final de p4 (índice 51)
	Vector2i(0, 9),
	Vector2i(0, 8),
	Vector2i(0, 7),
	Vector2i(0, 6),
	Vector2i(0, 5), # salida de p4 (índice 56)
	Vector2i(0, 4),
	Vector2i(0, 3),
	Vector2i(1, 2),
	Vector2i(2, 1),
	Vector2i(3, 0),
	Vector2i(4, 0),
	Vector2i(5, 0), # seguro de p4 (índice 63)
	Vector2i(6, 0),
	Vector2i(7, 0),
	Vector2i(8, 0),
	Vector2i(9, 0) # (índice 67 - total 68 casillas)
]

## Por asiento (0 = p1 ... 3 = p4).
const MINIMAP_HOMES: Array = [
	MINIMAP_PLAYER1_CARCEL, MINIMAP_PLAYER2_CARCEL,
	MINIMAP_PLAYER3_CARCEL, MINIMAP_PLAYER4_CARCEL,
]
const MINIMAP_LANES: Array = [
	MINIMAP_ARRIVALS_CORRIDOR_P1, MINIMAP_ARRIVALS_CORRIDOR_P2,
	MINIMAP_ARRIVALS_CORRIDOR_P3, MINIMAP_ARRIVALS_CORRIDOR_P4,
]

# --- Franja del mundo (un chunk de player_ground por asiento) -----------------

const PLAYER_GROUND_TRACK: Array[Vector2i] = [
	Vector2i(7, 3), # SEGURO DE ENTRADA A CORREDOR (índice 0)
	Vector2i(6, 3),
	Vector2i(5, 3),
	Vector2i(4, 3),
	Vector2i(3, 3),
	Vector2i(2, 3), # salida (índice 5)
	Vector2i(1, 3),
	Vector2i(0, 3),
	Vector2i(-1, 3),
	Vector2i(-2, 3),
	Vector2i(-3, 3),
	Vector2i(-4, 3),
	Vector2i(-5, 3), # seguro (índice 12)
	Vector2i(-6, 3),
	Vector2i(-7, 3),
	Vector2i(-8, 3),
	Vector2i(-9, 3)  # (índice 16)
]

const PLAYER_GROUND_ARRIVALS_CORRIDOR: Array[Vector2i] = [
	Vector2i(7, 4),
	Vector2i(6, 4),
	Vector2i(5, 4),
	Vector2i(4, 4),
	Vector2i(3, 4),
	Vector2i(2, 4),
	Vector2i(1, 4),
	Vector2i(0, 4)
]

# --- Orden de los chunks en la franja ------------------------------------------
# Dentro de un chunk los ids bajan hacia la izquierda (id 0 en la columna 7, id 16
# en la -9). Para que el id 17 quede pegado al 16, el chunk del asiento siguiente
# va a la IZQUIERDA: asiento 0 en el slot 3 (derecha) ... asiento 3 en el slot 0.
# Solo el paso 67 -> 0 (cierre de la vuelta) es un salto.

static func slot_of_seat(seat: int) -> int:
	return SEATS - 1 - seat

static func seat_of_slot(slot: int) -> int:
	return SEATS - 1 - slot

# --- Id de casilla -> celda ----------------------------------------------------

## División entera hacia abajo, sin la advertencia de GDScript por descartar decimales.
static func _div(a: int, b: int) -> int:
	return floori(float(a) / float(b))

static func is_valid_id(id: int) -> bool:
	return id >= 0 and id < CELL_COUNT

## Franja: {"seat": chunk (= asiento del sector), "cell": Vector2i}; {} si el id no existe.
static func strip_cell(id: int) -> Dictionary:
	if id >= 0 and id < TRACK_COUNT:
		return {"seat": _div(id, SECTOR), "cell": PLAYER_GROUND_TRACK[id % SECTOR]}
	if id >= LANE_BASE and id < CELL_COUNT:
		var lane := id - LANE_BASE
		return {"seat": _div(lane, LANE_LEN), "cell": PLAYER_GROUND_ARRIVALS_CORRIDOR[lane % LANE_LEN]}
	return {}

## Minimapa: celda del id físico. Usar is_valid_id() antes.
static func minimap_cell(id: int) -> Vector2i:
	if id >= 0 and id < TRACK_COUNT:
		return MINIMAP_TRACK[id]
	if id >= LANE_BASE and id < CELL_COUNT:
		var lane := id - LANE_BASE
		return MINIMAP_LANES[_div(lane, LANE_LEN)][lane % LANE_LEN]
	return Vector2i.ZERO

## Casa de la ficha `number` del `seat` en el minimapa.
static func minimap_home(seat: int, number: int) -> Vector2i:
	var cells: Array = MINIMAP_HOMES[posmod(seat, SEATS)]
	return cells[posmod(number, cells.size())]

# --- Fichas del snapshot --------------------------------------------------------

## Asiento dueño de la ficha (-1 si no se sabe).
static func seat_of_piece(piece: Dictionary) -> int:
	var who: Dictionary = GameNet.player(str(piece.get("ownerId", "")))
	if who.has("seat"):
		return int(who.seat)
	var parts := str(piece.get("id", "")).split("-")   # seat-{seat}-piece-{n}
	if parts.size() >= 4 and parts[0] == "seat":
		return int(parts[1])
	return -1

static func is_home(piece: Dictionary) -> bool:
	return str(piece.get("status", "")) == "HOME"

## Id de casilla de una ficha; -1 si está en casa o no se puede resolver.
static func piece_cell_id(piece: Dictionary, seat: int) -> int:
	if is_home(piece):
		return -1
	var pos: Variant = piece.get("position")
	if pos != null:
		return int(pos)
	if not Board.is_loaded:
		return -1
	return Board.cell_at_progress(seat, int(piece.get("number", 0)), int(piece.get("progress", -1)))
