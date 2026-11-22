extends Node
signal logged_in
signal logged_out

const PATH := "user://session.cfg"
var access_token := ""
var refresh_token := ""
var profile: Dictionary = {}

func set_tokens(access: String, refresh_tok: String) -> void:
	access_token = access
	refresh_token = refresh_tok
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh", refresh_tok)
	cfg.save_encrypted_pass(PATH, OS.get_unique_id())  # ofuscación, no seguridad real

func try_restore() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(PATH, OS.get_unique_id()) != OK:
		return false
	refresh_token = cfg.get_value("auth", "refresh", "")
	return await refresh() and await load_profile()

## Una sola renovación a la vez (guía §1.3): si varias peticiones reciben 401 juntas, solo la
## primera llama a /api/refresh y las demás esperan y comparten su resultado.
signal _refresh_finished(ok: bool)
var _refreshing := false

func refresh() -> bool:
	if refresh_token == "":
		return false
	if _refreshing:
		return await _refresh_finished
	_refreshing = true
	var ok := await _do_refresh()
	_refreshing = false
	_refresh_finished.emit(ok)
	return ok

func _do_refresh() -> bool:
	var r = await Api.request(HTTPClient.METHOD_POST, "/api/refresh",
			{"refreshToken": refresh_token}, false)
	if not r.ok:
		if r.status == 401:
			clear()                       # el refresh ya no vale: sesión fuera y pedir login
		return false
	access_token = r.data.accessToken     # el refresh NO rota: sigue siendo el mismo
	return true

func load_profile() -> bool:
	var r = await Api.request(HTTPClient.METHOD_GET, "/api/auth/me")
	if not r.ok:
		return false
	profile = r.data
	logged_in.emit()
	return true

func logout() -> void:
	if refresh_token != "":
		await Api.request(HTTPClient.METHOD_POST, "/api/logout",
				{"refreshToken": refresh_token}, false)
	clear()

func clear() -> void:
	access_token = ""; refresh_token = ""; profile = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	logged_out.emit()

func is_logged_in() -> bool:
	return access_token != "" and not profile.is_empty()
