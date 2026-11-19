class_name MinimapPiece
extends Node2D
## Ficha del minimapa: cuadrito de color con borde oscuro, centrado en su celda.

var color := Color.WHITE:
	set(value):
		color = value
		var sprite := get_node_or_null("Sprite2D") as Sprite2D    # ficha de game_pice.tscn
		if sprite != null:
			sprite.modulate = value
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-3, -3, 6, 6), Color(0, 0, 0, 0.9))
	draw_rect(Rect2(-2, -2, 4, 4), color)
