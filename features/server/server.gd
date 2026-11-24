extends Control
## Pantalla de servidor: se abre cuando el cliente no logra conectar (GameState.resolve_next_scene o
## un login sin respuesta). Pide la IP, comprueba que el Gateway responda y la recuerda (Config).
##
##  · Local (127.0.0.1): HTTP, solo se comprueba /actuator/health.
##  · LAN (IP privada): HTTPS. La primera vez se descarga la CA del propio Gateway (LanDiscovery) y el
##    jugador debe comparar su huella SHA-256 con la que le dio el anfitrión; después, TLS estricto.
##    Una CA ya verificada no se vuelve a preguntar. Una CA DISTINTA en una dirección conocida se trata
##    como sospechosa: se muestran las dos huellas y se detiene la sesión.

@onready var _message: Label = %MessageLabel
@onready var _address: LineEdit = %AddressEdit
@onready var _status: Label = %StatusLabel
@onready var _buttons: HBoxContainer = %Buttons
@onready var _connect: Button = %ConnectButton
@onready var _local: Button = %LocalButton
@onready var _cancel: Button = %CancelButton
@onready var _forget: Button = %ForgetButton
@onready var _verify_box: VBoxContainer = %VerifyBox
@onready var _verify_host: Label = %VerifyHostLabel
@onready var _fingerprint: Label = %FingerprintLabel
@onready var _old_fingerprint: Label = %OldFingerprintLabel
@onready var _verify_prompt: Label = %VerifyPromptLabel
@onready var _confirm: Button = %ConfirmButton
@onready var _reject: Button = %RejectButton

var _busy := false
var _attempt := 0            # identifica el intento en curso: un intento cancelado no actúa al terminar
var _pending := {}           # CA candidata esperando la comparación de huella del jugador
var _discovery: LanDiscovery

func _ready() -> void:
	_discovery = LanDiscovery.new()
	add_child(_discovery)
	_message.text = "No se pudo conectar con el servidor en %s. Escribe la IP del equipo donde corre." % _shown(Config.BASE_URL)
	_address.text = _shown(Config.BASE_URL)
	_connect.pressed.connect(_try_connect)
	_local.pressed.connect(_use_local)
	_cancel.pressed.connect(_cancel_attempt)
	_forget.pressed.connect(_forget_ca)
	_confirm.pressed.connect(_on_confirm)
	_reject.pressed.connect(_on_reject)
	_address.text_submitted.connect(func(_t: String): _try_connect())
	_address.text_changed.connect(func(_t: String): _refresh_forget())
	_address.grab_focus()
	_address.select_all()
	_refresh_forget()

## Sin el esquema, para que se lea y edite mejor: parse_address() lo repone según la IP.
func _shown(base_url: String) -> String:
	return base_url.trim_prefix("http://").trim_prefix("https://")

func _use_local() -> void:
	_address.text = _shown(Config.DEFAULT_BASE_URL)
	_try_connect()

func _set_busy(value: bool) -> void:
	_busy = value
	_connect.disabled = value
	_local.disabled = value
	_forget.disabled = value
	_address.editable = not value
	_cancel.visible = value

func _cancel_attempt() -> void:
	_attempt += 1                 # el resultado del intento anterior se ignora
	_set_busy(false)
	_status.text = "Conexión cancelada"

func _try_connect() -> void:
	if _busy or _verify_box.visible:
		return
	var parsed := Config.parse_address(_address.text)
	if parsed.error != "":
		_status.text = parsed.error
		return
	_attempt += 1
	var mine := _attempt
	_set_busy(true)
	if parsed.lan:
		await _connect_lan(parsed, mine)
	else:
		await _connect_local(parsed, mine)

# --- Local ------------------------------------------------------------------------------------------

func _connect_local(parsed: Dictionary, mine: int) -> void:
	var base_url: String = parsed.base_url
	_status.text = "Conectando con %s..." % _shown(base_url)
	var reachable: bool = await Api.wait_for_server(base_url, 2, 5.0)
	if mine != _attempt:
		return                    # se canceló mientras esperaba
	_set_busy(false)
	if not reachable:
		_status.text = "Sin respuesta de %s. Revisa el puerto y que el servidor esté encendido." % _shown(base_url)
		return
	# Credenciales de otro servidor no valen en este (guía §1.3): solo se conserva la sesión si la
	# dirección y el perfil no cambiaron.
	if base_url != Config.BASE_URL or Config.ca_hash != "":
		Session.clear()
	Config.set_server(base_url)
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

# --- LAN ---------------------------------------------------------------------------------------------

