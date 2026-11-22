extends Node2D
## Chunk del suelo (17 columnas de 32 px). `number_part` es su lugar en la franja
## (0 = izquierda). BoardView lo asigna según el asiento; el setter recoloca el
## chunk al momento. Solo se mueve este nodo: sus hijos (TileMap/TileMapLayer,
## PrisonCell, ArrivalsCorridor) heredan la posición, así no se duplica el desplazamiento.

const TILE_TRANSFORM_SIZE := 32
const NUM_TILES := 17

@export var number_part := 0:
	set(value):
		number_part = value
		_apply_offset()

func _ready() -> void:
	_apply_offset()

func _apply_offset() -> void:
	position.x = number_part * TILE_TRANSFORM_SIZE * NUM_TILES
