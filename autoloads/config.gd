extends Node
## Dirección del servidor (Gateway) y confianza TLS de la LAN.
##
## Dos modos (guía §1.4):
##   · Local: http://127.0.0.1:8080 y ws://127.0.0.1:8080/api/game/ws. Sin CA ni descubrimiento.
##     Se usa 127.0.0.1 y NO "localhost" (Compose publica solo en loopback IPv4).
##   · LAN: https://<IPv4 privada>:8443 y wss://.../api/game/ws, con TLS estricto contra la CA del
##     anfitrión. La CA se descarga una vez del propio Gateway (LanDiscovery), el jugador compara su
##     huella SHA-256 con la que le dio el anfitrión, y se guarda en `user://lan-trust/`.
##     Nunca se usa TLSOptions.client_unsafe() fuera de esa descarga aislada.
##
## La dirección y el perfil activo se guardan en `user://server.cfg`.

const DEFAULT_BASE_URL := "http://127.0.0.1:8080"
const DEFAULT_HTTP_PORT := 8080
const DEFAULT_HTTPS_PORT := 8443
const PATH := "user://server.cfg"
const TRUST_DIR := "user://lan-trust"
const TRUST_INDEX := "user://lan-trust/index.cfg"

var BASE_URL := DEFAULT_BASE_URL     # http(s)://host:puerto, sin "/" final
var WS_URL := ""                     # ws(s)://host:puerto/api/game/ws
var ca_hash := ""                    # SHA-256 (DER) de la CA del perfil activo; "" en modo local

var _tls_cache := {}                 # hash -> TLSOptions ya construido y revalidado

func _ready() -> void:
	var cfg := ConfigFile.new()
	var saved := DEFAULT_BASE_URL
	var saved_ca := ""
	if cfg.load(PATH) == OK:
		var parsed := parse_address(str(cfg.get_value("server", "base_url", DEFAULT_BASE_URL)))
		if parsed.error == "":
			saved = parsed.base_url
			saved_ca = str(cfg.get_value("server", "ca_hash", ""))
	_apply(saved, saved_ca)

func _apply(base_url: String, hash: String) -> void:
	BASE_URL = base_url
	ca_hash = hash if base_url.begins_with("https://") else ""
	WS_URL = base_url.replace("https://", "wss://").replace("http://", "ws://") + "/api/game/ws"

## Fija y recuerda el servidor. En LAN, `hash` es la CA ya confirmada por el jugador.
func set_server(base_url: String, hash := "") -> void:
	_apply(base_url, hash)
	var cfg := ConfigFile.new()
	cfg.set_value("server", "base_url", BASE_URL)
	cfg.set_value("server", "ca_hash", ca_hash)
	cfg.save(PATH)

func is_lan() -> bool:
	return BASE_URL.begins_with("https://")

# --- Direcciones -----------------------------------------------------------------------------------

