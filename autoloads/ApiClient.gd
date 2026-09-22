extends Node
## Autoload (Singleton).
## Cliente REST del servidor mock (ver server/authRoutes.js y server/roomRoutes.js).
##
## IMPORTANTE: cambia BASE_URL por la IP/host real cuando pruebes en otro
## dispositivo o cuando el servidor esté desplegado (no puede ser
## "127.0.0.1" si el servidor corre en otra máquina o en el emulador).

const BASE_URL := "http://127.0.0.1:8080/api"

signal login_ok(data: Dictionary)
signal login_error(mensaje: String)

signal sala_creada(data: Dictionary)
signal sala_unida(data: Dictionary)
signal sala_error(codigo: String, mensaje: String)


func mock_login(nombre_google: String) -> void:
	# US-001/US-002: en el server real esto se reemplaza por el flujo OAuth
	# de Google; aquí solo se simula para poder probar el resto del flujo.
	_post(
		"/auth/mock-login",
		{"nombreGoogle": nombre_google},
		func(data: Dictionary):
			Sesion.player_id = data.get("playerId", "")
			Sesion.nombre = data.get("nombre", "")
			Sesion.token = data.get("token", "")
			login_ok.emit(data),
		func(_codigo: String, mensaje: String):
			login_error.emit(mensaje)
	)


func crear_sala() -> void:
	# US-003: crea la sala y devuelve el código que hay que compartir.
	_post(
		"/rooms",
		{"playerId": Sesion.player_id, "nombre": Sesion.nombre},
		func(data: Dictionary):
			Sesion.room_code = data.get("code", "")
			Sesion.es_host = true
			sala_creada.emit(data),
		func(codigo: String, mensaje: String):
			sala_error.emit(codigo, mensaje)
	)


func unirse_sala(codigo_sala: String) -> void:
	# US-004: se une a una sala existente por código.
	var codigo_normalizado := codigo_sala.strip_edges().to_upper()
	_post(
		"/rooms/%s/join" % codigo_normalizado,
		{"playerId": Sesion.player_id, "nombre": Sesion.nombre},
		func(data: Dictionary):
			Sesion.room_code = data.get("code", "")
			Sesion.es_host = false
			sala_unida.emit(data),
		func(codigo: String, mensaje: String):
			sala_error.emit(codigo, mensaje)
	)


## Helper interno: crea un HTTPRequest de usar-y-tirar por cada llamada,
## así varias peticiones pueden ir en paralelo sin pisarse entre ellas.
func _post(path: String, body: Dictionary, on_success: Callable, on_error: Callable) -> void:
	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(
		func(_result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray):
			var texto := body_bytes.get_string_from_utf8()
			var json := JSON.new()
			var data: Dictionary = {}
			if json.parse(texto) == OK and json.data is Dictionary:
				data = json.data

			if response_code >= 200 and response_code < 300:
				on_success.call(data)
			else:
				# El servidor no siempre manda {error: CODIGO, message: texto}.
				# En validaciones simples (ej. "faltan playerId y nombre")
				# manda solo {error: "texto legible"}, sin "message". Por eso
				# el mensaje cae de vuelta a "error" cuando "message" no viene.
				var codigo_error: String = data.get("error", "ERROR_DESCONOCIDO")
				var mensaje_error: String = data.get("message", codigo_error if data.has("error") else "Ocurrió un error inesperado.")
				on_error.call(codigo_error, mensaje_error)

			http.queue_free()
	)

	var headers := ["Content-Type: application/json"]
	var err := http.request(BASE_URL + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		on_error.call("ERROR_RED", "No se pudo conectar con el servidor. Revisa que esté corriendo.")
		http.queue_free()
