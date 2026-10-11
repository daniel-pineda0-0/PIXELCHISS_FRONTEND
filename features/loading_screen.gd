extends Control

@onready var label:=$Label

const MAX_DOTS = 3
var target_scene_path:String
var dots:int
@export var animtion_time:= 1.5
var last_dot:float

func _ready() -> void:
	if(GameState.state == 0):
		target_scene_path = await Boot.new().restore_session()
	load_next_scene.call_deferred()
	last_dot=0
	dots = 0

func load_next_scene()->void:
	if target_scene_path.is_empty():
		target_scene_path = GameState.next_scene_path()
	ResourceLoader.load_threaded_request(target_scene_path)

func _process(delta: float) -> void:
	check_load()
	text_animation(delta)

func check_load()->void:
	var status = ResourceLoader.load_threaded_get_status(target_scene_path)
	if status==ResourceLoader.THREAD_LOAD_LOADED:
		var new_scene = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
		await get_tree().create_timer(animtion_time-(animtion_time/MAX_DOTS*dots)).timeout
		get_tree().change_scene_to_packed(new_scene)

func text_animation(delta: float)->void:
	last_dot+=delta 
	if (last_dot>animtion_time/MAX_DOTS):
		dots+=1
		if (dots>3):
			dots=0
		var text = "Cargando"
		for i in range(0, dots):
			text+="."
		label.text = text
		last_dot=0
