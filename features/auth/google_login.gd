class_name GoogleLogin extends Node
signal finished(ok: bool, error: String)

var GOOGLE_HTML_TEMPLATE := FileAccess.open("res://service/assets/google_reply_template.html.xml", FileAccess.READ).get_as_text()
var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _state := ""
var _done := false
var _handled := false

func start(timeout_sec := 120.0) -> void:
	_state = Crypto.new().generate_random_bytes(32).hex_encode()  # 64 chars hex
	var port := 0
	for p in range(49152, 49200):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if port == 0:
		_finish(false, "No hay puertos libres"); return
	OS.shell_open("%s/oauth2/authorization/google?client_state=%s&client_port=%d"
			% [Config.BASE_URL, _state, port])
	get_tree().create_timer(timeout_sec).timeout.connect(
			func(): _finish(false, "Tiempo de espera agotado"))

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
	if not target.begins_with("/callback?"):
		_reply_google("Pagina no encontrada", "Not found", 404)
		_peer = null
		return

	var q := {}
	for pair in target.get_slice("?", 1).split("&"):
		q[pair.get_slice("=", 0)] = pair.get_slice("=", 1).uri_decode()

	_handled = true               # deja de leer el socket antes de cualquier await
	if q.get("state", "") != _state:
		_reply_google("Error","State inválido", 400)
		_finish(false, "State inválido")
		return

	_reply_google("login success","Listo, ya puedes volver al juego.", 200)
	Session.set_tokens(q.get("accessToken", ""), q.get("refreshToken", ""))
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
	var status_text := "OK" if code == 200 else "Error"
	var resp := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" \
			% [code, status_text, body.to_utf8_buffer().size(), body]
	_peer.put_data(resp.to_utf8_buffer())
	_peer.disconnect_from_host()

func _finish(ok: bool, err: String) -> void:
	if _done: return
	_done = true
	_server.stop()
	finished.emit(ok, err)
