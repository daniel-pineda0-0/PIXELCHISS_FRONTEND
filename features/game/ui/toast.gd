class_name Toast
extends Control
## Aviso flotante en cola + destello rojo de pantalla (capturas, soplos, errores).

const TIME := 2.6
const MAX_QUEUE := 3

@onready var _label: Label = %Label
@onready var _flash: ColorRect = %Flash

var _queue: Array[String] = []
var _left := 0.0

## `urgent` descarta lo pendiente y se muestra al momento (errores, captura propia).
func show_message(text: String, urgent := false) -> void:
	if text == "":
		return
	if urgent:
		_queue.clear()
		_show(text)
		return
	_queue.append(text)
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	if _left <= 0.0:
		_show(_queue.pop_front())

func flash() -> void:
	_flash.color.a = 0.35
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.5)

func _show(text: String) -> void:
	_label.text = text
	_label.visible = true
	_left = TIME

func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left > 0.0:
		return
	if _queue.is_empty():
		_label.visible = false
	else:
		_show(_queue.pop_front())
