extends CanvasLayer
## Fondo del menu: una bola de fuego cruza el cielo, estalla en el castillo y lo derrumba.
## Despues de unos segundos el castillo se reconstruye y el ciclo vuelve a empezar.

@export var castle_frames: Array[Texture2D] = []   # 0 intacto, 1 explosion, 2 grietas, 3 en ruinas
@export var intact_time := 7.0     # segundos con el castillo en pie
@export var flight_time := 2.4     # vuelo de la bola de fuego
@export var rubble_time := 5.0     # segundos que quedan las ruinas

const IMPACT := Vector2(499, 179)          # donde pega la bola (en el castillo)
const FIRE_START := Vector2(-50, 30)
const FIRE_CTRL := Vector2(260, -10)       # punto de control de la curva del vuelo
const COLLAPSE_POINT := Vector2(540, 225)

@onready var castle_group: Node2D = $World/CastleGroup
@onready var castle: Sprite2D = $World/CastleGroup/Castle
@onready var rubble: Sprite2D = $World/CastleGroup/Rubble
@onready var fireball: Sprite2D = $World/Fireball
@onready var trail: CPUParticles2D = $World/Fireball/Trail
@onready var sparks: CPUParticles2D = $World/Sparks
@onready var debris: CPUParticles2D = $World/Debris
@onready var dust: CPUParticles2D = $World/Dust
@onready var flash: ColorRect = $Flash
@onready var lava_glow: Sprite2D = $World/LavaGlow

func _ready() -> void:
	# la lava "respira"
	var g := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	g.tween_property(lava_glow, "modulate:a", 0.45, 1.6)
	g.tween_property(lava_glow, "modulate:a", 0.08, 1.6)
	_start_cycle()

func _start_cycle() -> void:
	_set_frame(0)
	castle.modulate.a = 1.0
	rubble.modulate.a = 0.0
	fireball.visible = false
	trail.emitting = false
	var t := create_tween()
	t.tween_interval(intact_time)
	t.tween_callback(_launch)
	t.tween_method(_move_fireball, 0.0, 1.0, flight_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_impact)
	t.tween_interval(0.18)
	t.tween_callback(_set_frame.bind(2))
	t.tween_interval(0.35)
	t.tween_callback(_collapse)
	t.tween_interval(0.5)
	t.tween_property(castle, "modulate:a", 0.0, 0.9)             # ruinas aparecen
	t.parallel().tween_property(rubble, "modulate:a", 1.0, 0.9)
	t.tween_interval(rubble_time)
	t.tween_callback(_set_frame.bind(0))                          # el castillo (invisible) vuelve al frame intacto
	t.tween_property(castle, "modulate:a", 1.0, 1.6)             # y se reconstruye
	t.parallel().tween_property(rubble, "modulate:a", 0.0, 1.6)
	t.tween_callback(_start_cycle)

func _set_frame(i: int) -> void:
	if i < castle_frames.size():
		castle.texture = castle_frames[i]

func _launch() -> void:
	_move_fireball(0.0)
	fireball.visible = true
	trail.emitting = true

func _move_fireball(t: float) -> void:
	# curva de Bezier cuadratica: sube desde la izquierda y cae sobre el castillo
	fireball.position = FIRE_START.lerp(FIRE_CTRL, t).lerp(FIRE_CTRL.lerp(IMPACT, t), t)
	var tangent := (FIRE_CTRL - FIRE_START).lerp(IMPACT - FIRE_CTRL, t)
	fireball.rotation = tangent.angle()

func _impact() -> void:
	fireball.visible = false
	trail.emitting = false
	_set_frame(1)
	sparks.restart()
	debris.position = IMPACT
	debris.restart()
	flash.modulate.a = 0.55
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.4)
	_shake(3.0, 0.45)

func _collapse() -> void:
	_set_frame(3)
	debris.position = COLLAPSE_POINT
	debris.restart()
	dust.restart()
	_shake(2.0, 0.5)

func _shake(amount: float, time: float) -> void:
	var s := create_tween()
	var steps := int(time / 0.04)
	for i in steps:
		var k := 1.0 - float(i) / steps
		s.tween_property(castle_group, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)).round() * k, 0.04)
	s.tween_property(castle_group, "position", Vector2.ZERO, 0.04)