static func _ipv4_parts(host: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var pieces := host.split(".")
	if pieces.size() != 4:
		return out
	for piece in pieces:
		if piece.is_empty() or piece.length() > 3 or not piece.is_valid_int() or piece.begins_with("+") or piece.begins_with("-"):
			return PackedInt32Array()
		var value := int(piece)
		if value < 0 or value > 255:
			return PackedInt32Array()
		out.append(value)
	return out

## IPv4 privada de LAN (10/8, 172.16/12, 192.168/16), no loopback.
static func is_private_ipv4(host: String) -> bool:
	var p := _ipv4_parts(host)
	if p.size() != 4:
		return false
	return p[0] == 10 or (p[0] == 172 and p[1] >= 16 and p[1] <= 31) or (p[0] == 192 and p[1] == 168)

static func is_loopback(host: String) -> bool:
	var p := _ipv4_parts(host)
	return p.size() == 4 and p[0] == 127

## Lo que escribe el jugador → {error, base_url, host, port, lan}. `error` vacío si es válida.
##   "192.168.1.5"            → https://192.168.1.5:8443   (IP privada: LAN, siempre HTTPS)
##   "192.168.1.5:9443"       → https://192.168.1.5:9443
##   "127.0.0.1" / "localhost" → http://127.0.0.1:8080     (local)
## Se descarta cualquier ruta. No se admite HTTP para IPs de LAN ni nombres de equipo.
static func parse_address(text: String) -> Dictionary:
	var result := {"error": "", "base_url": "", "host": "", "port": 0, "lan": false}
	var t := text.strip_edges()
	var scheme := ""
	if t.begins_with("https://"):
		scheme = "https"
		t = t.substr(8)
	elif t.begins_with("http://"):
		scheme = "http"
		t = t.substr(7)
	elif t.contains("://"):
		result.error = "Dirección no válida. Ejemplo: 192.168.1.5"
		return result
	t = t.get_slice("/", 0)
	if t.count(":") > 1:
		result.error = "Solo se admiten direcciones IPv4."
		return result
	var host := t
	var port := 0
	if t.contains(":"):
		host = t.get_slice(":", 0)
		var port_text := t.get_slice(":", 1)
		if not port_text.is_valid_int():
			result.error = "El puerto no es válido."
			return result
		port = int(port_text)
		if port < 1 or port > 65535:
			result.error = "El puerto debe estar entre 1 y 65535."
			return result
	if host.to_lower() == "localhost":
		host = "127.0.0.1"
	if host.is_empty() or _ipv4_parts(host).size() != 4:
		result.error = "Escribe la IP del anfitrión, p. ej. 192.168.1.5."
		return result
	var lan := false
	if is_loopback(host):
		if scheme == "https":
			result.error = "El modo local usa HTTP en 127.0.0.1."
			return result
	elif is_private_ipv4(host):
		if scheme == "http":
			result.error = "No uses HTTP con una IP de la red local: se conecta por HTTPS. Escribe solo la IP."
			return result
		lan = true
	else:
		result.error = "Solo se admite 127.0.0.1 (este equipo) o una IP privada de tu red (10.x, 172.16-31.x, 192.168.x)."
		return result
	if port == 0:
		port = DEFAULT_HTTPS_PORT if lan else DEFAULT_HTTP_PORT
	result.host = host
	result.port = port
	result.lan = lan
	result.base_url = "%s://%s:%d" % ["https" if lan else "http", host, port]
	return result

## Compatibilidad: URL base canónica o "" si no es válida.
static func normalize(text: String) -> String:
	return str(parse_address(text).base_url)

# --- Almacén de confianza (guía §1.4) -------------------------------------------------------------

func _cert_path(hash: String) -> String:
	return "%s/%s.crt" % [TRUST_DIR, hash]

## Lee y REVALIDA una CA guardada: el nombre es el hash del DER recalculado, la estructura de raíz y
## la vigencia. Devuelve {} si falta, está alterada o venció.
func _load_trusted(hash: String) -> Dictionary:
	if not CaCert.is_hex64(hash) or not FileAccess.file_exists(_cert_path(hash)):
		return {}
	var pem := FileAccess.get_file_as_string(_cert_path(hash))
	var der := CaCert.pem_to_der(pem)
	if der.is_empty() or CaCert.der_sha256(der) != hash:
		return {}
	if CaCert.validate_root(der) != "":
		return {}
	var cert := X509Certificate.new()
	if cert.load_from_string(pem) != OK:
		return {}
	return {"cert": cert, "der": der}

## ¿Esta CA ya fue verificada por el jugador y sigue siendo válida?
func trust_has(hash: String) -> bool:
	return not _load_trusted(hash).is_empty()

## TLS estricto para una CA confiable: TLSOptions.client(ca), sin common_name_override.
func tls_for(hash: String) -> TLSOptions:
	if _tls_cache.has(hash):
		return _tls_cache[hash]
	var loaded := _load_trusted(hash)
	if loaded.is_empty():
		return null
	var options := TLSOptions.client(loaded.cert)
	_tls_cache[hash] = options
	return options

## TLS de la conexión activa; null en modo local (o si la CA del perfil ya no es válida: entonces
## HTTPRequest/WebSocket usan la confianza del sistema, que no acepta la CA propia, y falla cerrado).
func tls_options() -> TLSOptions:
	if not is_lan() or ca_hash == "":
		return null
	return tls_for(ca_hash)

func _index() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(TRUST_INDEX)
	return cfg

func _write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):                  # en Windows rename no pisa un archivo existente
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK

## Guarda una CA que el jugador acaba de confirmar. El nombre del archivo sale del hash CALCULADO
## sobre el DER ya validado, nunca del JSON. Escritura atómica. Devuelve false si falla.
func trust_add(der: PackedByteArray, ca_id: String, host_key: String) -> bool:
	var hash := CaCert.der_sha256(der)
	if hash == "" or CaCert.validate_root(der) != "":
		return false
	DirAccess.make_dir_recursive_absolute(TRUST_DIR)
	if not _write_atomic(_cert_path(hash), CaCert.der_to_pem(der)):
		return false
	var idx := _index()
	if not idx.has_section_key(hash, "confirmed_at"):
		idx.set_value(hash, "confirmed_at", Time.get_datetime_string_from_system(true))
	idx.set_value(hash, "ca_id", ca_id)
	trust_note_host(hash, host_key, idx)
	_tls_cache.erase(hash)
	return true

## Recuerda que esta CA se usó con `host_key` ("ip:puerto"). Sirve para detectar una CA distinta en
## una IP conocida. `idx` permite agrupar la escritura con trust_add().
func trust_note_host(hash: String, host_key: String, idx: ConfigFile = null) -> void:
	var cfg := idx if idx != null else _index()
	var hosts: Array = cfg.get_value(hash, "hosts", [])
	if not hosts.has(host_key):
		hosts.append(host_key)
	cfg.set_value(hash, "hosts", hosts)
	DirAccess.make_dir_recursive_absolute(TRUST_DIR)
	cfg.save(TRUST_INDEX)

## Hash de la CA guardada que se usó antes con esta IP:puerto ("" si ninguna). Si el anfitrión
## presenta OTRA CA en una dirección conocida, la pantalla debe exigir una comparación nueva.
func profile_for_host(host_key: String) -> String:
	var cfg := _index()
	for hash in cfg.get_sections():
		var hosts: Array = cfg.get_value(hash, "hosts", [])
		if hosts.has(host_key) and trust_has(hash):
			return hash
	return ""

## «Olvidar CA»: borra su entrada; la próxima conexión exigirá verificarla de nuevo.
func trust_remove(hash: String) -> void:
	if not CaCert.is_hex64(hash):
		return
	if FileAccess.file_exists(_cert_path(hash)):
		DirAccess.remove_absolute(_cert_path(hash))
	var cfg := _index()
	if cfg.has_section(hash):
		cfg.erase_section(hash)
		cfg.save(TRUST_INDEX)
	_tls_cache.erase(hash)
