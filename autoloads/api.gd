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
