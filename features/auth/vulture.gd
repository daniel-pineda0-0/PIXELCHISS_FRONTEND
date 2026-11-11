extends AnimatedSprite2D
## Buitre que planea en una elipse amplia y lenta, con un leve vaiven vertical.
## La posicion que tiene en la escena es el CENTRO de su recorrido.

@export var radius := Vector2(90, 20)
@export var speed := 0.12                # radianes por segundo; negativo = sentido contrario
@export var start_angle := 0.0
@export var native_facing := 1           # hacia donde mira el dibujo (+1 derecha)

var _center: Vector2
var _angle: float
var _t := randf() * 10.0

func _ready() -> void:
	_center = position
	_angle = start_angle
	speed_scale = randf_range(0.85, 1.15)
	frame = randi() % sprite_frames.get_frame_count("fly")
	play("fly")
	_update(0.0)

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	_t += delta
	_angle += speed * delta
	position = _center + Vector2(cos(_angle) * radius.x, sin(_angle) * radius.y + sin(_t * 1.6) * 2.0)
	var vel_x := -sin(_angle) * radius.x * speed
	if absf(vel_x) > 0.5:                # evita que parpadee al dar la vuelta
		flip_h = vel_x * native_facing < 0.0
