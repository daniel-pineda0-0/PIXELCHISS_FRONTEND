extends Node2D
## Brasas que suben lentas desde el rio de lava. Pocas, naranjas y con balanceo,
## para que el fondo se sienta vivo sin parecer nieve.

const COUNT := 16
const X_RANGE := Vector2(250.0, 420.0)    # por donde corre el rio (coordenadas del fondo 640x360)
const Y_RANGE := Vector2(290.0, 355.0)

var _embers: Array = []

func _ready() -> void:
	for i in COUNT:
		_embers.append(_spawn(true))

func _spawn(scatter: bool) -> Dictionary:
	var life := randf_range(3.0, 6.0)
	return {
		"x": randf_range(X_RANGE.x, X_RANGE.y),
		"y": randf_range(Y_RANGE.x, Y_RANGE.y),
		"vy": randf_range(9.0, 22.0),
		"phase": randf() * TAU,
		"age": randf() * life if scatter else 0.0,
		"life": life,
		"size": 1.0 + float(randi() % 2),
	}

func _process(delta: float) -> void:
	for i in _embers.size():
		var e: Dictionary = _embers[i]
		e["age"] += delta
		if e["age"] >= e["life"]:
			_embers[i] = _spawn(false)
	queue_redraw()

func _draw() -> void:
	for e in _embers:
		var t: float = e["age"] / e["life"]
		var pos := Vector2(
			roundf(e["x"] + sin(e["age"] * 1.3 + e["phase"]) * 5.0),
			roundf(e["y"] - e["vy"] * e["age"]))
		var color := Color(1.0, lerpf(0.6, 0.25, t), 0.1, sin(t * PI) * 0.9)
		draw_rect(Rect2(pos, Vector2(e["size"], e["size"])), color)
