class_name BurstEffect
extends Node2D
## Destello breve: captura (rojo), soplo (naranja) o coronación (dorado). Se borra solo.

@onready var _core: Sprite2D = %Core

func play(tint := Color(1.0, 0.3, 0.3)) -> void:
	_core.modulate = Color(tint, 0.8)
	scale = Vector2(0.4, 0.4)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.8, 1.8), 0.4)
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)
