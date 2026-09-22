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

@onready var codigo_label: Label = %CodigoLabel
@onready var codigo_input: LineEdit = %CodigoInput
@onready var unirse_btn: Button = %UnirseBoton
@onready var mensaje_label: Label = %MensajeError
@onready var cargando_label: Label = %Cargando


func _ready() -> void:
	mensaje_label.text = ""

	unirse_btn.pressed.connect(_on_unirse_pressed)
	codigo_input.text_submitted.connect(func(_texto: String): _on_unirse_pressed())

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


func _on_unirse_pressed() -> void:
	var codigo := codigo_input.text.strip_edges()
	if codigo.is_empty():
		mensaje_label.text = "Escribe un código de sala."
		return
	mensaje_label.text = ""
	_set_cargando(true)
	# Nota: la sala que se creó sola al entrar queda "huérfana" en el
	# servidor (nadie más se conecta a ella). Para pruebas locales no es
	# grave, pero si quieren limpiarla de verdad hay que avisarle al
	# servidor con un mensaje "leave_room" antes de unirte a otra, una
	# vez tengan el cliente WebSocket conectado.
	ApiClient.unirse_sala(codigo)


func _on_sala_lista(data: Dictionary) -> void:
	_set_cargando(false)
	mensaje_label.text = ""
	if Sesion.es_host:
		codigo_label.text = "Eres el anfitrión — código: %s" % data.get("code", "")
	else:
		codigo_label.text = "Te uniste a la sala: %s" % data.get("code", "")


func _on_sala_error(codigo: String, mensaje: String) -> void:
	_set_cargando(false)
	match codigo:
		"CODIGO_INVALIDO":
			mensaje_label.text = "Ese código no existe."
		"SALA_LLENA":
			mensaje_label.text = "Esa sala ya está llena (máx. 4 jugadores)."
		"PARTIDA_INICIADA":
			mensaje_label.text = "Esa partida ya está en curso."
		"EXPULSADO":
			mensaje_label.text = "Fuiste expulsado de esa sala."
		_:
			mensaje_label.text = mensaje


func _set_cargando(activo: bool) -> void:
	cargando_label.visible = activo
	unirse_btn.disabled = activo
	codigo_input.editable = not activo
