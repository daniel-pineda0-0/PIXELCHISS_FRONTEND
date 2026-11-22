extends Node2D
## Escena de la partida. Fase 0: carga el mundo del mapa elegido en el lobby,
## descarga el tablero del servidor y abre la conexión en tiempo real.
## US-020: BoardView dibuja los chunks y las fichas en el mundo, y GameUI el
## minimapa.
## Fase 2 (US-006, US-011, US-013, US-010): BoardView muestra los movimientos
## legales del servidor y manda el elegido; GameUI lleva el turno, los dados y
## los avisos. Aquí solo se conectan las señales de GameNet a cada uno.

const WORLDS := {
	"classic": "res://features/game/world_clasic.tscn",
	"science": "res://features/game/world_cience.tscn",
}

var world: Node2D
var view: BoardView
@onready var _debug: Label = %DebugLabel

func _ready() -> void:
	if GameState.game_id == "":
		GameState.leave_game.call_deferred("No hay una partida en curso")
		return
	_load_world(GameState.map_id)
	_build_board_view()
	_setup_debug_overlay()
	GameNet.fatal.connect(_on_fatal)
	GameNet.events_received.connect(_on_events)
	for signal_ref in [GameNet.state_changed, GameNet.status_changed, GameNet.busy_changed]:
		signal_ref.connect(func(_arg = null): _refresh_debug())
	if not await Board.ensure_loaded():
		GameState.leave_game(Board.load_error)
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

func _build_board_view() -> void:
	view = BoardView.new()
	view.name = "BoardView"
	add_child(view)
	view.setup(world, $Pieces, $Halos, $Targets)
	GameNet.state_changed.connect(view.refresh)
	GameNet.legal_moves_changed.connect(view.on_overlays_changed)
	GameNet.busy_changed.connect(view.on_overlays_changed)
	GameNet.events_received.connect(view.handle_events)
	var ui := get_node_or_null("GameUI")
	if ui != null and ui.has_signal("view_step"):
		ui.connect("view_step", view.step_focus)
	if not GameNet.state.is_empty():
		view.refresh(GameNet.state)

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

func _setup_debug_overlay() -> void:
	if OS.is_debug_build():
		return
	$DebugOverlay.queue_free()       # el texto de depuración solo existe en debug
	_debug = null

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
