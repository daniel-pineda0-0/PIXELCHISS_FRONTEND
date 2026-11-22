extends Node

func request(method: int, path: String, body: Variant = null,
		auth := true, retry := true) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := ["Content-Type: application/json"]
	if auth and Session.access_token != "":
		headers.append("Authorization: Bearer " + Session.access_token)
	var payload := "" if body == null else JSON.stringify(body)
	if http.request(Config.BASE_URL + path, headers, method, payload) != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": null}
	var res = await http.request_completed
	http.queue_free()
	var status: int = res[1]
	var text: String = res[3].get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if status == 401 and auth and retry and await Session.refresh():
		return await request(method, path, body, auth, false)
	return {"ok": status >= 200 and status < 300, "status": status, "data": data}

## ¿Responde el Gateway en `base_url`? GET /actuator/health, sin JWT (guía §1.1).
## {"ok": bool, "status": int}: status 0 = no hubo respuesta HTTP (host caído, IP errónea, timeout).
func ping(base_url: String, timeout := 5.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	if http.request(base_url + "/actuator/health") != OK:
		http.queue_free()
		return {"ok": false, "status": 0}
	var res = await http.request_completed       # [result, status, headers, body]
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0}
	return {"ok": res[1] == 200, "status": int(res[1])}

## Espera a que el servidor conteste, con reintentos de espera creciente: justo tras arrancar
## puede dar 500/502/503 transitorios mientras Eureka registra los servicios (guía §1.1).
## Un 4xx/404 no se reintenta: ahí hay otro servicio, no el Gateway.
func wait_for_server(base_url: String, attempts := 2, timeout := 4.0) -> bool:
	for i in attempts:
		var r: Dictionary = await ping(base_url, timeout)
		if r.ok:
			return true
		var status: int = r.status
		if status != 0 and status < 500:
			return false
		if i < attempts - 1:
			await get_tree().create_timer(0.6 * (i + 1)).timeout
	return false
