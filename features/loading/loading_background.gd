extends CanvasLayer
## Fondo de la pantalla de carga: paisaje difuminado y de baja calidad, con ruido (grano),
## neblina y brillo de lava que se mueven. Solo los escombros y ramas del primer plano
## quedan nitidos, como en la maqueta.

const BASE_POS := Vector2(-12.8, -7.2)   # el fondo se agranda 4 % para que el vaiven no muestre el borde
const DRIFT := Vector2(4.0, 2.0)         # vaiven lento del fondo borroso (px)
const DRIFT_PERIOD := 16.0
const GRAIN_STEP := 0.07                 # el grano "salta" cada 70 ms
const GRAIN_JITTER := 20                 # la textura del grano sobra 20 px por lado

@onready var blur_world: Node2D = $BlurWorld
@onready var lava_glow: Sprite2D = $BlurWorld/LavaGlow
@onready var grain: Sprite2D = $Grain

var _t := 0.0
var _grain_clock := 0.0

func _ready() -> void:
	blur_world.scale = Vector2(1.04, 1.04)
	blur_world.position = BASE_POS
	var glow := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	glow.tween_property(lava_glow, "modulate:a", 0.6, 1.4)
	glow.tween_property(lava_glow, "modulate:a", 0.15, 1.4)
	_jump_grain()

func _process(delta: float) -> void:
	_t += delta
	var k := TAU / DRIFT_PERIOD
	blur_world.position = BASE_POS + Vector2(sin(_t * k) * DRIFT.x, cos(_t * k * 0.7) * DRIFT.y)
	_grain_clock += delta
	if _grain_clock >= GRAIN_STEP:
		_grain_clock = 0.0
		_jump_grain()

func _jump_grain() -> void:
	grain.position = Vector2(-randi_range(0, GRAIN_JITTER), -randi_range(0, GRAIN_JITTER))
