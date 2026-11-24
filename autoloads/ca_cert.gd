class_name CaCert
extends RefCounted
## Utilidades para la CA pública de un anfitrión LAN (guía §1.4): PEM → DER, huella SHA-256 sobre los
## bytes DER y un validador estructural de la raíz.
##
## `X509Certificate.load_from_string()` solo PARSEA el PEM: no comprueba que sea una raíz
## autofirmada, vigente y con CA:true. Este validador lo hace leyendo el DER a mano. Comprueba:
##   · un único bloque PEM CERTIFICATE y DER sin bytes sobrantes
##   · emisor == sujeto (raíz autofirmada)
##   · vigencia (notBefore <= ahora <= notAfter)
##   · Basic Constraints presente con CA:true, y Key Usage con keyCertSign si existe
## NO verifica la firma criptográfica del certificado sobre sí mismo (GDScript no expone ese
## cálculo para todos los algoritmos). La confianza real la da la comparación de la huella por
## parte del jugador y el TLS estricto en cada conexión; esto es defensa adicional, no sustituye
## al "validador revisado" que pide la guía.

const BEGIN := "-----BEGIN CERTIFICATE-----"
const END := "-----END CERTIFICATE-----"
const OID_BASIC_CONSTRAINTS := [0x55, 0x1D, 0x13]   # 2.5.29.19
const OID_KEY_USAGE := [0x55, 0x1D, 0x0F]           # 2.5.29.15

## PEM con exactamente un bloque CERTIFICATE → bytes DER. Vacío si no es válido.
static func pem_to_der(pem: String) -> PackedByteArray:
	var text := pem.strip_edges()
	if text.count("-----BEGIN") != 1 or text.count("-----END") != 1:
		return PackedByteArray()
	if not text.begins_with(BEGIN) or not text.ends_with(END):
		return PackedByteArray()
	var body := text.substr(BEGIN.length(), text.length() - BEGIN.length() - END.length())
	body = body.replace("\r", "").replace("\n", "").replace(" ", "").replace("\t", "")
	var valid := RegEx.new()
	valid.compile("^[A-Za-z0-9+/]+={0,2}$")
	if body.length() % 4 != 0 or valid.search(body) == null:
		return PackedByteArray()
	return Marshalls.base64_to_raw(body)

## DER → PEM canónico (64 columnas). Es lo que se guarda: sale de los bytes ya validados, no del
## texto que mandó el servidor.
static func der_to_pem(der: PackedByteArray) -> String:
	var b64 := Marshalls.raw_to_base64(der)
	var lines := PackedStringArray([BEGIN])
	var i := 0
	while i < b64.length():
		lines.append(b64.substr(i, 64))
		i += 64
	lines.append(END)
	return "\n".join(lines) + "\n"

## SHA-256 de los bytes DER (no del texto PEM), en hexadecimal minúscula. "" si está vacío.
static func der_sha256(der: PackedByteArray) -> String:
	if der.is_empty():
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(der)
	return ctx.finish().hex_encode()

## 64 hex en minúscula (formato de `fingerprintSha256` y del sufijo de `caId`).
static func is_hex64(text: String) -> bool:
	var valid := RegEx.new()
	valid.compile("^[0-9a-f]{64}$")
	return valid.search(text) != null

## Para leerlo: grupos de 8 caracteres separados por espacio.
static func spaced(hash: String) -> String:
	var parts := PackedStringArray()
	var i := 0
	while i < hash.length():
		parts.append(hash.substr(i, 8))
		i += 8
	return " ".join(parts)

## Una etiqueta DER: [tag, inicio_del_valor, fin] o [] si está mal formada. Solo longitudes
## definidas (DER) y tags de un byte.
static func _tlv(buf: PackedByteArray, off: int, limit: int) -> Array:
	if off < 0 or off + 2 > limit:
		return []
	var tag := int(buf[off])
	if (tag & 0x1F) == 0x1F:
		return []
	var first := int(buf[off + 1])
	var length := 0
	var header := 2
	if first < 0x80:
		length = first
	else:
		var n := first & 0x7F
		if n == 0 or n > 3 or off + 2 + n > limit:
			return []
		for i in n:
			length = (length << 8) | int(buf[off + 2 + i])
		header = 2 + n
	var start := off + header
	var end := start + length
	if end > limit:
		return []
	return [tag, start, end]

static func _digits(s: String) -> bool:
	if s.is_empty():
		return false
	for c in s:
		if c < "0" or c > "9":
			return false
	return true

## UTCTime (0x17) o GeneralizedTime (0x18) en UTC → segundos Unix, o -1 si no es válido.
static func _parse_time(buf: PackedByteArray, tag: int, start: int, end: int) -> int:
	var s := buf.slice(start, end).get_string_from_ascii()
	if not s.ends_with("Z"):
		return -1
	var year := 0
	var rest := ""
	if tag == 0x17 and s.length() == 13:
		var yy := s.substr(0, 2)
		if not _digits(yy):
			return -1
		year = 2000 + int(yy) if int(yy) < 50 else 1900 + int(yy)
		rest = s.substr(2, 10)
	elif tag == 0x18 and s.length() == 15:
		var yyyy := s.substr(0, 4)
		if not _digits(yyyy):
			return -1
		year = int(yyyy)
		rest = s.substr(4, 10)
	else:
		return -1
	if not _digits(rest):
		return -1
	return Time.get_unix_time_from_datetime_dict({
		"year": year, "month": int(rest.substr(0, 2)), "day": int(rest.substr(2, 2)),
		"hour": int(rest.substr(4, 2)), "minute": int(rest.substr(6, 2)), "second": int(rest.substr(8, 2)),
	})