func _connect_lan(parsed: Dictionary, mine: int) -> void:
	var host: String = parsed.host
	var port: int = parsed.port
	var host_key := "%s:%d" % [host, port]
	_status.text = "Buscando la CA de %s..." % host_key
	var cand: Dictionary = await _discovery.fetch_with_retry(host, port)
	if mine != _attempt:
		return
	if not cand.ok:
		_set_busy(false)
		_status.text = cand.error
		_refresh_forget()
		return
	# CA ya verificada (se reconoce por el hash calculado, no por caId, IP ni nombre): no se pregunta.
	if Config.trust_has(cand.hash):
		await _finish_lan(parsed, cand.hash, host_key, mine)
		return
	# CA nueva, o DISTINTA de la que ya se había confirmado en esta dirección.
	var previous := Config.profile_for_host(host_key)
	_pending = {"parsed": parsed, "cand": cand, "previous": previous, "host_key": host_key, "mine": mine}
	_show_verify()

## Segunda mitad: con la CA confiable se abre TLS ESTRICTO (sin client_unsafe) y se comprueba la salud.
func _finish_lan(parsed: Dictionary, hash: String, host_key: String, mine: int) -> void:
	var tls := Config.tls_for(hash)
	if tls == null:
		_set_busy(false)
		_status.text = "La CA guardada ya no es válida. Vuelve a conectar para verificarla otra vez."
		return
	_status.text = "Verificando la conexión segura con %s..." % host_key
	var base_url: String = parsed.base_url
	var reachable: bool = await Api.wait_for_server(base_url, 2, 5.0, tls)
	if mine != _attempt:
		return
	_set_busy(false)
	if not reachable:
		# No se atribuye una causa concreta al fallo TLS: puede ser IP, puerto, certificado o red.
		_status.text = "No se pudo establecer la conexión segura con %s. Comprueba IP y puerto y que el anfitrión tenga la LAN activa (`lan.py url`). Si su IP cambió, debe ejecutar `start --auto`." % host_key
		_refresh_forget()
		return
	Config.trust_note_host(hash, host_key)
	if base_url != Config.BASE_URL or hash != Config.ca_hash:
		Session.clear()           # nunca se envía el JWT ni el refresh de otro anfitrión
	Config.set_server(base_url, hash)
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

# --- Verificación de huella ----------------------------------------------------------------------------

func _show_verify() -> void:
	_set_busy(false)
	_message.visible = false
	_address.visible = false
	_buttons.visible = false
	_status.text = ""
	var cand: Dictionary = _pending.cand
	var previous: String = _pending.previous
	_verify_box.visible = true
	_fingerprint.text = CaCert.spaced(cand.hash)
	if previous == "":
		_verify_host.text = "Anfitrión %s" % _pending.host_key
		_old_fingerprint.visible = false
		_verify_prompt.text = "Compara los 64 caracteres con la huella que te comunicó el anfitrión por un canal independiente. Confirma únicamente si coinciden."
	else:
		_verify_host.text = "¡%s presenta OTRA CA!" % _pending.host_key
		_old_fingerprint.visible = true
		_old_fingerprint.text = "CA guardada antes: %s" % CaCert.spaced(previous)
		_verify_prompt.text = "Esta dirección ya tenía otra CA. Si el anfitrión no la renovó a propósito, podría ser una suplantación. Compara los 64 caracteres de la CA NUEVA (arriba) con la huella que te comunicó el anfitrión por un canal independiente. Confirma únicamente si coinciden. Se cerrará tu sesión."

func _hide_verify() -> void:
	_verify_box.visible = false
	_message.visible = true
	_address.visible = true
	_buttons.visible = true
	_address.grab_focus()

func _on_reject() -> void:
	_pending = {}                 # se descarta la candidata: nada guardado, sin Google ni Game
	_hide_verify()
	_status.text = "CA descartada: no se guardó nada."

func _on_confirm() -> void:
	if _pending.is_empty():
		return
	var pending := _pending
	_pending = {}
	var cand: Dictionary = pending.cand
	_hide_verify()
	if not Config.trust_add(cand.der, cand.ca_id, pending.host_key):
		_status.text = "No se pudo guardar la CA en este equipo."
		return
	if pending.previous != "":
		Session.clear()           # CA distinta en una IP conocida: se detiene la sesión; la anterior se conserva
	_set_busy(true)
	await _finish_lan(pending.parsed, cand.hash, pending.host_key, pending.mine)

# --- Olvidar CA --------------------------------------------------------------------------------------------

## El botón aparece solo si la IP escrita ya tiene una CA verificada guardada.
func _refresh_forget() -> void:
	var parsed := Config.parse_address(_address.text)
	_forget.visible = parsed.error == "" and parsed.lan \
			and Config.profile_for_host("%s:%d" % [parsed.host, parsed.port]) != ""

func _forget_ca() -> void:
	var parsed := Config.parse_address(_address.text)
	if parsed.error != "" or not parsed.lan:
		return
	var hash := Config.profile_for_host("%s:%d" % [parsed.host, parsed.port])
	if hash == "":
		return
	if hash == Config.ca_hash:
		Session.clear()           # la sesión usa esa CA: se cierra con ella
	Config.trust_remove(hash)
	_refresh_forget()
	_status.text = "CA olvidada. La próxima conexión pedirá verificarla de nuevo."
