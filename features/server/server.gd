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
	Music.play(&"login")                  # misma musica y fondo que la pantalla de inicio
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
	return base_url.trim_prefix("http://").trim_prefix("https://")

func _use_local() -> void:
	_address.text = _shown(Config.DEFAULT_BASE_URL)
	_try_connect()

## Mismo criterio de color que el login: gris = informacion, rojo = error.
func _show(text: String, is_error: bool) -> void:
	if is_error:
		Sfx.play(&"error")
	_status.text = text
	_status.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.55) if is_error else Color(0.6039, 0.6039, 0.6039))

func _set_busy(value: bool) -> void:
	_busy = value
	_connect.disabled = value
	_local.disabled = value
	_address.editable = not value
	_cancel.visible = value

func _cancel_attempt() -> void:
	_attempt += 1                 # el resultado del intento anterior se ignora
	_set_busy(false)
	_show("Conexión cancelada", false)

func _try_connect() -> void:
	if _busy:
		return
	var parsed := Config.parse_address(_address.text)
	if parsed.error != "":
		_show(str(parsed.error), true)
		return
	var base_url: String = parsed.base_url
	_attempt += 1
	var mine := _attempt
	_set_busy(true)
	_show("Conectando con %s..." % _shown(base_url), false)
	var ca_hash := ""
	if parsed.lan:
		ca_hash = await _prepare_lan(parsed, mine)       # "" = cancelado o error (ya mostrado)
		if mine != _attempt:
			return
		if ca_hash == "":
			_set_busy(false)
			return
	var tls: TLSOptions = Config.tls_for(ca_hash) if ca_hash != "" else null
	var reachable: bool = await Api.wait_for_server(base_url, 2, 5.0, tls)
	if mine != _attempt:
		return                    # se canceló mientras esperaba
	_set_busy(false)
	if not reachable:
		var why := "Sin respuesta de %s. Revisa la IP, el puerto y que el servidor esté encendido." % _shown(base_url)
		if parsed.lan:
			why = "La CA es de confianza pero el TLS falló. El certificado del servidor puede estar vencido o no incluir la IP %s: que el anfitrión ejecute `lan.py start --auto`." % parsed.host
		_show(why, true)
		return
	# Credenciales de otro servidor no valen en este (guía §1.3): solo se conserva la sesión si la
	# dirección no cambió.
	if base_url != Config.BASE_URL:
		Session.clear()
	Config.set_server(base_url, ca_hash)
	get_tree().change_scene_to_file(GameState.LOADING_SCENE)

## Primera conexión a un anfitrión LAN (guía §1.4): descarga la CA candidata, pide al jugador que
## compare la huella y la guarda. Devuelve el hash (DER) de la CA confiable, o "" si se canceló/falló.
func _prepare_lan(parsed: Dictionary, mine: int) -> String:
	var host_key := "%s:%d" % [parsed.host, parsed.port]
	var discovery := LanDiscovery.new()
	add_child(discovery)
	_show("Descargando la CA de %s..." % host_key, false)
	var result: Dictionary = await discovery.fetch_with_retry(parsed.host, parsed.port)
	discovery.queue_free()
	if mine != _attempt:
		return ""
	if not result.ok:
		_show(str(result.error), true)
		return ""
	var hash: String = result.hash
	if Config.trust_has(hash):
		Config.trust_note_host(hash, host_key)
		return hash
	var known := Config.profile_for_host(host_key)
	var confirmed: bool = await _confirm_fingerprint(host_key, hash, known)
	if mine != _attempt:
		return ""
	if not confirmed:
		_show("Conexión cancelada: la CA no fue verificada.", false)
		return ""
	if not Config.trust_add(result.der, str(result.ca_id), host_key):
		_show("No se pudo guardar la CA.", true)
		return ""
	return hash

## Diálogo sin opción preseleccionada. true solo si el jugador pulsa «He comparado y coincide».
func _confirm_fingerprint(host_key: String, hash: String, known_hash: String) -> bool:
	var dialog := AcceptDialog.new()
	dialog.title = "Verificar anfitrión"
	dialog.exclusive = true
	dialog.get_ok_button().visible = false
	var text := "Anfitrión: %s\n\nHuella SHA-256 de la CA:\n%s\n\nCompara los 64 caracteres con la huella que te comunicó el anfitrión por un canal independiente. Confirma únicamente si coinciden." % [host_key, CaCert.spaced(hash)]
	if known_hash != "":
		text = "¡ATENCIÓN! Esta dirección ya usaba otra CA (%s...). Podría ser un anfitrión distinto o un ataque.\n\n%s" % [known_hash.substr(0, 16), text]
	dialog.dialog_text = text
	dialog.dialog_autowrap = true
	var ok_btn := dialog.add_button("He comparado y coincide", false, "ok")
	var cancel_btn := dialog.add_button("Cancelar", true, "cancel")
	var answer := [false]
	var done := [false]
	ok_btn.pressed.connect(func(): answer[0] = true; done[0] = true; dialog.hide())
	cancel_btn.pressed.connect(func(): done[0] = true; dialog.hide())
	dialog.canceled.connect(func(): done[0] = true)
	dialog.visibility_changed.connect(func(): if not dialog.visible: done[0] = true)
	add_child(dialog)
	dialog.popup_centered(Vector2i(560, 260))
	dialog.get_ok_button().release_focus()
	while not done[0]:
		await get_tree().process_frame
	dialog.queue_free()
	return answer[0]
