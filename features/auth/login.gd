# features/auth/login.gd
extends Control
## Pantalla de inicio de sesion. Flujo:
##   1) el jugador escribe su nombre (3 a 24: letras sin tilde, numeros o _)
##   2) inicia sesion con Google en el navegador
##   3) el nombre se guarda en el servidor (PUT /api/auth/me/display-name), asi la
##      sala lo muestra en vez del nombre de la cuenta de Google
## "Salir" cierra el juego.

const NAME_FILE := "user://last_username.cfg"
const NAME_PATTERN := "^[A-Za-z0-9_]{3,24}$"
const NAME_HINT := "Usa de 3 a 24 letras sin tilde, numeros o _"
const DEFAULT_HINT := "Elige tu nombre"

@onready var btn: Button = %Button
@onready var quit_btn: Button = %QuitButton
@onready var name_edit: LineEdit = %NameEdit
@onready var status: Label = %label

var _login: GoogleLogin
var _name_regex := RegEx.create_from_string(NAME_PATTERN)
var _wanted_name := ""

func _ready() -> void:
	Music.play(&"login")
	name_edit.text = _load_last_name()
	name_edit.text_changed.connect(func(_t: String): _show(DEFAULT_HINT, false))
	name_edit.text_submitted.connect(func(_t: String): _on_button_pressed())
	quit_btn.pressed.connect(func(): get_tree().quit())

func _on_button_pressed() -> void:
	var chosen := name_edit.text.strip_edges()
	if _name_regex.search(chosen) == null:
		_show(NAME_HINT, true)
		name_edit.grab_focus()
		return
	_wanted_name = chosen
	_save_last_name(chosen)
	_set_busy(true)
	if Session.is_logged_in():          # ya hay sesion (p. ej. fallo antes al guardar el nombre)
		_apply_name()
		return
	_show("Esperando el inicio de sesion en el navegador...", false)
	_login = GoogleLogin.new()
	add_child(_login)                   # necesario para que corra _process
	_login.finished.connect(_on_login_finished)
	_login.start()

func _on_login_finished(ok: bool, error: String) -> void:
	_login.queue_free()
	if ok:
		_apply_name()                   # guarda el nombre elegido ANTES de entrar (antes se saltaba)
	elif error == GoogleLogin.ERR_NO_SERVER:
		get_tree().change_scene_to_file(GameState.SERVER_SCENE)    # el servidor dejó de responder
	else:
		_show("No se pudo iniciar sesion: " + error, true)
		_set_busy(false)

## Guarda el nombre elegido en el servidor y entra al juego.
func _apply_name() -> void:
	if str(Session.profile.get("displayName", "")) != _wanted_name:
		_show("Guardando tu nombre...", false)
		var r: Dictionary = await Session.set_display_name(_wanted_name)
		if not r.ok:
			var reason := "no se pudo conectar" if r.status == 0 else "error %d" % r.status
			if r.status == 400:
				reason = NAME_HINT.to_lower()
			_show("No se pudo guardar el nombre: " + reason, true)
			_set_busy(false)
			return
	Sfx.play(&"login_ok")
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

func _set_busy(busy: bool) -> void:
	btn.disabled = busy
	name_edit.editable = not busy

func _show(text: String, is_error: bool) -> void:
	if is_error:
		Sfx.play(&"error")
	status.text = text
	status.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.55) if is_error else Color(0.6039, 0.6039, 0.6039))

func _load_last_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(NAME_FILE) != OK:
		return ""
	return str(cfg.get_value("login", "name", ""))

func _save_last_name(value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("login", "name", value)
	cfg.save(NAME_FILE)
