class_name LanDiscovery
extends Node
## Descarga CANDIDATA de la CA pública de un anfitrión LAN (guía §1.4, protocolo de descubrimiento 1).
##
## Es el ÚNICO sitio donde se tolera TLS sin autenticar (`TLSOptions.client_unsafe()`): por eso usa un
## HTTPRequest nuevo y exclusivo, destruido al terminar, sin credenciales (ni Authorization, ni cookies,
## ni JWT, ni OAuth/PKCE), con IP privada validada, sin redirecciones, 10 s de timeout, 32 KiB máximo y
## sin gzip. Nunca se reutiliza para Auth, Lobby, Game ni Google.
##
## Lo que devuelve NO está autenticado: solo detecta respuestas inconsistentes. Quien decide confiar es
## el jugador, comparando la huella con la que le comunicó el anfitrión por otro canal.
##
## fetch() → {"ok": true, "hash", "der", "ca_id"}  |  {"ok": false, "error": String, "retry": bool}
## `retry` = fallo de conexión (se puede reintentar); los demás se descartan sin reintentar.

const PATH := "/.well-known/pixelchiss/ca"
const MAX_BODY := 32768
const TIMEOUT := 10.0

func _fail(message: String, retry := false) -> Dictionary:
	return {"ok": false, "error": message, "retry": retry}

## Hasta `attempts` intentos con espera 1/2/4 s, solo para fallos de conexión.
func fetch_with_retry(host: String, port: int, attempts := 3) -> Dictionary:
	var result := {}
	for i in attempts:
		result = await fetch(host, port)
		if result.ok or not result.retry:
			return result
		if i < attempts - 1:
			await get_tree().create_timer(float(1 << i)).timeout
	return result

func fetch(host: String, port: int) -> Dictionary:
	if not Config.is_private_ipv4(host):
		return _fail("La CA solo se descarga de una IP privada de tu red.")
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.max_redirects = 0
	http.body_size_limit = MAX_BODY
	http.accept_gzip = false
	http.set_tls_options(TLSOptions.client_unsafe())
	add_child(http)
	if http.request("https://%s:%d%s" % [host, port, PATH], PackedStringArray(), HTTPClient.METHOD_GET) != OK:
		http.queue_free()
		return _fail("No se pudo iniciar la conexión.", true)
	var res = await http.request_completed             # [result, status, headers, body]
	http.queue_free()
	var result: int = res[0]
	var status: int = res[1]
	var body: PackedByteArray = res[3]
	if result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED or (status >= 300 and status < 400):
		return _fail("El anfitrión respondió con una redirección: se descarta.")
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return _fail("La respuesta es demasiado grande: se descarta.")
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("Sin respuesta de %s:%d." % [host, port], true)
	match status:
		200:
			return _parse(body)
		503:
			return _fail("El anfitrión no tiene lista su CA. Pídele que ejecute `lan.py cert-check` o `diagnose`.")
		400:
			return _fail("El anfitrión rechazó la solicitud de descubrimiento (400).")
		405:
			return _fail("El anfitrión rechazó el método de descubrimiento (405).")
		404, 401:
			return _fail("Ese puerto no entrega la CA. Comprueba IP y puerto, o que el anfitrión haya ejecutado `start --auto` con la versión actual.")
	return _fail("Respuesta inesperada del anfitrión (%d)." % status)

func _parse(body: PackedByteArray) -> Dictionary:
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		return _fail("La respuesta del anfitrión no es válida: se descarta.")
	var version: Variant = data.get("protocolVersion")
	if not ((version is int or version is float) and float(version) == 1.0):
		return _fail("Versión de protocolo de descubrimiento no soportada: se descarta.")
	var ca_id: Variant = data.get("caId")
	var fingerprint: Variant = data.get("fingerprintSha256")
	var pem: Variant = data.get("caPem")
	if not (ca_id is String and fingerprint is String and pem is String):
		return _fail("La respuesta del anfitrión está incompleta: se descarta.")
	if not str(ca_id).begins_with("sha256:") or not CaCert.is_hex64(str(ca_id).trim_prefix("sha256:")):
		return _fail("El identificador de la CA no es válido: se descarta.")
	if not CaCert.is_hex64(str(fingerprint)):
		return _fail("La huella de la CA no es válida: se descarta.")
	var der := CaCert.pem_to_der(str(pem))
	if der.is_empty():
		return _fail("El certificado no es un único bloque PEM válido: se descarta.")
	# Huella calculada LOCALMENTE sobre los bytes DER: es la que se muestra y la que nombra el archivo.
	var hash := CaCert.der_sha256(der)
	if hash != str(fingerprint) or hash != str(ca_id).trim_prefix("sha256:"):
		return _fail("La huella declarada no coincide con el certificado recibido: se descarta.")
	var problem := CaCert.validate_root(der)
	if problem != "":
		return _fail("La CA recibida no es válida: %s." % problem)
	return {"ok": true, "hash": hash, "der": der, "ca_id": str(ca_id)}
