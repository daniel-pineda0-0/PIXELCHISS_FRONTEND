extends Node
## Dirección del servidor (Gateway). Se guarda en `user://server.cfg` para recordarla entre
## ejecuciones; si no hay ninguna guardada se usa la local. La pantalla de servidor
## (features/server) la cambia cuando el cliente no logra conectar.
##
## Se usa 127.0.0.1 y NO "localhost": Compose publica solo en loopback IPv4 y "localhost" puede
## resolverse a ::1 y no conectar (guía §1.1).
## Modo LAN (guía §1.4): serían https://<IP>:8443 y wss://<IP>:8443/api/game/ws, con el ca.crt del
## anfitrión verificado por huella y TLSOptions.client(ca). No está implementado: aquí solo se
## acepta la dirección; un certificado propio no se podrá verificar todavía.

const DEFAULT_BASE_URL := "http://127.0.0.1:8080"
const DEFAULT_HTTP_PORT := 8080
const DEFAULT_HTTPS_PORT := 8443
const PATH := "user://server.cfg"

var BASE_URL := DEFAULT_BASE_URL     # http(s)://host:puerto, sin "/" final
var WS_URL := ""                     # ws(s)://host:puerto/api/game/ws

func _ready() -> void:
	var cfg := ConfigFile.new()
	var saved := DEFAULT_BASE_URL
	if cfg.load(PATH) == OK:
		saved = normalize(str(cfg.get_value("server", "base_url", DEFAULT_BASE_URL)))
		if saved == "":
			saved = DEFAULT_BASE_URL
	_apply(saved)

func _apply(base_url: String) -> void:
	BASE_URL = base_url
	WS_URL = base_url.replace("https://", "wss://").replace("http://", "ws://") + "/api/game/ws"

## Fija y recuerda la dirección. `base_url` debe venir de normalize().
func set_server(base_url: String) -> void:
	_apply(base_url)
	var cfg := ConfigFile.new()
	cfg.set_value("server", "base_url", base_url)
	cfg.save(PATH)

## Lo que escribe el jugador → URL base canónica, o "" si no es una dirección válida.
##   "192.168.1.5"          → http://192.168.1.5:8080
##   "192.168.1.5:9000"     → http://192.168.1.5:9000
##   "https://10.0.0.2"     → https://10.0.0.2:8443
##   "localhost"            → http://127.0.0.1:8080
## Se descarta cualquier ruta; solo se conservan esquema, equipo y puerto.
static func normalize(text: String) -> String:
	var t := text.strip_edges()
	var scheme := "http"
	if t.begins_with("https://"):
		scheme = "https"
		t = t.substr(8)
	elif t.begins_with("http://"):
		t = t.substr(7)
	elif t.contains("://"):
		return ""                                    # otro esquema (ftp://, ws://...)
	t = t.get_slice("/", 0)
	if t.count(":") > 1:
		return ""                                    # IPv6 y similares: no soportado
	var host := t
	var port := 0
	if t.contains(":"):
		host = t.get_slice(":", 0)
		var port_text := t.get_slice(":", 1)
		if not port_text.is_valid_int():
			return ""
		port = int(port_text)
		if port < 1 or port > 65535:
			return ""
	if host.to_lower() == "localhost":
		host = "127.0.0.1"
	var valid := RegEx.new()
	valid.compile("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$")
	if host == "" or valid.search(host) == null:
		return ""
	if port == 0:
		port = DEFAULT_HTTPS_PORT if scheme == "https" else DEFAULT_HTTP_PORT
	return "%s://%s:%d" % [scheme, host, port]
