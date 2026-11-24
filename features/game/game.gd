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
	_update_background(GameNet.state)         # solo el primer fondo; despues manda la zona de la camara
	view.zone_blend.connect(Callable($GameBackground, "set_blend"))
	GameNet.events_received.connect(_on_events)
	for signal_ref in [GameNet.state_changed, GameNet.status_changed, GameNet.busy_changed]:
		signal_ref.connect(func(_arg = null): _refresh_debug())
	if not await Board.ensure_loaded():
		GameState.leave_game(Board.load_error)
		return
	_refresh_debug()
	GameNet.join(GameState.game_id)

func _exit_tree() -> void:
	Presenter.busy_probe = Callable()
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
	Presenter.state_shown.connect(view.refresh)       # el tablero muestra lo que reproduce el Presenter, en orden
	Presenter.idle_changed.connect(view.on_overlays_changed)
	GameNet.legal_moves_changed.connect(view.on_overlays_changed)
	GameNet.busy_changed.connect(view.on_overlays_changed)
	Presenter.events_shown.connect(view.handle_events)
	Presenter.busy_probe = view.animation_remaining   # no se muestra la siguiente jugada mientras una ficha aun se mueve
	var ui := get_node_or_null("GameUI")
	if ui != null and ui.has_signal("view_step"):
		ui.connect("view_step", view.step_focus)
	if not Presenter.shown.is_empty():
		view.refresh(Presenter.shown)

## Fondo inicial: el color del asiento del jugador local (luego cambia con la zona que se mira).
func _update_background(_state: Dictionary) -> void:
	if GameNet.me == "":
		return
	var seat: int = int(GameNet.player(GameNet.me).get("seat", 0))
	$GameBackground.call("set_seat", seat)

func _on_fatal(_code: String, message: String) -> void:
	GameState.leave_game(message)

func _on_events(events: Array, version: int) -> void:
	if not OS.is_debug_build():
		return
	var names := PackedStringArray()
	for e in events:
		names.append(str(e.get("type", "?")))
	print("[game] %6d ms v%d %s" % [Time.get_ticks_msec() % 1000000, version, ", ".join(names)])

# --- Overlay de depuración (solo builds de debug) ---

func _setup_debug_overlay() -> void:
	if OS.is_debug_build():
		$DebugOverlay.visible = false        # F3 la muestra u oculta: no tapa el minimapa
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

func _unhandled_input(event: InputEvent) -> void:
	if _debug != null and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		$DebugOverlay.visible = not $DebugOverlay.visible
