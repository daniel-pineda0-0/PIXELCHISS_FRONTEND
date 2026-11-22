extends Control
## Pantalla de carga: la lava de la barra se llena con el progreso y el muneco corre
## encima de la barra al ritmo del avance. Debajo, "CARGANDO" con puntos.
## Pasa siempre por aqui al cambiar de pantalla (login, menu, sala, partida).

const MAX_DOTS := 3
const WIN_X := 35.0            # inicio de la ventana de la barra dentro de Bar (px)
const WIN_W := 217.0           # ancho de la ventana (px)
const LAVA_PERIOD := 284.0     # la textura de lava se repite cada 284 px (sin costura)
const FEET_Y := 15.0           # el muneco pisa el borde superior de la barra
const STALL_LIMIT := 0.9       # mientras no termine la carga, la barra no pasa de aqui

@export var animtion_time := 1.5          # un ciclo completo de puntos
@export var min_time := 1.6               # lo que tarda como minimo en llenarse (se vea la barra)
@export var lava_speed := 18.0            # px/s con que fluye la lava

@onready var label: Label = $Label
@onready var bar: Control = $Bar
@onready var lava_clip: Control = $Bar/LavaClip
@onready var lava_strip: TextureRect = $Bar/LavaClip/LavaStrip
@onready var edge: TextureRect = $Bar/Edge
@onready var runner: AnimatedSprite2D = $Runner

var target_scene_path := ""
var dots := 0
var last_dot := 0.0
var _requested := false
var _changing := false
var _loaded := false
var _failed := false
var _scene: PackedScene
var _elapsed := 0.0
var _real := 0.0          # progreso real de la carga (0..1)
var _shown := 0.0         # progreso que se ve en la barra (0..1)

func _ready() -> void:
	runner.play("run")
	runner.frame_changed.connect(_on_runner_frame_changed)
	_apply_progress()
	target_scene_path = await GameState.resolve_next_scene()
	ResourceLoader.load_threaded_request(target_scene_path)
	_requested = true

func _process(delta: float) -> void:
	_elapsed += delta
	text_animation(delta)
	lava_strip.position.x = -roundf(fposmod(_elapsed * lava_speed, LAVA_PERIOD))
	if _requested and not _loaded and not _failed:
		_poll_load()
	if _failed or _changing:
		return
	# Antes de que termine la carga la barra avanza "de mentira" hasta STALL_LIMIT (la
	# carga de una escena es casi instantanea y resolve_next_scene puede tardar en red).
	# Al terminar, se llena el resto sin bajar de min_time en total.
	var target := 1.0
	var speed := 1.0 / min_time
	if not _loaded:
		var fake := STALL_LIMIT * (1.0 - exp(-_elapsed / (min_time * 0.7)))
		target = minf(STALL_LIMIT, maxf(fake, _real * STALL_LIMIT))
		speed = 0.6
	_shown = move_toward(_shown, target, speed * delta)
	_apply_progress()
	if _loaded and _shown >= 0.999:
		_finish()

func _poll_load() -> void:
	var progress := []
	match ResourceLoader.load_threaded_get_status(target_scene_path, progress):
		ResourceLoader.THREAD_LOAD_LOADED:
			_scene = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
			_loaded = true
			_real = 1.0
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_failed = true
			runner.pause()
			label.text = "ERROR AL CARGAR"
			push_error("No se pudo cargar: " + target_scene_path)
		_:
			if progress.size() > 0:
				_real = progress[0]

func _finish() -> void:
	_changing = true
	Sfx.play(&"load_done")
	# un instante con la barra llena y luego se cambia de escena
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_callback(func(): get_tree().change_scene_to_packed(_scene))

func _apply_progress() -> void:
	var w := roundf(WIN_W * _shown)
	lava_clip.size.x = w
	edge.visible = w > 2.0 and w < WIN_W
	edge.position.x = WIN_X + w - 3.0
	runner.position = Vector2(roundf(bar.position.x + WIN_X + w), bar.position.y + FEET_Y)

## Un pequeno rebote en los cuadros pares, para que el paso se sienta.
func _on_runner_frame_changed() -> void:
	runner.offset.y = -24.0 - float(runner.frame % 2)
	if not _failed and runner.frame % 2 == 0:
		Sfx.play(&"step", 0.0, randf_range(0.9, 1.1))   # un pisadita por paso

func text_animation(delta: float) -> void:
	if _failed:
		return
	last_dot += delta
	if last_dot > animtion_time / MAX_DOTS:
		dots = (dots + 1) % (MAX_DOTS + 1)
		# los espacios finales mantienen fijo el ancho: "CARGANDO" no se mueve
		label.text = "CARGANDO" + ".".repeat(dots) + " ".repeat(MAX_DOTS - dots)
		last_dot = 0.0
