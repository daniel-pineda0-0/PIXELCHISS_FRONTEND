extends Node2D
## Golpe de espada sobre una ficha que cae: arco blanco que barre, y la calavera sale volando.
## Se borra sola. Lo crea BoardView al soltar a la víctima de una captura.

const LIFE := 0.7
var tint := Color.WHITE
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := _t / LIFE
	# arco de la espada: barre de arriba-izquierda a abajo-derecha en el primer tercio
	var sweep := clampf(k / 0.3, 0.0, 1.0)
	if k < 0.45:
		var a0 := deg_to_rad(-150.0)
		var a1 := lerpf(a0, deg_to_rad(-20.0), sweep)
		draw_arc(Vector2(0, -2), 22.0, a0, a1, 14, Color(1, 1, 1, 1.0 - k / 0.45), 3.0)
		draw_arc(Vector2(0, -2), 17.0, a0, a1, 14, Color(tint.r, tint.g, tint.b, (1.0 - k / 0.45) * 0.8), 2.0)
	# la cabeza sale disparada en parábola y cae
	if k > 0.2:
		var h := (k - 0.2) / 0.8
		var pos := Vector2(34.0 * h, -22.0 - 40.0 * h + 70.0 * h * h)
		var spin := h * 9.0
		draw_circle(pos, 5.0, Color(0.93, 0.93, 0.88, 1.0 - maxf(0.0, h - 0.75) * 4.0))
		draw_circle(pos + Vector2(-1.5, -0.5 + sin(spin)), 1.0, Color(0.1, 0.1, 0.1))
		draw_circle(pos + Vector2(1.5, -0.5 + sin(spin)), 1.0, Color(0.1, 0.1, 0.1))
