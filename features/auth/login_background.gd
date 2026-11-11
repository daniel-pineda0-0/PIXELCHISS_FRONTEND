extends CanvasLayer
## Fondo del login: la luna sube, se vuelve roja y el cielo pasa de frio a rojo.
## Animacion de una sola pasada; termina igual que la imagen de referencia.

const MOON_END := Vector2(325, 71)
const RISE := 24.0            # px que sube la luna
const RISE_TIME := 20.0
const RED_DELAY := 6.0
const RED_TIME := 6.0

@onready var world: Node2D = $World
@onready var moon: Sprite2D = $World/Moon
@onready var halo: Sprite2D = $World/MoonHalo
@onready var mist_near: Sprite2D = $World/MistNear/Sprite2D

func _ready() -> void:
	world.modulate = Color(0.55, 0.6, 0.9)
	moon.position = MOON_END + Vector2(0, RISE)
	halo.position = moon.position
	halo.modulate.a = 0.0

	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	t.tween_property(moon, "position:y", MOON_END.y, RISE_TIME)
	t.tween_property(halo, "position:y", MOON_END.y, RISE_TIME)
	t.tween_property(moon, "modulate", Color("e04040"), RED_TIME).set_delay(RED_DELAY)
	t.tween_property(halo, "modulate:a", 1.0, RED_TIME).set_delay(RED_DELAY)
	t.tween_property(world, "modulate", Color.WHITE, RED_TIME).set_delay(RED_DELAY)

	# la neblina cercana respira: sube y baja unos px en bucle
	var b := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	b.tween_property(mist_near, "position:y", -3.0, 3.0)
	b.tween_property(mist_near, "position:y", 3.0, 3.0)
