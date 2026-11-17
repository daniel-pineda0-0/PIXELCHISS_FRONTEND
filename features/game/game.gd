extends Node2D
## Escena de la partida. Fase 0: carga el mundo del mapa elegido en el lobby,
## descarga el tablero del servidor y abre la conexión en tiempo real.
## Las fichas, el HUD y las animaciones se conectan después a las señales de
## GameNet (US-020 en adelante).

const WORLDS := {
	"classic": "res://features/game/world_clasic.tscn",
	"science": "res://features/game/world_cience.tscn",
}

var world: Node2D
var _debug: Label

func _ready() -> void:
	if GameState.game_id == "":
		GameState.leave_game.call_deferred("No hay una partida en curso")
		return
	_load_world(GameState.map_id)
	_build_debug_overlay()
	GameNet.fatal.connect(_on_fatal)
	GameNet.events_received.connect(_on_events)
	for signal_ref in [GameNet.state_changed, GameNet.status_changed, GameNet.busy_changed]:
		signal_ref.connect(func(_arg = null): _refresh_debug())
	if not await Board.ensure_loaded():
		GameState.leave_game("No se pudo cargar el tablero")
		return
	_refresh_debug()
	GameNet.join(GameState.game_id)

func _exit_tree() -> void:
	# Si la escena se cierra por cualquier otro camino, no deja el socket abierto.
	if GameNet.status != GameNet.Status.IDLE and GameState.state != GameState.State.GAME:
		GameNet.leave()

func _load_world(map_id: String) -> void:
	if not WORLDS.has(map_id):
		push_warning("Mapa desconocido '%s', se usa classic" % map_id)
	var packed := load(WORLDS.get(map_id, WORLDS["classic"])) as PackedScene
	world = packed.instantiate()
	add_child(world)
	move_child(world, 0)      # el HUD (GameUI es CanvasLayer) siempre queda encima

func _on_fatal(_code: String, message: String) -> void:
	GameState.leave_game(message)

func _on_events(events: Array, version: int) -> void:
	if not OS.is_debug_build():
		return
	var names := PackedStringArray()
	for e in events:
		names.append(str(e.get("type", "?")))
	print("[game] v%d %s" % [version, ", ".join(names)])

# --- Overlay de depuración (solo builds de debug) ---

func _build_debug_overlay() -> void:
	if not OS.is_debug_build():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	_debug = Label.new()
	_debug.position = Vector2(4, 4)
	_debug.add_theme_font_size_override("font_size", 8)
	_debug.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug.add_theme_constant_override("outline_size", 3)
	layer.add_child(_debug)
	add_child(layer)

func _refresh_debug() -> void:
	if _debug == null:
		return
	var lines := PackedStringArray()
	lines.append("red: %s%s" % [GameNet.status_name(), " (ocupado)" if GameNet.busy else ""])
	if Board.is_loaded:
		lines.append("tablero %s: %d casillas, %d de recorrido, %d seguros" % [
				Board.layout, Board.cell_count, Board.track_count, Board.safe_ids.size()])
	var s := GameNet.state
	if not s.is_empty():
		lines.append("v%d %s mapa=%s" % [int(s.get("version", 0)), str(s.get("status", "")), str(s.get("mapId", ""))])
		var turn: Variant = s.get("turn")
		if turn is Dictionary:
			lines.append("turno: %s%s" % [str(turn.get("playerId", "")), " (yo)" if GameNet.is_my_turn() else ""])
	_debug.text = "\n".join(lines)
