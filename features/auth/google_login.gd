class_name GoogleLogin extends Node
## Login con Google (guía §1.3). El callback ya NO trae tokens: trae un código de un solo
## uso que se canjea por cuerpo (POST) con un verificador PKCE que solo conoce este cliente.
##
##  1. Desktop + PKCE (recomendado): POST /api/auth/desktop/start → navegador → callback
##     (?code&state) → POST /api/auth/desktop/exchange.
##  2. Web local (si Desktop no está configurado en el backend, el start responde 503):
##     /oauth2/authorization/google?client_state&client_port&client_challenge → callback
##     (?code&state) → POST /api/auth/login/exchange. Solo sirve en HTTP loopback, no en LAN.
##
## Cada intento usa un state y un verificador nuevos; un canje fallido (401) obliga a empezar de
## cero: nunca se reintenta. Los tokens no se escriben en logs ni en URLs.
signal finished(ok: bool, error: String)

## Error de conectividad: login.gd lo distingue para abrir la pantalla de servidor.
const ERR_NO_SERVER := "No se pudo contactar al servidor"

var GOOGLE_HTML_TEMPLATE := FileAccess.open("res://service/assets/google_reply_template.html.xml", FileAccess.READ).get_as_text()
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _state := ""          # el que debe volver en el callback (en Desktop lo fija el servidor)
var _verifier := ""       # PKCE: se queda en memoria, nunca sale en una URL
var _desktop := true
var _done := false
var _handled := false
var callback_port := 0

## 43 caracteres Base64URL sin relleno (32 bytes aleatorios), como pide PKCE.
static func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

func start(timeout_sec := 300.0) -> void:
	_verifier = _b64url(Crypto.new().generate_random_bytes(32))
	var challenge := _b64url(_verifier.sha256_buffer())     # S256 del verificador (ASCII)
	var port := _open_port()                                  # solo loopback, nunca 0.0.0.0
	if port == 0:
		_finish(false, "No hay puertos libres")
		return
	var url := await _begin_desktop(port, challenge)
	if _done:
		return
	if url == "":
		url = _begin_web(port, challenge)
	OS.shell_open(url)                                        # navegador del sistema, no uno embebido
	get_tree().create_timer(timeout_sec).timeout.connect(_on_timeout)

func _on_timeout() -> void:
	_finish(false, "Tiempo de espera agotado")

## Devuelve la URL de autorización, o "" para caer al login Web (backend sin Desktop).
func _begin_desktop(port: int, challenge: String) -> String:
	var r: Dictionary = await Api.request(HTTPClient.METHOD_POST, "/api/auth/desktop/start",
			{"clientPort": port, "codeChallenge": challenge}, false)
	if r.ok and r.data is Dictionary and str(r.data.get("authorizationUrl", "")) != "":
		_desktop = true
		_state = str(r.data.get("state", ""))
		return str(r.data.get("authorizationUrl"))
	if r.status == 503:
		return ""                                             # Desktop no configurado en el backend
	if r.status == 0:
		_finish(false, ERR_NO_SERVER)
	else:
		_finish(false, "El servidor rechazó el inicio de sesión (%d)" % r.status)
	return ""

func _begin_web(port: int, challenge: String) -> String:
	_desktop = false
	_state = Crypto.new().generate_random_bytes(32).hex_encode()   # 64 caracteres [0-9a-f]
	# El navegador debe empezar en el MISMO host al que Google lo devuelve: el servidor guarda el
	# intento en una cookie de sesion y OAUTH_REDIRECT_URI apunta a "localhost:8081". Si se empieza
	# en 127.0.0.1, la cookie no viaja a localhost y el callback falla ("Invalid credentials").
	# Solo cambia la URL que abre el navegador; las peticiones del juego siguen en 127.0.0.1.
	var browser_base := Config.BASE_URL.replace("//127.0.0.1:", "//localhost:")
	return "%s/oauth2/authorization/google?client_state=%s&client_port=%d&client_challenge=%s" \
			% [browser_base, _state, port, challenge]

## Abre un puerto local libre para recibir el callback del servidor (acepta 1024-65535).
## Primero deja que el sistema elija uno; asi se evitan los rangos que Windows reserva
## (Hyper-V, WSL, Docker). Si eso falla, prueba puertos al azar en todo el rango.
func _open_port() -> int:
	if _server.listen(0, "127.0.0.1") == OK:
		var chosen := _server.get_local_port()
		if chosen >= 1024:
			return chosen
		_server.stop()
	for _i in 200:
		var p := randi_range(1024, 65535)
		if _server.listen(p, "127.0.0.1") == OK:
			return p
	return 0

