extends Control
## Pantalla que aparece justo después del login con Google.
##
## Ya no se elige entre "crear" o "unirse": al entrar, el jugador queda
## como anfitrión de una sala nueva automáticamente (US-003 se dispara
## solo, sin botón de por medio) y ve su código para compartir.
##
## Debajo se deja un campo por si el jugador prefiere unirse a la sala
## de alguien más (US-004) en lugar de quedarse como anfitrión de la
## suya — sin necesidad de una pantalla intermedia aparte.

@onready var code_label: Label = %RoomCodeLabel
@onready var code_input: LineEdit = %CodeInput
@onready var join_btn: Button = %JoinBoton
@onready var error_label: Label = %ErrorLabel
@onready var load_label: Label = %LoadLabel


func _ready() -> void:
	error_label.text = ""

	ApiClient.sala_creada.connect(_on_sala_lista)
	ApiClient.sala_unida.connect(_on_sala_lista)
	ApiClient.sala_error.connect(_on_sala_error)

	_set_cargando(true)

	if Sesion.tiene_sesion():
		ApiClient.crear_sala()
	else:
		# TEMPORAL: esta pantalla asume que ya se hizo login antes de
		# llegar aquí (Sesion.player_id/nombre ya llenos). Mientras la
		# pantalla de login real de tu compañero no esté integrada,
		# hacemos un mock-login aquí mismo para poder seguir probando
		# esta escena sola con F6. Borrar este "else" cuando el login
		# real ya deje la sesión lista antes de entrar a esta escena.
		ApiClient.login_ok.connect(_on_login_temporal_ok)
		ApiClient.mock_login("Jugador de prueba")


func _on_login_temporal_ok(_data: Dictionary) -> void:
	ApiClient.login_ok.disconnect(_on_login_temporal_ok)
	ApiClient.crear_sala()




func _on_sala_lista(data: Dictionary) -> void:
	_set_cargando(false)
	error_label.text = ""
	if Sesion.es_host:
		code_label.text = "Eres el anfitrión — código: %s" % data.get("code", "")
	else:
		code_label.text = "Te uniste a la sala: %s" % data.get("code", "")


func _on_sala_error(codigo: String, mensaje: String) -> void:
	_set_cargando(false)
	match codigo:
		"CODIGO_INVALIDO":
			error_label.text = "Ese código no existe."
		"SALA_LLENA":
			error_label.text = "Esa sala ya está llena (máx. 4 jugadores)."
		"PARTIDA_INICIADA":
			error_label.text = "Esa partida ya está en curso."
		"EXPULSADO":
			error_label.text = "Fuiste expulsado de esa sala."
		_:
			error_label.text = mensaje


func _set_cargando(activo: bool) -> void:
	load_label.visible = activo
	join_btn.disabled = activo
	code_input.editable = not activo

func _on_join_boton_pressed() -> void:
	var codigo := code_input.text.strip_edges()
	if codigo.is_empty():
		error_label.text = "Escribe un código de sala."
		return
	error_label.text = ""
	_set_cargando(true)
	ApiClient.unirse_sala(codigo)
