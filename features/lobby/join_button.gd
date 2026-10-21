extends TextureButton

@onready var label:Label=$Label

func _on_button_down() -> void:
	label.position.y = label.position.y+1


func _on_button_up() -> void:
	label.position.y = label.position.y-1
