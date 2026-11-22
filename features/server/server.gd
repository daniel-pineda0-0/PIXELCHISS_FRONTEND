extends Control
## Pantalla de servidor: se abre cuando el cliente no logra conectar (GameState.resolve_next_scene
## o un login sin respuesta). Pide la IP, comprueba que el Gateway responda y la recuerda
## (Config.set_server). Al conectar vuelve a la pantalla de carga, que reanuda el arranque normal.

@onready var _message: Label = %MessageLabel
@onready var _address: LineEdit = %AddressEdit
@onready var _status: Label = %StatusLabel
@onready var _connect: Button = %ConnectButton
@onready var _local: Button = %LocalButton
@onready var _cancel: Button = %CancelButton

var _busy := false
var _attempt := 0            # identifica el intento en curso: un intento cancelado no actúa al terminar

func _ready() -> void:
	_message.text = "No se pudo conectar con el servidor en %s. Escribe la IP del equipo donde corre." % _shown(Config.BASE_URL)
	_address.text = _shown(Config.BASE_URL)
	_connect.pressed.connect(_try_connect)
	_local.pressed.connect(_use_local)
	_cancel.pressed.connect(_cancel_attempt)
	_address.text_submitted.connect(func(_t: String): _try_connect())
	_address.grab_focus()
	_address.select_all()

## Sin el "http://" para que se lea y edite mejor; normalize() lo repone.
func _shown(base_url: String) -> String:
	return base_url.trim_prefix("http://")

func _use_local() -> void:
	_address.text = _shown(Config.DEFAULT_BASE_URL)
	_try_connect()

func _set_busy(value: bool) -> void:
	_busy = value
	_connect.disabled = value
	_local.disabled = value
	_address.editable = not value
	_cancel.visible = value

func _cancel_attempt() -> void:
	_attempt += 1                 # el resultado del intento anterior se ignora
	_set_busy(false)
	_status.text = "Conexión cancelada"

func _try_connect() -> void:
	if _busy:
		return
	var base_url := Config.normalize(_address.text)
	if base_url == "":
		_status.text = "Dirección no válida. Ejemplo: 192.168.1.5:8080"
		return
	_attempt += 1
	var mine := _attempt
	_set_busy(true)
	_status.text = "Conectando con %s..." % _shown(base_url)
	var reachable: bool = await Api.wait_for_server(base_url, 2, 5.0)
	if mine != _attempt:
		return                    # se canceló mientras esperaba
	_set_busy(false)
	if not reachable:
		_status.text = "Sin respuesta de %s. Revisa la IP, el puerto y que el servidor esté encendido." % _shown(base_url)
		if base_url.begins_with("https://"):
			_status.text += " (HTTPS con certificado propio aún no está soportado.)"
		return
	# Credenciales de otro servidor no valen en este (guía §1.3): solo se conserva la sesión si la
	# dirección no cambió.
	if base_url != Config.BASE_URL:
		Session.clear()
	Config.set_server(base_url)
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)