## "" si el DER es una raíz autofirmada vigente con CA:true; si no, el motivo (en español).
## Misma lógica que el validador de referencia probado contra certificados reales.
static func validate_root(der: PackedByteArray) -> String:
	var illegible := "certificado ilegible"
	var bad_structure := "estructura inválida"
	var n := der.size()
	var t := _tlv(der, 0, n)
	if t.is_empty():
		return illegible
	if t[0] != 0x30:
		return "no es un certificado X.509"
	if t[2] != n:
		return "el certificado trae bytes de más"
	var cert_start: int = t[1]
	var cert_end: int = t[2]
	t = _tlv(der, cert_start, cert_end)                    # tbsCertificate
	if t.is_empty():
		return illegible
	if t[0] != 0x30:
		return bad_structure
	var tbs_end: int = t[2]
	var p: int = t[1]
	t = _tlv(der, p, tbs_end)
	if t.is_empty():
		return illegible
	if t[0] == 0xA0:                                      # versión [0]
		p = t[2]
		t = _tlv(der, p, tbs_end)
		if t.is_empty():
			return illegible
	if t[0] != 0x02:                                      # serial
		return bad_structure
	p = t[2]
	t = _tlv(der, p, tbs_end)
	if t.is_empty():
		return illegible
	if t[0] != 0x30:                                      # algoritmo de firma
		return bad_structure
	p = t[2]
	var issuer_start := p
	t = _tlv(der, p, tbs_end)
	if t.is_empty():
		return illegible
	if t[0] != 0x30:                                      # emisor
		return bad_structure
	var issuer := der.slice(issuer_start, t[2])
	p = t[2]
	t = _tlv(der, p, tbs_end)
	if t.is_empty():
		return illegible
	if t[0] != 0x30:                                      # validez
		return bad_structure
	var validity_end: int = t[2]
	var t1 := _tlv(der, t[1], validity_end)
	if t1.is_empty():
		return illegible
	var not_before := _parse_time(der, t1[0], t1[1], t1[2])
	var t2 := _tlv(der, t1[2], validity_end)
	if t2.is_empty():
		return illegible
	var not_after := _parse_time(der, t2[0], t2[1], t2[2])
	if not_before < 0 or not_after < 0:
		return illegible
	p = validity_end
	var subject_start := p
	t = _tlv(der, p, tbs_end)
	if t.is_empty():
		return illegible
	if t[0] != 0x30:                                      # sujeto
		return bad_structure
	var subject := der.slice(subject_start, t[2])
	p = t[2]
	t = _tlv(der, p, tbs_end)
	if t.is_empty():
		return illegible
	if t[0] != 0x30:                                      # clave pública
		return bad_structure
	p = t[2]
	var ext_start := -1
	var ext_end := -1
	while p < tbs_end:                                    # uniqueIDs opcionales y extensiones [3]
		t = _tlv(der, p, tbs_end)
		if t.is_empty():
			return illegible
		if t[0] == 0xA3:
			ext_start = t[1]
			ext_end = t[2]
		p = t[2]
	if issuer != subject:
		return "no es una raíz autofirmada (emisor distinto del sujeto)"
	var now := int(Time.get_unix_time_from_system())
	if now < not_before:
		return "la CA aún no es válida"
	if now > not_after:
		return "la CA está vencida"
	if ext_start < 0:
		return "falta Basic Constraints CA:true"
	t = _tlv(der, ext_start, ext_end)                     # SEQUENCE OF Extension
	if t.is_empty():
		return illegible
	if t[0] != 0x30:
		return "extensiones inválidas"
	var list_end: int = t[2]
	p = t[1]
	var is_ca := false
	var has_ku := false
	var key_cert_sign := false
	while p < list_end:
		var ext := _tlv(der, p, list_end)                 # Extension
		if ext.is_empty():
			return illegible
		if ext[0] != 0x30:
			return "extensiones inválidas"
		var ext_inner_end: int = ext[2]
		var oid := _tlv(der, ext[1], ext_inner_end)
		if oid.is_empty():
			return illegible
		if oid[0] != 0x06:
			return "extensiones inválidas"
		var oid_bytes := der.slice(oid[1], oid[2])
		var value := _tlv(der, oid[2], ext_inner_end)
		if value.is_empty():
			return illegible
		if value[0] == 0x01:                              # critical (opcional)
			value = _tlv(der, value[2], ext_inner_end)
			if value.is_empty():
				return illegible
		if value[0] != 0x04:                              # OCTET STRING
			return "extensiones inválidas"
		if oid_bytes == PackedByteArray(OID_BASIC_CONSTRAINTS):
			var bc := _tlv(der, value[1], value[2])
			if bc.is_empty() or bc[0] != 0x30:
				return "Basic Constraints inválido"
			if bc[1] < bc[2]:
				var flag := _tlv(der, bc[1], bc[2])
				if flag.is_empty():
					return illegible
				is_ca = flag[0] == 0x01 and flag[2] > flag[1] and der[flag[1]] != 0
		elif oid_bytes == PackedByteArray(OID_KEY_USAGE):
			has_ku = true
			var ku := _tlv(der, value[1], value[2])
			if ku.is_empty() or ku[0] != 0x03 or ku[2] - ku[1] < 2:
				return "Key Usage inválido"
			key_cert_sign = (int(der[ku[1] + 1]) & 0x04) != 0
		p = ext_inner_end
	if not is_ca:
		return "no es una CA (Basic Constraints CA:true)"
	if has_ku and not key_cert_sign:
		return "la CA no puede firmar certificados (Key Usage)"
	return ""
