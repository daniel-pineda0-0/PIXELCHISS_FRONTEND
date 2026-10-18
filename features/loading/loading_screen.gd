extends Control

@onready var label: Label = $Label

const MAX_DOTS := 3
@export var animtion_time := 1.5

var target_scene_path := ""
var dots := 0
var last_dot := 0.0
var _requested := false
var _changing := false

func _ready() -> void:
	target_scene_path = await GameState.resolve_next_scene()
	ResourceLoader.load_threaded_request(target_scene_path)
	_requested = true

func _process(delta: float) -> void:
	text_animation(delta)
	if _requested and not _changing:
		check_load()

func check_load() -> void:
	match ResourceLoader.load_threaded_get_status(target_scene_path):
		ResourceLoader.THREAD_LOAD_LOADED:
			_changing = true
			var scene := ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
			# termina el ciclo de puntos antes de cambiar
			await get_tree().create_timer(animtion_time - (animtion_time / MAX_DOTS * dots)).timeout
			get_tree().change_scene_to_packed(scene)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_changing = true
			push_error("No se pudo cargar: " + target_scene_path)

func text_animation(delta: float) -> void:
	last_dot += delta
	if last_dot > animtion_time / MAX_DOTS:
		dots = (dots + 1) % (MAX_DOTS + 1)
		label.text = "Cargando" + ".".repeat(dots)
		last_dot = 0.0
