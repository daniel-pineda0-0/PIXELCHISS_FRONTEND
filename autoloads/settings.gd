extends Node
## Ajustes del jugador (audio, pantalla). Guarda en user://settings.cfg y los
## aplica al arrancar. La escena features/settings/settings_screen solo pinta
## los controles y llama aqui; no decide nada.

signal changed

const PATH := "user://settings.cfg"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUSES := [BUS_MASTER, BUS_MUSIC, BUS_SFX]

const DEFAULT_RESOLUTION := Vector2i(1280, 720)
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var volumes := {BUS_MASTER: 1.0, BUS_MUSIC: 1.0, BUS_SFX: 1.0}   # 0.0 a 1.0
var muted := false
var fullscreen := false
var vsync := true
var resolution := DEFAULT_RESOLUTION

func _ready() -> void:
	_ensure_buses()
	_load()
	apply_audio()
	apply_display()

# --- Cambios (los llama la pantalla de ajustes) ---

func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	apply_audio()
	changed.emit()

func set_muted(value: bool) -> void:
	muted = value
	apply_audio()
	changed.emit()

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_display()
	changed.emit()

func set_vsync(value: bool) -> void:
	vsync = value
	apply_display()
	changed.emit()

func set_resolution(value: Vector2i) -> void:
	resolution = value
	apply_display()
	changed.emit()

## Resoluciones que caben en el monitor actual (siempre hay al menos una).
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i] = []
	for res in RESOLUTIONS:
		if res.x <= screen.x and res.y <= screen.y:
			result.append(res)
	if result.is_empty():
		result.append(DEFAULT_RESOLUTION)
	return result

# --- Aplicar ---

func apply_audio() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx == -1:
			continue
		var volume: float = volumes[bus]
		AudioServer.set_bus_volume_db(idx, linear_to_db(volume))
		# En 0 el bus se silencia: linear_to_db(0) es -INF.
		AudioServer.set_bus_mute(idx, volume <= 0.0 or (bus == BUS_MASTER and muted))

@warning_ignore("integer_division")
func apply_display() -> void:
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var mode := DisplayServer.window_get_mode()
	if fullscreen:
		if mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if mode != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_size() == resolution:
		return                                   # ya esta a ese tamano
	DisplayServer.window_set_size(resolution)
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var offset := Vector2i((area.size.x - resolution.x) / 2, (area.size.y - resolution.y) / 2)
	DisplayServer.window_set_position(area.position + offset)

# --- Persistencia ---

func save() -> void:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "resolution", resolution)
	cfg.save(PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for bus in BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", bus, 1.0)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", false))
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	vsync = bool(cfg.get_value("display", "vsync", true))
	var saved = cfg.get_value("display", "resolution", DEFAULT_RESOLUTION)
	if saved is Vector2i and saved in available_resolutions():
		resolution = saved

## Music y SFX se crean aqui si el proyecto aun no tiene default_bus_layout.
func _ensure_buses() -> void:
	for bus in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, BUS_MASTER)	
