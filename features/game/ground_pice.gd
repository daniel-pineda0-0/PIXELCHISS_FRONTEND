extends Node2D
## Ficha del tablero: el esqueleto con cuernos, de un color por asiento. BoardView la anima por
## nombre con el AnimationPlayer (idl_ground_pice, walk_ground_pice, attack) y le dice el asiento
## y hacia donde camina.

const TEXTURES: Array[Texture2D] = [
	preload("res://service/assets/game/piece_red.png"),
	preload("res://service/assets/game/piece_blue.png"),
	preload("res://service/assets/game/piece_green.png"),
	preload("res://service/assets/game/piece_gold.png"),
]

@onready var sprite: Sprite2D = $Sprite

func set_seat(seat: int) -> void:
	sprite.texture = TEXTURES[posmod(seat, TEXTURES.size())]

## `direction` < 0 camina a la izquierda, > 0 a la derecha; con 0 conserva hacia donde miraba.
func face(direction: float) -> void:
	if absf(direction) > 0.5:
		sprite.flip_h = direction < 0.0
