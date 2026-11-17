extends TileMap

@export var number_part:=0
const TILE_TRANSFORM_SIZE:=32
const NUM_TILES := 17

func _ready() -> void:
	position.x = number_part*TILE_TRANSFORM_SIZE*NUM_TILES
