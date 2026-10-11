# features/auth/login.gd
extends Control

@onready var btn: Button = %Button
@onready var status: Label = %label

var _login: GoogleLogin

func _on_button_pressed() -> void:
	btn.disabled = true
	status.text = "Esperando el inicio de sesión en el navegador…"
	_login = GoogleLogin.new()
	add_child(_login)                      # necesario para que corra _process
	_login.finished.connect(_on_login_finished)
	_login.start()

func _on_login_finished(ok: bool, error: String) -> void:
	_login.queue_free()
	if ok:
		get_tree().change_scene_to_file("res://features/LoadingScreen.tscn")
	else:
		status.text = "No se pudo iniciar sesión: " + error
		btn.disabled = false
