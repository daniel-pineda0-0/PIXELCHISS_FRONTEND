extends CanvasLayer
## Fondo de la sala: paisaje en ruinas con lava y luna roja, y un ojo que vuela de
## lado por detras de la interfaz, se detiene en un lugar visible (rest_point), se
## voltea y te mira fijamente. El ojo no parpadea.

@export var eye_front: Texture2D
@export var eye_side: Texture2D          # la imagen mira a la IZQUIERDA
@export var fly_speed := 100.0           # px por segundo
@export var wander := false              # true: tras mirar un rato vuelve a volar
@export var stare_time := 40.0           # solo si wander = true

# Los dos sprites son de 72x72 y el globo esta centrado en ellos.
const TURN_SQUASH := 0.06

# Pasada 1: rasante de izquierda a derecha (mirando a la derecha).
const PASS_1 := [Vector2(-60, 300), Vector2(120, 314), Vector2(300, 296), Vector2(500, 318), Vector2(700, 292)]
# Pasada 2: reaparece arriba a la derecha, cruza el cielo mirando a la izquierda y baja al punto de descanso.
const PASS_2_START := Vector2(700, 70)
const PASS_2 := [Vector2(560, 38), Vector2(430, 30), Vector2(380, 96)]

@onready var eye: Node2D = $World/Eye
@onready var sprite: Sprite2D = $World/Eye/Sprite
@onready var lava_glow: Sprite2D = $World/LavaGlow

var rest_point := Vector2(332, 172)
var _t := 0.0
var _flying := true
var _hover := 0.0              # amplitud del vaiven vertical (px)
var _staring := false

func _ready() -> void:
	var glow := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	glow.tween_property(lava_glow, "modulate:a", 0.4, 1.8)
	glow.tween_property(lava_glow, "modulate:a", 0.08, 1.8)
	_start_cycle()

func _process(delta: float) -> void:
	_t += delta
	sprite.position.y = roundf(sin(_t * (5.0 if _flying else 1.6)) * _hover)

## La sala dice donde esta el hueco libre entre los mapas. Si el ojo ya esta mirando se
## desliza hasta ahi; si no, llega alli al terminar su vuelo.
func set_rest_point(point: Vector2) -> void:
	var moved := not rest_point.is_equal_approx(point)
	rest_point = point
	if _staring and moved:
		create_tween().tween_property(eye, "position", rest_point, 0.5).set_trans(Tween.TRANS_SINE)

func _start_cycle() -> void:
	_staring = false
	_flying = true
	_hover = 2.5
	_face_side(+1)
	eye.position = PASS_1[0]
	var curve := _smooth(PASS_1)
	var length := curve.get_baked_length()
	var t := create_tween()
	t.tween_interval(0.5)                         # entra por la izquierda y se oye pasar
	t.tween_callback(Sfx.play.bind(&"eye_fly"))
	t.tween_method(_follow.bind(curve), 0.0, length, length / fly_speed)
	t.tween_callback(_begin_pass_2)

func _begin_pass_2() -> void:
	_face_side(-1)
	eye.position = PASS_2_START
	var points: Array = [PASS_2_START]
	points.append_array(PASS_2)
	points.append(rest_point)
	var curve := _smooth(points)
	var length := curve.get_baked_length()
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_callback(Sfx.play.bind(&"eye_fly"))
	t.tween_method(_follow.bind(curve), 0.0, length, length / fly_speed * 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_callback(_turn_to_front)

## Gira el cuerpo (aplastandolo un instante) y deja el ojo de frente.
func _turn_to_front() -> void:
	_flying = false
	Sfx.play(&"eye_turn")
	var t := create_tween()
	t.tween_property(eye, "scale:x", TURN_SQUASH * signf(eye.scale.x), 0.16).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func():
		sprite.texture = eye_front
		eye.scale.x = TURN_SQUASH)
	t.tween_property(eye, "scale:x", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_start_staring)

func _start_staring() -> void:
	_staring = true
	Sfx.play(&"eye_stare")
	_hover = 1.0
	if wander:
		var t := create_tween()
		t.tween_interval(stare_time)
		t.tween_callback(_turn_to_side)

func _turn_to_side() -> void:
	_staring = false
	Sfx.play(&"eye_turn", 0.0, 0.85)
	var t := create_tween()
	t.tween_property(eye, "scale:x", TURN_SQUASH, 0.16).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func():
		sprite.texture = eye_side
		eye.scale.x = -TURN_SQUASH)
	t.tween_property(eye, "scale:x", -1.0, 0.2).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_flee_and_restart)

func _flee_and_restart() -> void:
	_flying = true
	Sfx.play(&"eye_fly", 0.0, 0.9)
	_hover = 2.5
	var t := create_tween()
	var target := Vector2(760, eye.position.y - 40)
	t.tween_property(eye, "position", target, (target.x - eye.position.x) / fly_speed) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(_start_cycle)

# --- utilidades ---

## Pone la imagen de lado. direction +1 = vuela a la derecha, -1 = a la izquierda.
## El sprite mira a la izquierda, asi que a la derecha se voltea.
func _face_side(direction: int) -> void:
	sprite.texture = eye_side
	eye.scale.x = -1.0 if direction > 0 else 1.0

func _follow(offset: float, curve: Curve2D) -> void:
	eye.position = curve.sample_baked(offset)

## Curva suave que pasa por todos los puntos.
func _smooth(points: Array) -> Curve2D:
	var curve := Curve2D.new()
	for i in points.size():
		var prev: Vector2 = points[maxi(i - 1, 0)]
		var next: Vector2 = points[mini(i + 1, points.size() - 1)]
		var tangent := (next - prev) * 0.22
		curve.add_point(points[i], -tangent, tangent)
	return curve