func _process(_d: float) -> void:
	if _done or _handled:
		return
	if _peer == null:
		if _server.is_connection_available():
			_peer = _server.take_connection()
		return

	_peer.poll()
	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			pass
		StreamPeerTCP.STATUS_CONNECTING:
			return
		_:
			_peer = null          # el navegador cerró una conexión vacía; seguimos esperando
			return
	var n := _peer.get_available_bytes()
	if n <= 0:
		return
	var res := _peer.get_data(n)  # [error, PackedByteArray]
	if res[0] != OK:
		_peer = null
		return
	_handle((res[1] as PackedByteArray).get_string_from_utf8())

func _handle(raw: String) -> void:
	var line := raw.get_slice("\r\n", 0)
	var target := line.get_slice(" ", 1)
	if not (target == "/callback" or target.begins_with("/callback?")):
		_reply_google("Pagina no encontrada", "Not found", 404)
		_peer = null
		return

	var q := {}
	if target.contains("?"):
		for pair in target.get_slice("?", 1).split("&"):
			var kv := pair.split("=", true, 1)               # el código puede traer "=" dentro
			q[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else ""

	_handled = true               # deja de leer el socket antes de cualquier await
	if _state == "" or q.get("state", "") != _state:          # debe coincidir EXACTAMENTE
		_reply_google("Error", "State inválido", 400)
		_finish(false, "State inválido")
		return
	if q.has("error"):
		_reply_google("Error", "Inicio de sesión cancelado", 400)
		_finish(false, "Inicio de sesión cancelado")
		return
	var code := str(q.get("code", ""))
	if code == "":
		_reply_google("Error", "Falta el código de acceso", 400)
		_finish(false, "Falta el código de acceso")
		return

	var path := "/api/auth/desktop/exchange" if _desktop else "/api/auth/login/exchange"
	var body := {"code": code, "codeVerifier": _verifier}
	if _desktop:
		body["state"] = _state
	# auth=false: es un canje de un solo uso, no una petición que se pueda renovar y repetir.
	var r: Dictionary = await Api.request(HTTPClient.METHOD_POST, path, body, false)
	if not (r.ok and r.data is Dictionary and str(r.data.get("accessToken", "")) != ""):
		var why := "El intento venció o ya se usó: vuelve a iniciar sesión" if r.status == 401 \
				else "No se pudo completar el inicio de sesión"
		_reply_google("Error", why, 400)
		_finish(false, why)
		return
	_reply_google("login success", "Listo, ya puedes volver al juego.", 200)
	Session.set_tokens(str(r.data.get("accessToken", "")), str(r.data.get("refreshToken", "")))
	var ok: bool = await Session.load_profile()
	_finish(ok, "" if ok else "No se pudo cargar el perfil")

func _reply_google(title: String, body_message: String, code: int = 200) -> void:
	var is_ok := (code >= 200 and code < 300)

	# Colores para la etiqueta de estado (Azul si es OK, Rojo si es error)
	var badge_bg := "#a8c7fa" if is_ok else "#f2b8b5"
	var badge_color := "#041e49" if is_ok else "#601410"
	var status_label := "Completado" if is_ok else "Error %d" % code

	var html := GOOGLE_HTML_TEMPLATE \
			.replace("{TITLE}", title) \
			.replace("{BODY}", body_message) \
			.replace("{BADGE_BG}", badge_bg) \
			.replace("{BADGE_COLOR}", badge_color) \
			.replace("{STATUS_LABEL}", status_label)

	_reply(html, code)

func _reply(body: String, code: int) -> void:
	if _peer == null:
		return
	var status_text := "OK" if code == 200 else "Error"
	var resp := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
			% [code, status_text, body.to_utf8_buffer().size(), body]
	_peer.put_data(resp.to_utf8_buffer())
	_peer.disconnect_from_host()

func _finish(ok: bool, err: String) -> void:
	if _done: return
	_done = true
	_server.stop()
	_verifier = ""                # el verificador ya no sirve: no lo dejamos vivo
	finished.emit(ok, err)
