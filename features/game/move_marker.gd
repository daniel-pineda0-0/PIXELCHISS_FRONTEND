class_name MoveMarker
extends Node2D
## Marcadores dibujados sobre el tablero (mundo):
##  - TARGET: destino de un movimiento legal, con el valor del dado.
##  - HALO: aro bajo una ficha (azul = protegida, amarillo = se puede mover, blanco = elegida,
##    dorado = coronada).
##  - BURST: destello breve (captura en rojo, coronación en dorado).

enum Kind { TARGET, HALO, BURST }

var kind := Kind.TARGET
var label := ""
var color := Color.WHITE
var move: Dictionary = {}           # elemento de legalMoves que ejecuta este marcador
var chunk := 0                      # TARGET: chunk y celda donde se dibuja
var cell := Vector2i.ZERO

var safe_cell := false:             # HALO: la ficha está protegida (seguro o corredor)
	set(value):
		safe_cell = value
		queue_redraw()
var movable := false:               # HALO: la ficha se puede mover ahora
	set(value):
		movable = value
		queue_redraw()
var crowned := false:               # HALO: ficha ya coronada (US-015)
	set(value):
		crowned = value
		queue_redraw()
var selected := false:              # HALO: es la ficha elegida
	set(value):
		selected = value
		queue_redraw()

var _time := 0.0

## Destello que se expande y se apaga; se borra solo.
static func burst(parent: Node, world_pos: Vector2, tint := Color(1.0, 0.3, 0.3)) -> void:
	var fx := MoveMarker.new()
	fx.kind = Kind.BURST
	fx.color = tint
	parent.add_child(fx)
	fx.global_position = world_pos
	fx.scale = Vector2(0.4, 0.4)
	var tween := fx.create_tween()
	tween.set_parallel(true)
	tween.tween_property(fx, "scale", Vector2(1.8, 1.8), 0.4)
	tween.tween_property(fx, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(fx.queue_free)

func _process(delta: float) -> void:
	_time += delta
	if kind == Kind.TARGET or (kind == Kind.HALO and movable):
		queue_redraw()

func _draw() -> void:
	match kind:
		Kind.TARGET:
			var radius := 11.0 + sin(_time * 6.0) * 1.2
			draw_circle(Vector2.ZERO, radius, Color(color, 0.35))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(color, 0.95), 2.0)
			var font := ThemeDB.fallback_font
			draw_string_outline(font, Vector2(-8, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 16, 12, 4, Color.BLACK)
			draw_string(font, Vector2(-8, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color.WHITE)
		Kind.HALO:
			draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.45))    # aro aplastado a los pies
			if crowned:
				draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.25, 0.95), 2.0)
			elif safe_cell:
				draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 32, Color(0.4, 0.8, 1.0, 0.9), 2.0)
			if movable:
				var alpha := 0.55 + 0.45 * sin(_time * 5.0)
				draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.2, alpha), 2.0)
			if selected:
				draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(1, 1, 1, 1), 3.0)
		Kind.BURST:
			draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, Color(1, 1, 1, 1), 3.0)
			draw_circle(Vector2.ZERO, 8.0, Color(color, 0.8))
