class_name BoardView
extends Node
## Dibuja la partida en el mundo (US-020): chunks, fichas y cámara.
##
## El tablero es un anillo de 4 chunks y se muestra como un mundo infinito: cada
## frame, cada chunk se coloca en la copia del anillo más cercana a la cámara
## (como mucho a 2 chunks, siempre fuera de pantalla), así que al moverse con
## left/right nunca se ve el borde ni el vacío. Orden en el anillo: el chunk del
## asiento siguiente queda a la IZQUIERDA (ver BoardMap.slot_of_seat), por eso el
## cierre de la vuelta (id 67 -> 0) también es continuo.
##
## Las posiciones se piden a los propios TileMap/TileMapLayer (map_to_local), así
## que sirve igual antes y después de migrar a TileMapLayer.
##
## Fase 2 (turnos, liberar, zona segura, matar): sobre el tablero se pintan los
## movimientos que el SERVIDOR dice que son legales (GameNet.legal_moves). El
## cliente no calcula reglas: elegir una ficha muestra sus destinos y tocar uno
## envía ese movimiento tal cual. Los aros indican fichas protegidas (seguro o
## corredor), fichas movibles y la elegida; las capturas muestran un destello.
##
## Fase 4 (cartas): cuando el servidor pide un objetivo (`state.card.choices`) al
## jugador local, las opciones se dibujan igual que los movimientos: casillas
## marcadas (matar a tu elección) o ficha + destino (avanzar a zona segura). Tocar
## una envía CARD_TARGET con esa opción tal cual.

const PIECE_SCENE := preload("res://features/game/ground_pice.tscn")
const HALO_SCENE := preload("res://features/game/fx/piece_halo.tscn")
const TARGET_SCENE := preload("res://features/game/fx/target_marker.tscn")
const BURST_SCENE := preload("res://features/game/fx/burst_effect.tscn")
const IDLE_ANIMATION := &"idl_ground_pice"
const CHUNK_WIDTH := 32.0 * 17.0      # 17 columnas de 32 px (igual que player_ground.gd)
const SHARED_CELL_SPACING := 8.0      # separación entre fichas que comparten casilla
const CAM_SMOOTH := 5.0               # qué tan rápido alcanza la cámara su objetivo (1/s); más alto = más rápida
const PAN_SPEED := 420.0              # px/s al mover la cámara con las flechas o los botones
## Desplazamiento vertical de la cámara respecto al centro del chunk. Negativo = el
## mapa se ve más abajo. El suelo mide 5 filas (160 px) y el minimapa llega a y≈196:
## con -48 la fila del recorrido queda por debajo del minimapa. Ajustar aquí.
const CAMERA_OFFSET_Y := -128.0
const CLICK_RADIUS := 16.0            # qué tan cerca del centro hay que tocar una ficha o un destino
const SLIDE_TIME_PER_CELL := 0.34     # segundos por casilla que recorre una ficha
const SLIDE_TIME_MIN := 0.8
const SLIDE_TIME_MAX := 4.2
const WALK_ANIMATION := &"walk_ground_pice"
const ATTACK_ANIMATION := &"attack"
const ATTACK_TIME := 0.7              # lo que dura la animación de ataque antes de volver a reposo
const ATTACK_HIT := 0.4               # momento del ataque en que la víctima se va a casa

const LANE_SCRIPT := preload("res://features/game/lane_screen.gd")
const SIGNS_SCRIPT := preload("res://features/game/strip_signs.gd")
const SLASH_SCRIPT := preload("res://features/game/fx/slash_fx.gd")
const VIEW_ZOOM := 1.4                # casillas mas grandes: la camara acerca el tablero
const STRIP_SCREEN_DROP := 88.0       # cuanto debajo del centro de la camara queda la franja (px de mundo); mas alto = casillas mas abajo, mas fondo a la vista
const TAP_TIME := 0.25                # un toque corto en las flechas salta de ficha; mantener recorre el mapa
const STAIRS_DROP_VEC := Vector2(0.0, 20.0)     # la ficha se hunde en la compuerta abierta del seguro de la escalera
const FOOT_Y := -8.0                  # las fichas se paran sobre la casilla, no delante de ella
const LANE_ORIGIN := Vector2(0.0, 2400.0)   # las pantallas de corredor viven lejos del tablero
const LANE_SPACING := 800.0
const LANE_ROW := 4                   # fila del chunk que antes era el corredor (ahora: pantalla aparte)
const FADE_TIME := 0.28
const HOP_TIME := 0.46                # segundos por salto entre islas del corredor final
const HOP_HEIGHT := 15.0              # altura del salto (px de mundo)
const BACKDROP_SCRIPT := preload("res://features/game/world_backdrop.gd")
const BACKDROP_RANGE := 640.0         # a que distancia (x de mundo) de la camara se ve el fondo de un chunk
const HATCH_RADIUS := 18.0            # a que distancia (x) de la casilla de la escalera una ficha abre la compuerta

signal zone_blend(a: int, b: int, mix: float)   # entre que dos zonas esta la camara y cuanto (mezcla del fondo)

const COLOR_CAPTURE := Color(1.0, 0.4, 0.4)
const COLOR_CROWN := Color(1.0, 0.85, 0.25)
const COLOR_RELEASE := Color(0.45, 1.0, 0.55)
const COLOR_SAFE := Color(0.4, 0.8, 1.0)
const COLOR_PLAIN := Color(1.0, 1.0, 1.0)
const COLOR_BLOW := Color(1.0, 0.6, 0.2)   # SOPLAR: ficha devuelta a casa por no capturar

var world: Node2D
var camera: Camera2D

var _chunks := {}                     # asiento -> {holder, ground, prison, homes}
var _assigned := {}                   # asiento -> slot en que está ahora (sin límite, no módulo 4)
var _center_x := 0.0                  # x del centro de un chunk en el slot 0
var _pieces_layer: Node2D
var _pieces := {}                     # id de ficha -> Node2D
var _placements := {}                 # id de ficha -> {chunk, cell, shift}
var _cam_target_x := 0.0              # x del mundo a la que se acerca la cámara (movimiento continuo)
var _cam_y := 0.0
var _pan_dir := 0                     # -1/0/1: botones de la interfaz mantenidos (las flechas se leen aparte)
var _follow_piece := ""               # ficha que la cámara sigue mientras se desliza
var _slide_end := {}                  # id de ficha -> segundo en que termina su deslizamiento
var _pending_attack := {}             # id de atacante -> true: ataca al llegar a su casilla
var _focused_once := false

var _backdrops := {}                  # asiento -> WorldBackdrop (fondo pegado al mundo)
var _lanes := {}                      # asiento -> pantalla del corredor final (lane_screen.gd)
var _view_lane := -1                  # asiento cuyo corredor se ve ahora; -1 = el tablero
var _view_target := -1                # vista a la que va la camara (puede ir adelantada al fundido)
var _press_dir := 0                  # flecha de la interfaz apretada (-1/1) y desde cuando
var _press_time := 0.0
var _focus_index := -1               # ultima ficha propia a la que saltaron las flechas
var _descents := {}                   # id de ficha -> true mientras camina hacia la escalera
var _fade_rect: ColorRect
var _fade_tween: Tween

var _halo_layer: Node2D               # aros bajo las fichas
var _target_layer: Node2D             # destinos de la ficha elegida
var _halos := {}                      # id de ficha -> PieceHalo
var _targets: Array = []              # TargetMarker de la ficha elegida
var _selected_piece := ""
var _focused_piece := ""              # última ficha a la que se llevó la cámara
var _focused_card := ""               # último desafío de carta al que se llevó la cámara
var _last_moved_piece := ""           # última ficha propia que se movió (o salió de casa): a ella vuelve la cámara en tu turno
var _crown_ids: Array = []            # fichas que se pueden coronar ahora (tres pares seguidos)
var _focused_crown := ""
var _prev_placements := {}            # colocación de las fichas antes del último refresh()
var _slide := {}                      # id de ficha -> desfase que se va apagando (animación)
var _slide_tweens := {}
var _pending_state := {}              # último estado recibido mientras ruedan los dados
var _pending_events: Array = []       # eventos recibidos en ese lapso
var _was_holding := false
var _homes_synced := false           # ya se dibujaron las fichas en casa al menos una vez (la primera vez sin animacion)

## Las capas (Pieces, Halos, Targets) ya vienen creadas en game.tscn.
func setup(world_node: Node2D, pieces_layer: Node2D, halo_layer: Node2D, target_layer: Node2D) -> void:
	world = world_node
	_pieces_layer = pieces_layer
	_halo_layer = halo_layer
	_target_layer = target_layer
	camera = world.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.zoom = Vector2(VIEW_ZOOM, VIEW_ZOOM)
	var level := world.get_node_or_null("level")
	if level == null:
		push_error("BoardView: el mundo no tiene el nodo 'level'")
		return
	var seat := 0
	for child in level.get_children():
		var parts := _chunk_parts(child)
		if parts.is_empty():
			if str(child.name).begins_with("GroundPice"):
				child.queue_free()    # ficha de prueba del mundo: las reales salen del estado
			continue
		if seat >= BoardMap.SEATS:
			push_warning("BoardView: hay más de %d chunks, se ignoran los sobrantes" % BoardMap.SEATS)
			break
		var slot := BoardMap.slot_of_seat(seat)
		parts.holder.number_part = slot
		parts["homes"] = _read_homes(parts.prison)
		_chunks[seat] = parts
		_assigned[seat] = slot
		seat += 1
	if seat < BoardMap.SEATS:
		push_warning("BoardView: el mundo tiene %d chunks y hacen falta %d" % [seat, BoardMap.SEATS])
	if not _chunks.is_empty():
		var first: int = _chunks.keys()[0]
		_center_x = _chunk_center(first).x - int(_assigned[first]) * CHUNK_WIDTH
	for chunk_seat in _chunks:
		_decorate_chunk(int(chunk_seat))
		var bd = BACKDROP_SCRIPT.new()
		bd.seat = int(chunk_seat)
		world.add_child(bd)
		_backdrops[int(chunk_seat)] = bd
	for lane_seat in BoardMap.SEATS:
		var lane = LANE_SCRIPT.new()
		lane.seat = lane_seat
		lane.position = LANE_ORIGIN + Vector2(LANE_SPACING * lane_seat, 0.0)
		level.add_child(lane)
		_lanes[lane_seat] = lane
	_build_fade()

## Castillo en lugar de la casa en blanco, rotulos y escalera de bajada. El corredor
## de la fila de abajo ya no se dibuja aqui: es la pantalla del corredor final.
func _decorate_chunk(seat: int) -> void:
	var parts: Dictionary = _chunks[seat]
	var ground: Node2D = parts.ground
	var prison: Node = parts.prison
	if prison != ground and prison is CanvasItem:
		(prison as CanvasItem).visible = false
	var arrivals: Node = (parts.holder as Node).find_child("ArrivalsCorridor", true, false)
	if arrivals is CanvasItem:
		(arrivals as CanvasItem).visible = false
	ground.visible = false                         # el suelo lo dibuja strip_signs.gd con las texturas por color
	var signs = SIGNS_SCRIPT.new()
	signs.seat = seat
	signs.ground = ground
	signs.position = ground.position
	(parts.holder as Node).add_child(signs)
	parts["signs"] = signs                          # _ready ya corrio: signs.crowd (HomeCrowd) existe

func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade_rect)

## Destello en el mundo (captura, soplo, coronación): BurstEffect.tscn se borra solo.
func _burst(world_pos: Vector2, tint := COLOR_CAPTURE) -> void:
	var fx := BURST_SCENE.instantiate() as BurstEffect
	_pieces_layer.add_child(fx)
	fx.global_position = world_pos
	fx.play(tint)

func _process(delta: float) -> void:
	if _chunks.is_empty():
		return
	var holding := RollHold.active()
	if _was_holding and not holding:
		_flush_pending()
	_was_holding = holding
	_update_camera(delta)
	_update_chunks()
	_place_pieces()
	_update_hatches()

## Repinta todas las fichas desde un snapshot (conectar a Presenter.state_shown).
func refresh(state: Dictionary) -> void:
	if _pieces_layer == null or _chunks.is_empty():
		return
	if RollHold.active():
		_pending_state = state            # se dibuja al terminar la animación de los dados
		return
	_pending_state = {}                   # este estado es más nuevo que cualquiera guardado
	if not _focused_once:
		_focus_initial()

	_prev_placements = _placements.duplicate(true)
	var entries: Array = []
	var group_sizes := {}
	for p in state.get("pieces", []):
		var seat := BoardMap.seat_of_piece(p)
		if seat < 0 or not _chunks.has(seat):
			continue
		var key := ""
		var chunk := seat
		var cell := Vector2i.ZERO
		var cell_id := -1
		if BoardMap.is_home(p):
			var homes: Array = _chunks[seat].homes
			if homes.is_empty():
				continue
			key = "home-%s" % str(p.get("id", ""))
			cell = homes[posmod(int(p.get("number", 0)), homes.size())]
		else:
			cell_id = BoardMap.piece_cell_id(p, seat)
			var placed := BoardMap.strip_cell(cell_id)
			if placed.is_empty() or not _chunks.has(placed.seat):
				continue
			key = "cell-%d" % cell_id
			chunk = placed.seat
			cell = placed.cell
		group_sizes[key] = int(group_sizes.get(key, 0)) + 1
		entries.append({"piece": p, "seat": seat, "key": key, "chunk": chunk, "cell": cell, "cell_id": cell_id})

	var placed_count := {}
	var seen := {}
	for e in entries:
		var id := str(e.piece.get("id", ""))
		seen[id] = true
		var index := int(placed_count.get(e.key, 0))
		placed_count[e.key] = index + 1
		var shift := (index - (int(group_sizes[e.key]) - 1) / 2.0) * SHARED_CELL_SPACING
		_piece_node(id, e.seat)
		var placement := {
			"chunk": e.chunk, "cell": e.cell, "shift": shift,
			"cell_id": e.cell_id, "status": str(e.piece.get("status", "")), "seat": e.seat,
			"number": int(e.piece.get("number", 0)),
			"progress": int(e.piece.get("progress", -1)),
		}
		var old: Dictionary = _prev_placements.get(id, {})
		if not old.is_empty() and (old.chunk != e.chunk or old.cell != e.cell):
			_start_slide(id, old, placement)
		_placements[id] = placement

	for id in _pieces.keys():
		if not seen.has(id):
			_pieces[id].queue_free()
			_pieces.erase(id)
			_placements.erase(id)
	_sync_homes()
	_rebuild_overlays()
	_update_chunks()
	_place_pieces()
	for id in _placements:
		if not _slide.has(id):
			_face_forward(str(id))

## Botones de la interfaz: -1 mueve la cámara a la izquierda, 1 a la derecha, 0 la detiene.
## Es un movimiento continuo mientras se mantiene pulsado (igual que las flechas).
func step_focus(direction: int) -> void:
	if direction != 0:
		_press_dir = direction                  # aun no sabemos si es toque o mantener
		_press_time = _now()
		return
	var held := _now() - _press_time
	if _press_dir != 0 and held < TAP_TIME:
		_next_piece(_press_dir)                 # toque corto: salta a tu siguiente ficha
	_press_dir = 0
	_pan_dir = 0

## Salta a la siguiente (1) o anterior (-1) ficha tuya que siga en juego.
func _next_piece(direction: int) -> void:
	var mine: Array = []
	for id in _placements:
		if _is_mine(str(id)):
			mine.append(str(id))
	if mine.is_empty():
		return
	mine.sort()
	_focus_index = posmod(_focus_index + direction, mine.size())
	_cam_to_piece(mine[_focus_index])

## Lleva la cámara (con movimiento suave) al centro del chunk de ese asiento, en
## la copia del anillo más cercana a la vista actual.
func focus_seat(seat: int, animate := true) -> void:
	if camera == null or not _chunks.has(seat):
		return
	if _view_lane >= 0 or _view_target >= 0:
		_switch_view(-1)                              # viene de un corredor: vuelve al tablero
	var base := BoardMap.slot_of_seat(seat)
	var cam_slot := (_cam_target_x - _center_x) / CHUNK_WIDTH if _view_lane >= 0 \
			else (camera.global_position.x - _center_x) / CHUNK_WIDTH
	var slot := base + BoardMap.SEATS * roundi((cam_slot - base) / float(BoardMap.SEATS))
	_follow_piece = ""
	_cam_target_x = _slot_x(slot)
	if not animate and _view_lane < 0:
		camera.global_position.x = _cam_target_x
		_update_chunks()

## Lleva la camara a donde esta una ficha: su corredor (con fundido) o el chunk del tablero.
func _focus_placement(pl: Dictionary) -> void:
	if _is_lane_cell(pl.cell):
		_switch_view(int(pl.chunk))
	else:
		focus_seat(int(pl.chunk))

# --- Movimientos legales (Fase 2) --------------------------------------------------

## El tablero reacciona a cualquier cambio que afecte lo que se puede tocar:
## movimientos legales nuevos o una acción en vuelo (GameNet.busy).
func on_overlays_changed(_arg = null) -> void:
	_rebuild_overlays()

## Eventos del servidor (uno por versión). Aquí solo los que se dibujan en el mundo.
func handle_events(events: Array, _version: int = 0) -> void:
	if RollHold.active() or not _pending_state.is_empty():
		_pending_events.append_array(events)
		return
	for e in events:
		var data: Dictionary = e.data if e.get("data") is Dictionary else {}
		var piece_id := str(data.get("pieceId", ""))
		match str(e.get("type", "")):
			"PIECE_CAPTURED":
				# El atacante camina hasta la casilla y ataca; la víctima espera ahí hasta el golpe.
				var attacker := GameText.s(data.get("byPieceId"))
				if attacker != "" and _pieces.has(attacker) and _prev_placements.has(piece_id):
					_capture_sequence(piece_id, attacker)
					_cam_to_piece(attacker)            # la camara va a la pelea, sea de quien sea
					_follow_piece = attacker
				else:
					_burst_at_previous(piece_id)
			"CARD_PIECE_RETURNED":
				_burst_at_previous(piece_id)       # carta o castigo: no hay ficha atacante
			"PIECE_MOVED":
				if _slide.has(piece_id):
					_follow_piece = piece_id           # la cámara sigue a cualquier ficha que se mueve
				if data.get("cardId") == null and _is_mine(piece_id):
					_last_moved_piece = piece_id       # a esta vuelve la cámara cuando te toque
				if str(data.get("status", "")) == "CROWNED":
					_burst_crown(piece_id)             # coronación (US-015)
			"PIECE_RELEASED":
				# Salida automática con par (v5-100): la ficha ya está en la salida y se desliza desde casa.
				if _slide.has(piece_id):
					_follow_piece = piece_id
				if _is_mine(piece_id):
					_last_moved_piece = piece_id
			"PIECE_CROWNED":
				_burst_crown(piece_id)                 # coronación elegida con tres pares
			"PIECE_BLOWN":
				_burst_at_previous(piece_id, COLOR_BLOW)   # SOPLAR: no capturaste y la ficha vuelve a casa
			"TURN_CHANGED":
				if str(data.get("playerId", "")) == GameNet.me:
					_focus_last_moved()

## Destello donde estaba la ficha antes del último estado (ya salió del tablero).
func _burst_at_previous(piece_id: String, tint := Color(1.0, 0.3, 0.3)) -> void:
	var prev: Dictionary = _prev_placements.get(piece_id, {})
	if prev.is_empty() or not _chunks.has(prev.chunk):
		return
	_burst(_cell_world(prev.chunk, prev.cell) + Vector2(prev.shift, 0), tint)

## Destello dorado en la corona, donde ya está la ficha.
func _burst_crown(piece_id: String) -> void:
	var now: Dictionary = _placements.get(piece_id, {})
	if now.is_empty() or not _chunks.has(now.chunk):
		return
	_burst(_cell_world(now.chunk, now.cell) + Vector2(now.shift, 0), COLOR_CROWN)

## ¿La ficha es del jugador local? (id "seat-{asiento}-piece-{n}")
func _is_mine(piece_id: String) -> bool:
	var parts := piece_id.split("-")
	if parts.size() < 4 or parts[0] != "seat":
		return false
	return int(parts[1]) == int(GameNet.player(GameNet.me).get("seat", -2))

## Al empezar tu turno la cámara vuelve a la última ficha que moviste. Si otras fichas
## aún se están deslizando (la jugada que acaba de terminar), espera a que se asienten.
func _focus_last_moved() -> void:
	if _last_moved_piece == "" or not _placements.has(_last_moved_piece):
		return
	var wait := 0.0
	for id in _slide_end:
		wait = maxf(wait, float(_slide_end[id]) - _now())
	if wait > 0.05:
		get_tree().create_timer(wait + 0.15).timeout.connect(_focus_piece.bind(_last_moved_piece))
	else:
		_focus_piece(_last_moved_piece)

func _focus_piece(piece_id: String) -> void:
	if not GameNet.is_my_turn():                 # si el turno ya pasó mientras esperaba, no se mueve nada
		return
	_cam_to_piece(piece_id)

## Lleva la camara a una ficha (a su corredor o a su casilla del tablero), sin mirar de quien es el turno.
func _cam_to_piece(piece_id: String) -> void:
	var pl: Dictionary = _placements.get(piece_id, {})
	if pl.is_empty() or not _chunks.has(pl.chunk):
		return
	_follow_piece = ""
	if _is_lane_cell(pl.cell):
		_switch_view(int(pl.chunk))
		return
	if _view_lane >= 0:
		_switch_view(-1)
	_cam_target_x = _cell_world(pl.chunk, pl.cell).x + float(pl.shift)

## US-010: primero llega y ataca el atacante, y solo entonces la víctima salta y vuelve
## a casa. El estado ya la mandó a casa, así que aquí se la mantiene en su casilla
## (con un desfase fijo) hasta el momento del golpe.
func _capture_sequence(victim: String, attacker: String) -> void:
	var old: Dictionary = _prev_placements.get(victim, {})
	var home: Dictionary = _placements.get(victim, {})
	if old.is_empty() or home.is_empty() or not _chunks.has(old.chunk):
		return
	if _slide_tweens.has(victim):
		(_slide_tweens[victim] as Tween).kill()
		_slide_tweens.erase(victim)
	_slide[victim] = _slide_offset(old, home)
	_play_animation(victim, IDLE_ANIMATION)
	var wait := 0.0
	if _slide_end.has(attacker):
		wait = maxf(0.0, float(_slide_end[attacker]) - _now())
		_pending_attack[attacker] = true             # ataca apenas termine de caminar
	else:
		_attack(attacker)
	get_tree().create_timer(wait + ATTACK_HIT).timeout.connect(_release_victim.bind(victim, old))

func _release_victim(victim: String, old: Dictionary) -> void:
	if not _pieces.has(victim) or not _placements.has(victim) or not _chunks.has(old.chunk):
		return
	var hit_pos := _cell_world(old.chunk, old.cell) + Vector2(old.shift, 0)
	_burst(hit_pos)
	var slash = SLASH_SCRIPT.new()
	slash.tint = BoardMap.SEAT_COLORS[posmod(int(old.chunk), BoardMap.SEATS)]
	slash.z_index = 20
	slash.global_position = hit_pos + Vector2(0, -6)
	_pieces_layer.add_child(slash)
	_start_slide(victim, old, _placements[victim])

## Aplica lo que quedó en espera durante la animación de los dados: primero el
## estado (las fichas se deslizan), luego los eventos (destello de captura) y por
## último los destinos, que antes no se podían tocar.
func _flush_pending() -> void:
	var state := _pending_state
	var events := _pending_events
	_pending_state = {}
	_pending_events = []
	if not state.is_empty():
		refresh(state)
	if not events.is_empty():
		handle_events(events)
	_rebuild_overlays()

## Movimientos del jugador local que se pueden mostrar ahora. Vacío si no es su
## turno, no ha lanzado, hay un desafío pendiente o hay una acción en vuelo.
func _usable_moves() -> Array:
	if RollHold.active() or GameNet.busy or not GameNet.is_my_turn() or not Presenter.idle():
		return []
	var turn: Variant = Presenter.view().get("turn")
	if not (turn is Dictionary) or not bool(turn.get("rolled", false)):
		return []
	if Presenter.view().get("trivia") != null or Presenter.view().get("card") != null:
		return []
	return GameNet.legal_moves

## Protegida = zona segura o corredor final (US-013): ahí no se puede capturar.
func _is_protected_cell(cell_id: int) -> bool:
	if cell_id < 0:
		return false
	return Board.is_safe(cell_id) or bool(Board.cell(cell_id).get("protectedCell", false))

func _move_color(m: Dictionary) -> Color:
	if bool(m.get("capture", false)):
		return COLOR_CAPTURE
	if bool(m.get("crown", false)):
		return COLOR_CROWN
	if bool(m.get("release", false)):
		return COLOR_RELEASE
	if bool(m.get("safe", false)):
		return COLOR_SAFE
	return COLOR_PLAIN

## Reconstruye aros y destinos. Se llama tras cada estado, cambio de movimientos o
## de selección. No decide nada: solo dibuja lo que el servidor ya validó.
func _rebuild_overlays() -> void:
	if _halo_layer == null:
		return
	for target in _targets:
		target.queue_free()
	_targets.clear()

	var moves := _usable_moves()
	var card_choices := _usable_card_choices()
	var movable := {}
	for m in moves:
		movable[str(m.get("pieceId", ""))] = true
	for c in card_choices:
		var choice_piece := GameText.s(c.get("pieceId"))
		if choice_piece != "" and _choice_cell(c) >= 0:
			movable[choice_piece] = true                    # carta que mueve una ficha propia: se elige primero
	_crown_ids = _crown_candidates()
	for crown_id in _crown_ids:
		movable[crown_id] = true                            # tres pares: se toca la ficha a coronar
	if not movable.has(_selected_piece):
		_selected_piece = ""
	if _selected_piece == "" and movable.size() == 1:
		_selected_piece = str(movable.keys()[0])          # una sola opción: se elige sola

	var wanted := {}
	for id in _placements:
		var pl: Dictionary = _placements[id]
		var guarded: bool = pl.status == "BOARD" and _is_protected_cell(int(pl.cell_id))
		var can_move: bool = movable.has(id)
		var crowned: bool = pl.status == "CROWNED"
		if not guarded and not can_move and not crowned:
			continue
		wanted[id] = true
		var halo: PieceHalo = _halos.get(id)
		if halo == null:
			halo = HALO_SCENE.instantiate() as PieceHalo
			_halo_layer.add_child(halo)
			_halos[id] = halo
		halo.safe_cell = guarded
		halo.crowned = crowned
		halo.movable = can_move
		halo.selected = id == _selected_piece
	for id in _halos.keys():
		if not wanted.has(id):
			_halos[id].queue_free()
			_halos.erase(id)

	if _selected_piece != "":
		var seen := {}
		for m in moves:
			if str(m.get("pieceId", "")) != _selected_piece:
				continue
			var to := int(m.get("to", -1))
			var die_value := int(m.get("dieValue", 0))
			var key := "%d-%d" % [to, die_value]
			if seen.has(key):
				continue                                   # dobles: dos dados iguales, mismo destino
			seen[key] = true
			var placed := BoardMap.strip_cell(to)
			if placed.is_empty() or not _chunks.has(placed.seat):
				continue
			var target := TARGET_SCENE.instantiate() as TargetMarker
			target.label = _move_label(m)
			target.color = _move_color(m)
			target.move = m
			var spot := _marker_spot(placed, _selected_piece, _targets.size())
			target.chunk = int(spot.chunk)
			target.cell = spot.cell
			if spot.nudge != Vector2.ZERO:
				target.set_meta("nudge", spot.nudge)
			_target_layer.add_child(target)
			_targets.append(target)

	_add_card_targets(card_choices)

	# La cámara sigue a la ficha elegida (solo cuando cambia la elección).
	if _selected_piece != _focused_piece:
		_focused_piece = _selected_piece
		if _selected_piece != "" and _placements.has(_selected_piece):
			_frame_selection()
	_focus_card_targets(card_choices)
	if _crown_ids.is_empty():
		_focused_crown = ""
	elif _focused_crown == "":
		_focused_crown = str(_crown_ids[0])                 # la cámara va a la primera candidata
		var first: Dictionary = _placements.get(_focused_crown, {})
		if not first.is_empty():
			_focus_placement(first)
	_place_pieces()

## Encuadra la ficha elegida Y sus destinos. Antes la cámara iba al centro del chunk de la ficha, y
## con destinos en el chunk vecino (o lejos de ese centro) se quedaban fuera de pantalla. Ahora toma
## la ficha y todos los marcadores sobre el anillo (copia más cercana a la ficha) y centra el conjunto;
## si no caben en pantalla, prioriza que se vea la ficha y el primer destino.
func _frame_selection() -> void:
	var pl: Dictionary = _placements.get(_selected_piece, {})
	if camera == null or pl.is_empty() or not _chunks.has(pl.chunk):
		return
	if _is_lane_cell(pl.cell):
		_focus_placement(pl)                       # corredor final: su propia pantalla
		return
	if _view_lane >= 0 or _view_target >= 0:
		_switch_view(-1)
	var ring := BoardMap.SEATS * CHUNK_WIDTH
	var piece_x := _cell_world(pl.chunk, pl.cell).x + float(pl.shift)
	var min_x := piece_x
	var max_x := piece_x
	var first_dx := 0.0
	var count := 0
	for target in _targets:
		if _is_lane_cell(target.cell) or not _chunks.has(target.chunk):
			continue
		var dx := fposmod(_cell_world(target.chunk, target.cell).x - piece_x + ring / 2.0, ring) - ring / 2.0
		min_x = minf(min_x, piece_x + dx)
		max_x = maxf(max_x, piece_x + dx)
		if count == 0:
			first_dx = dx
		count += 1
	var visible_w := get_viewport().get_visible_rect().size.x / VIEW_ZOOM
	var margin := 56.0                              # que no queden pegados al borde (y lejos de los botones)
	var center := (min_x + max_x) * 0.5
	if max_x - min_x > visible_w - margin * 2.0:
		# no caben todos: ficha y primer destino
		var lo := minf(piece_x, piece_x + first_dx)
		var hi := maxf(piece_x, piece_x + first_dx)
		center = (lo + hi) * 0.5
		if hi - lo > visible_w - margin * 2.0:
			center = piece_x + signf(first_dx) * (visible_w * 0.5 - margin)
	_follow_piece = ""
	_cam_target_x = center
	_pan_dir = 0
	_press_dir = 0

## Texto del destino: el valor del dado, o "4+2" cuando el movimiento usa la suma de
## los dos dados (`dieIndex` 2).
func _move_label(m: Dictionary) -> String:
	var die_value := int(m.get("dieValue", 0))
	if int(m.get("dieIndex", 0)) != 2:
		return str(die_value)
	var turn: Variant = Presenter.view().get("turn")
	var dice: Variant = turn.get("dice") if turn is Dictionary else null
	if dice is Array and dice.size() == 2:
		return "%d+%d" % [int(dice[0]), int(dice[1])]
	return str(die_value)

## Tres pares seguidos (`turn.crownChoiceRequired`): fichas propias en el tablero entre
## las que el servidor permite coronar. Vacío fuera de ese caso.
func _crown_candidates() -> Array:
	if RollHold.active() or GameNet.busy or not GameNet.crown_choice_pending():
		return []
	var turn: Variant = Presenter.view().get("turn")
	var eligible: Variant = turn.get("crownEligible") if turn is Dictionary else null
	var out: Array = []
	if eligible is Array:
		for id in eligible:
			var pl: Dictionary = _placements.get(str(id), {})
			if not pl.is_empty() and pl.status == "BOARD":
				out.append(str(id))
	return out

# --- Objetivos de carta (Fase 4) ---------------------------------------------------------

## Opciones de `state.card` que el jugador local puede tocar ahora. Vacío si la
## carta no es suya, ruedan unos dados o hay una acción en vuelo.
func _usable_card_choices() -> Array:
	if RollHold.active() or GameNet.busy:
		return []
	var card: Variant = Presenter.view().get("card")
	if not (card is Dictionary) or str(card.get("playerId", "")) != GameNet.me:
		return []
	var choices: Variant = card.get("choices")
	return choices if choices is Array else []

## Casilla de una opción: `targetPosition`, o donde está la ficha `targetPieceId`. -1 si no hay.
func _choice_cell(choice: Dictionary) -> int:
	var pos: Variant = choice.get("targetPosition")
	if pos != null:
		return int(pos)
	var target_piece := GameText.s(choice.get("targetPieceId"))
	if target_piece != "" and _placements.has(target_piece):
		return int(_placements[target_piece].cell_id)
	return -1

## Marca y color según el efecto de la carta (solo presentación).
func _card_marker() -> Dictionary:
	var card: Variant = Presenter.view().get("card")
	var effect := GameText.s(card.get("effectCode")) if card is Dictionary else ""
	if effect.begins_with("CAPTURE"):
		return {"label": "X", "color": COLOR_CAPTURE}
	if effect == "MOVE_SAFE":
		return {"label": "S", "color": COLOR_SAFE}
	return {"label": "?", "color": COLOR_PLAIN}

## Dibuja las opciones de la carta. Las que llevan `pieceId` (ficha propia) solo
## salen cuando esa ficha está elegida; las demás se ven siempre.
func _add_card_targets(card_choices: Array) -> void:
	var marker := _card_marker()
	var seen := {}
	for c in card_choices:
		if not (c is Dictionary):
			continue
		var choice_piece := GameText.s(c.get("pieceId"))
		if choice_piece != "" and choice_piece != _selected_piece:
			continue
		var cell_id := _choice_cell(c)
		var key := "%s-%d" % [choice_piece, cell_id]
		if cell_id < 0 or seen.has(key):
			continue
		seen[key] = true
		var placed := BoardMap.strip_cell(cell_id)
		if placed.is_empty() or not _chunks.has(placed.seat):
			continue
		var target := TARGET_SCENE.instantiate() as TargetMarker
		target.label = str(marker.label)
		target.color = marker.color
		target.move = c
		target.is_card = true
		var spot := _marker_spot(placed, choice_piece, _targets.size())
		target.chunk = int(spot.chunk)
		target.cell = spot.cell
		if spot.nudge != Vector2.ZERO:
			target.set_meta("nudge", spot.nudge)
		_target_layer.add_child(target)
		_targets.append(target)

## Al abrirse una carta con casillas por elegir, la cámara va a la primera si ninguna se ve.
func _focus_card_targets(card_choices: Array) -> void:
	var card: Variant = Presenter.view().get("card")
	var card_id := GameText.s(card.get("id")) if card is Dictionary else ""
	if card_id == "":
		_focused_card = ""
		return
	if card_choices.is_empty() or card_id == _focused_card:
		return
	_focused_card = card_id
	if _selected_piece != "" or _targets.is_empty():
		return                                             # con ficha elegida la cámara ya la sigue
	var cam_x := camera.global_position.x if camera != null else 0.0
	for target in _targets:
		if absf(_cell_world(target.chunk, target.cell).x - cam_x) < 280.0:
			return                                         # ya hay una a la vista
	focus_seat(int(_targets[0].chunk))

## Toque o clic en el mundo: primero un destino (envía el movimiento), si no una
## ficha movible (la elige). Los botones del HUD consumen sus propios clics.
func _unhandled_input(event: InputEvent) -> void:
	if world == null or not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := world.get_global_mouse_position()
	for target in _targets:
		if target.global_position.distance_to(pos) <= CLICK_RADIUS:
			get_viewport().set_input_as_handled()
			var sent: bool = GameNet.pick_card(target.move) if target.is_card else GameNet.move(target.move)
			if sent:
				_selected_piece = ""
			return
	var best := ""
	var best_distance := CLICK_RADIUS
	for id in _halos:
		var halo: PieceHalo = _halos[id]
		if not halo.movable:
			continue
		var distance := halo.global_position.distance_to(pos)
		if distance <= best_distance:
			best = str(id)
			best_distance = distance
	if best != "":
		get_viewport().set_input_as_handled()
		if _crown_ids.has(best):
			GameNet.crown(best)                   # CROWN_REQUEST: no hay destinos que elegir
			return
		_selected_piece = best
		_focused_piece = best                       # el reencuadre lo hace este toque, no el rebuild
		_rebuild_overlays()
		_frame_selection()
		return
	# Escaleras: tocar la de un chunk baja a su corredor final; tocar la del corredor sube de vuelta.
	if _view_lane >= 0:
		if _lanes[_view_lane].stairs_hit(pos):
			get_viewport().set_input_as_handled()
			_cam_target_x = _stairs_world(_view_lane).x
			_switch_view(-1)
		return
	for seat in _chunks:
		if _stairs_world(int(seat)).distance_to(pos) <= 20.0:
			get_viewport().set_input_as_handled()
			_cam_target_x = _stairs_world(int(seat)).x
			_switch_view(int(seat))
			return

# --- Deslizamiento de fichas -----------------------------------------------------------

## Desfase entre la casilla vieja y la nueva (por el camino corto del anillo).
func _slide_offset(old: Dictionary, placement: Dictionary) -> Vector2:
	var from_pos := _cell_world(old.chunk, old.cell) + Vector2(old.shift, 0)
	var to_pos := _cell_world(placement.chunk, placement.cell) + Vector2(placement.shift, 0)
	var offset := from_pos - to_pos
	var ring := BoardMap.SEATS * CHUNK_WIDTH
	offset.x = fposmod(offset.x + ring / 2.0, ring) - ring / 2.0
	return offset

## La ficha aparece en su casilla nueva con un desfase hacia la vieja y lo va
## apagando, caminando. Dura según la distancia. Se aplica sobre la posición, así
## sigue funcionando con el mundo en bucle.
func _start_slide(id: String, old: Dictionary, placement: Dictionary) -> void:
	_set_piece_alpha(id, 1.0)
	_descents.erase(id)
	var old_lane := _is_lane_cell(old.cell)
	var new_lane := _is_lane_cell(placement.cell)
	if new_lane and not old_lane:
		_start_descent(id, old, placement)       # entra al corredor: escalera + cambio de pantalla
		return
	if old_lane and not new_lane:
		_kill_slide(id)                          # sale del corredor (vuelve a casa): sin camino entre pantallas
		_fade_rect.color.a = 0.0
		_cam_target_x = _cell_world(placement.chunk, placement.cell).x
		_switch_view(-1)
		return
	if new_lane:
		_switch_view(int(placement.chunk))       # camina dentro del corredor: la camara esta alli
		if old_lane and int(old.chunk) == int(placement.chunk):
			_start_hop(id, old, placement)       # en el corredor la ficha SALTA de isla en isla, no camina en linea recta
			return
	var offset := _slide_offset(old, placement)
	var time := clampf(offset.length() / 32.0 * SLIDE_TIME_PER_CELL, SLIDE_TIME_MIN, SLIDE_TIME_MAX)
	if _slide_tweens.has(id):
		(_slide_tweens[id] as Tween).kill()
	_slide[id] = offset
	_slide_end[id] = _now() + time
	_play_animation(id, WALK_ANIMATION)
	var walker: Variant = _pieces.get(id)
	if walker != null and is_instance_valid(walker) and (walker as Node).has_method("face"):
		(walker as Node).call("face", -offset.x)   # mira hacia donde camina
	_play_steps(offset.length() / 32.0, time)
	var tween := create_tween()
	tween.tween_method(_set_slide.bind(id, offset), 0.0, 1.0, time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_end_slide.bind(id))
	_slide_tweens[id] = tween

## Gira la ficha hacia donde iria su siguiente paso en la pista (en el corredor, hacia la corona).
## Asi una ficha que sale de casa, o que se queda quieta tras moverse, mira hacia donde tiene que ir.
func _face_forward(id: String) -> void:
	var pl: Dictionary = _placements.get(id, {})
	var node: Variant = _pieces.get(id)
	if pl.is_empty() or node == null or not is_instance_valid(node) or not (node as Node).has_method("face"):
		return
	var cell_id := int(pl.cell_id)
	if cell_id < 0:
		return
	if cell_id >= BoardMap.LANE_BASE:
		(node as Node).call("face", 1.0)               # el corredor se recorre hacia la derecha
		return
	var nxt := BoardMap.strip_cell((cell_id + 1) % BoardMap.TRACK_COUNT)
	if nxt.is_empty() or not _chunks.has(nxt.seat) or not _chunks.has(pl.chunk):
		return
	var dx := _cell_world(nxt.seat, nxt.cell).x - _cell_world(pl.chunk, pl.cell).x
	var ring := BoardMap.SEATS * CHUNK_WIDTH
	dx = fposmod(dx + ring / 2.0, ring) - ring / 2.0
	(node as Node).call("face", dx)

## Una pisada por casilla mientras la ficha camina (como mucho 14, para que no sea un traqueteo).
func _play_steps(cells: float, time: float) -> void:
	var steps := clampi(roundi(cells), 1, 14)
	var steps_tween := create_tween()
	for i in steps:
		steps_tween.tween_callback(Sfx.play.bind(&"step", -3.0, randf_range(0.92, 1.08)))
		steps_tween.tween_interval(time / float(steps))

func _set_slide(t: float, id: String, offset: Vector2) -> void:
	_slide[id] = offset.lerp(Vector2.ZERO, t)

func _end_slide(id: String) -> void:
	if _fade_rect != null:
		_fade_rect.color = Color(0.0, 0.0, 0.0, _fade_rect.color.a)
	_set_piece_alpha(id, 1.0)
	_descents.erase(id)
	_slide.erase(id)
	_slide_tweens.erase(id)
	_slide_end.erase(id)
	_sync_homes()                                 # si volvio a casa, ahora se funde en su hueco del fondo
	_face_forward(id)                             # queda mirando hacia donde tiene que seguir
	if id == _follow_piece:                       # la cámara termina de asentarse en su casilla
		_follow_piece = ""
		var pl: Dictionary = _placements.get(id, {})
		if not pl.is_empty() and _chunks.has(pl.chunk) and not _is_lane_cell(pl.cell):
			_cam_target_x = _cell_world(pl.chunk, pl.cell).x + float(pl.shift)
	if _pending_attack.erase(id):
		_attack(id)
	else:
		_play_animation(id, IDLE_ANIMATION)

func _attack(id: String) -> void:
	_play_animation(id, ATTACK_ANIMATION)
	get_tree().create_timer(ATTACK_TIME).timeout.connect(_end_attack.bind(id))

func _end_attack(id: String) -> void:
	if not _slide_tweens.has(id):                 # si ya se está moviendo otra vez, sigue caminando
		_play_animation(id, IDLE_ANIMATION)

func _play_animation(id: String, animation: StringName) -> void:
	var node: Variant = _pieces.get(id)
	if node == null or not is_instance_valid(node):
		return
	var player := (node as Node).get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation(animation):
		player.play(animation)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Segundos que faltan para que terminen las fichas que se estan moviendo (caminata, bajada por la escalera,
## ataque). El Presenter espera a esto antes de mostrar la siguiente jugada, para que no se pisen.
func animation_remaining() -> float:
	var left := 0.0
	for id in _slide_end:
		left = maxf(left, float(_slide_end[id]) - _now())
	return left

# --- Corredor final: escalera, fundido y cambio de pantalla -----------------------------

## ¿La ficha esta dibujada en el tablero? (no en la pantalla del corredor)
func _on_strip(id: String) -> bool:
	var pl: Dictionary = _placements.get(id, {})
	return pl.is_empty() or not _is_lane_cell(pl.cell) or _descents.has(id)

func _set_piece_alpha(id: String, alpha: float) -> void:
	var piece: Variant = _pieces.get(id)
	if piece != null and is_instance_valid(piece):
		var item := piece as CanvasItem
		item.modulate = Color(item.modulate.r, item.modulate.g, item.modulate.b, alpha)

func _kill_slide(id: String) -> void:
	if _slide_tweens.has(id):
		(_slide_tweens[id] as Tween).kill()
		_slide_tweens.erase(id)
	_slide.erase(id)
	_slide_end.erase(id)

## Cambia lo que ve la camara: un corredor final (seat 0-3) o el tablero (-1), con fundido.
func _switch_view(lane_seat: int, instant := false) -> void:
	if lane_seat == _view_target:
		return
	_view_target = lane_seat
	if _fade_tween != null:
		_fade_tween.kill()
	if instant or _fade_rect == null:
		_apply_view()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 1.0, FADE_TIME)
	_fade_tween.tween_callback(_apply_view)
	_fade_tween.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)

func _apply_view() -> void:
	_view_lane = _view_target
	if camera == null:
		return
	if _view_lane >= 0:
		camera.global_position = _lanes[_view_lane].view_center()
		zone_blend.emit(_view_lane, _view_lane, 0.0)   # el fondo toma el color del corredor
		_lanes[_view_lane].play_intro()                # titulo y pulso del portal al llegar
	else:
		camera.global_position = Vector2(_cam_target_x, _cam_y)
		_update_chunks()                          # vuelve a avisar la zona del tablero

## La ficha camina hasta la escalera, baja, la pantalla se funde y sigue caminando en el
## corredor hasta su casilla. `placement` ya es una casilla del corredor.
func _start_descent(id: String, old: Dictionary, placement: Dictionary) -> void:
	_kill_slide(id)
	var seat := int(placement.chunk)
	var lane = _lanes[seat]
	var stairs_cell: Vector2i = BoardMap.stairs_cell()
	var offset := _cell_world(old.chunk, old.cell) + Vector2(old.shift, 0) - _cell_world(seat, stairs_cell)
	var ring := BoardMap.SEATS * CHUNK_WIDTH
	offset.x = fposmod(offset.x + ring / 2.0, ring) - ring / 2.0
	var walk_time := clampf(absf(offset.x) / 32.0 * SLIDE_TIME_PER_CELL, 0.2, SLIDE_TIME_MAX)
	var target_pos := _cell_world(seat, placement.cell) + Vector2(placement.shift, 0)
	var lane_offset: Vector2 = lane.stairs_top() - target_pos
	var to_idx := _lane_index(placement.cell)
	var lane_time := clampf(float(to_idx + 1) * HOP_TIME, 0.5, SLIDE_TIME_MAX + 1.0)   # portal -> isla 1 -> ... -> destino
	_descents[id] = true
	var tint: Color = lane.ACCENT[posmod(seat, lane.ACCENT.size())].darkened(0.82)
	_fade_rect.color = Color(tint.r, tint.g, tint.b, _fade_rect.color.a)   # el fundido toma el color de la zona
	_follow_piece = id
	_slide_end[id] = _now() + walk_time + 0.45 + FADE_TIME * 2.0 + lane_time
	_play_animation(id, WALK_ANIMATION)
	var walker: Variant = _pieces.get(id)
	if walker != null and is_instance_valid(walker) and (walker as Node).has_method("face"):
		(walker as Node).call("face", -offset.x if absf(offset.x) > 0.5 else -1.0)
	_play_steps(absf(offset.x) / 32.0, walk_time)
	var tween := create_tween()
	tween.tween_method(_descent_walk.bind(id, seat, stairs_cell, offset), 0.0, 1.0, walk_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(Sfx.play.bind(&"step", -3.0, 0.85))
	tween.tween_method(_descent_stairs.bind(id, seat, stairs_cell), 0.0, 1.0, 0.45)
	tween.tween_property(_fade_rect, "color:a", 1.0, FADE_TIME)
	tween.tween_callback(_descent_cut.bind(id, seat, lane_offset))
	tween.tween_property(_fade_rect, "color:a", 0.0, FADE_TIME)
	tween.tween_callback(_play_steps.bind(float(to_idx + 1), lane_time))
	tween.tween_method(_set_hop.bind(id, seat, true, 0, to_idx, float(placement.shift)), 0.0, 1.0, lane_time)
	tween.tween_callback(_end_slide.bind(id))
	_slide_tweens[id] = tween

## Numero de isla (0 = junto al portal ... 7 = trono) de una celda del corredor.
static func _lane_index(cell: Vector2i) -> int:
	return BoardMap.LANE_LEN - 1 - cell.x

## Movimiento dentro del corredor: salta de isla en isla (arco entre cada una) en vez de ir en linea recta.
func _start_hop(id: String, old: Dictionary, placement: Dictionary) -> void:
	var seat := int(placement.chunk)
	var from_idx := _lane_index(old.cell)
	var to_idx := _lane_index(placement.cell)
	var hops := absi(to_idx - from_idx)
	if hops == 0:
		return
	var time := clampf(float(hops) * HOP_TIME, 0.4, SLIDE_TIME_MAX)
	if _slide_tweens.has(id):
		(_slide_tweens[id] as Tween).kill()
	var start := _hop_point(seat, false, from_idx, to_idx, float(placement.shift), 0.0)
	var final_pos := _cell_world(seat, placement.cell) + Vector2(placement.shift, 0)
	_slide[id] = start - final_pos              # sin esto la ficha aparecería un cuadro en su casilla final
	_slide_end[id] = _now() + time
	_play_animation(id, WALK_ANIMATION)
	var walker: Variant = _pieces.get(id)
	if walker != null and is_instance_valid(walker) and (walker as Node).has_method("face"):
		(walker as Node).call("face", float(to_idx - from_idx))   # el corredor se recorre hacia la derecha
	_play_steps(float(hops), time)
	var tween := create_tween()
	tween.tween_method(_set_hop.bind(id, seat, false, from_idx, to_idx, float(placement.shift)), 0.0, 1.0, time)
	tween.tween_callback(_end_slide.bind(id))
	_slide_tweens[id] = tween

## Punto del salto en el instante t (0..1) de la ruta isla a isla. Con `from_portal` empieza en el portal.
func _hop_point(seat: int, from_portal: bool, from_idx: int, to_idx: int, shift: float, t: float) -> Vector2:
	var lane = _lanes[seat]
	var pts: Array[Vector2] = []
	if from_portal:
		pts.append(lane.stairs_top())
	var step := 1 if to_idx >= from_idx else -1
	var i := from_idx
	while true:
		pts.append(lane.cell_pos(i))
		if i == to_idx:
			break
		i += step
	pts[pts.size() - 1] += Vector2(shift, 0.0)
	if pts.size() < 2:
		return pts[0]
	var hops := pts.size() - 1
	var u := clampf(t, 0.0, 1.0) * float(hops)
	var k := mini(int(u), hops - 1)
	var f := u - float(k)
	return pts[k].lerp(pts[k + 1], f) + Vector2(0.0, -sin(PI * f) * HOP_HEIGHT)

func _set_hop(t: float, id: String, seat: int, from_portal: bool, from_idx: int, to_idx: int, shift: float) -> void:
	_put_piece_at(id, _hop_point(seat, from_portal, from_idx, to_idx, shift, t))

## Pone la ficha en `desired` (mundo) usando el desfase sobre su casilla final.
func _put_piece_at(id: String, desired: Vector2) -> void:
	var pl: Dictionary = _placements.get(id, {})
	if pl.is_empty() or not _chunks.has(pl.chunk):
		return
	_slide[id] = desired - (_cell_world(pl.chunk, pl.cell) + Vector2(pl.shift, 0))

func _descent_walk(t: float, id: String, seat: int, stairs_cell: Vector2i, offset: Vector2) -> void:
	_put_piece_at(id, _cell_world(seat, stairs_cell) + offset * (1.0 - t))

func _descent_stairs(t: float, id: String, seat: int, stairs_cell: Vector2i) -> void:
	_put_piece_at(id, _cell_world(seat, stairs_cell) + STAIRS_DROP_VEC * t)
	_set_piece_alpha(id, 1.0 - t)

## Pantalla en negro: cambia la vista al corredor y la ficha aparece arriba de la escalera.
func _descent_cut(id: String, seat: int, lane_offset: Vector2) -> void:
	_descents.erase(id)
	_follow_piece = ""
	_view_target = seat
	_apply_view()
	_slide[id] = lane_offset
	_set_piece_alpha(id, 1.0)
	var piece: Variant = _pieces.get(id)
	if piece != null and is_instance_valid(piece) and (piece as Node).has_method("face"):
		(piece as Node).call("face", 1.0)

# --- Casas y compuerta de la escalera -----------------------------------------------

## Las fichas en casa NO se dibujan como fichas: cada una es un HomeSlot del fondo (arena, hielo, acido,
## lava). Aqui se oculta la ficha real mientras esta en casa y se muestra su hueco. Una ficha que sale
## (o vuelve capturada) camina desde/hasta su hueco: mientras se desliza se ve la ficha real.
func _sync_homes() -> void:
	for id in _placements:
		var pl: Dictionary = _placements[id]
		var at_home: bool = pl.status == "HOME"
		var moving := _slide.has(id)
		var node: Node2D = _pieces.get(id)
		if node != null:
			node.visible = (not at_home) or moving
		var seat := int(pl.seat)
		if not _chunks.has(seat):
			continue
		var signs = _chunks[seat].get("signs")
		if signs != null and signs.crowd != null:
			signs.crowd.set_present(int(pl.number), at_home and not moving, not _homes_synced)
	_homes_synced = true

## El SEGURO de la escalera de cada chunk se abre cuando una ficha DEL DUEÑO (mismo color) pasa o se queda encima (y mientras
## baja): la casilla se parte en dos y deja ver la escalera. Se cierra sola al irse (strip_signs.gd).
func _update_hatches() -> void:
	var stairs_cell: Vector2i = BoardMap.stairs_cell()
	for seat in _chunks:
		var signs = _chunks[seat].get("signs")
		if signs == null:
			continue
		var spot := _cell_world(int(seat), stairs_cell)
		var open := false
		for id in _pieces:
			var node: Node2D = _pieces[id]
			if not is_instance_valid(node) or not node.visible:
				continue
			var pl: Dictionary = _placements.get(id, {})
			if pl.is_empty() or int(pl.seat) != int(seat):
				continue                          # solo la compuerta del dueño: fichas de otro color pasan de largo
			if _is_lane_cell(pl.cell) and not _descents.has(id):
				continue                          # ya esta en la pantalla del corredor
			if not _descents.has(id) and int(pl.get("progress", -1)) < BoardMap.stairs_progress():
				continue                          # solo abre quien ya llego al seguro de entrada (progreso 63): las que vienen detras no
			var d := node.global_position - spot
			if absf(d.x) <= HATCH_RADIUS and d.y > -14.0 and d.y < 40.0:
				open = true
				break
		signs.set_open(open)

# --- Mundo en bucle ---------------------------------------------------------------

func _slot_x(slot: float) -> float:
	return _center_x + slot * CHUNK_WIDTH

## Coloca cada chunk en la copia del anillo más cercana a la cámara.
func _update_chunks() -> void:
	var cam_x := camera.global_position.x if camera != null else _cam_target_x
	if _view_lane >= 0:
		cam_x = _cam_target_x                    # en un corredor la camara esta lejos: el tablero conserva su sitio
	var cam_slot := (cam_x - _center_x) / CHUNK_WIDTH
	if _view_lane < 0:
		# mezcla continua entre el fondo de la zona de la izquierda y el de la derecha
		var lower := floori(cam_slot)
		var mix := smoothstep(0.3, 0.7, cam_slot - lower)
		zone_blend.emit(BoardMap.seat_of_slot(posmod(lower, BoardMap.SEATS)),
				BoardMap.seat_of_slot(posmod(lower + 1, BoardMap.SEATS)), mix)
	for seat in _chunks:
		var base := BoardMap.slot_of_seat(seat)
		var slot := base + BoardMap.SEATS * roundi((cam_slot - base) / float(BoardMap.SEATS))
		if slot != int(_assigned[seat]):
			_assigned[seat] = slot
			_chunks[seat].holder.number_part = slot
		if _backdrops.has(seat):          # el fondo va con su chunk: misma x que el centro del chunk, a la altura de la camara
			var bd: Node2D = _backdrops[seat]
			var cam_y := camera.global_position.y if camera != null else _cam_y
			bd.global_position = Vector2(_slot_x(slot), cam_y)
			bd.visible = absf(cam_x - _slot_x(slot)) < BACKDROP_RANGE and _view_lane < 0

## Las fichas siguen a su chunk, que cambia de copia al dar la vuelta.
func _place_pieces() -> void:
	for id in _placements:
		var pl: Dictionary = _placements[id]
		var node: Node2D = _pieces.get(id)
		if node != null:
			var slide: Vector2 = _slide.get(id, Vector2.ZERO)
			var target_pos := _cell_world(pl.chunk, pl.cell) + Vector2(pl.shift, 0) + slide
			# Mientras camina, la ficha mira hacia donde SE MUEVE en pantalla (no hacia donde se calculo al
			# empezar): evita que quede de espaldas con el camino corto del anillo o al cambiar de chunk.
			# Los saltos grandes (el mundo en bucle, teletransportes) no cuentan como pasos.
			if _slide.has(id) and node.has_method("face"):
				var step := target_pos.x - node.global_position.x
				if absf(step) > 0.3 and absf(step) < 48.0:
					node.call("face", step)
			node.global_position = target_pos
	for id in _halos:
		var piece_node: Node2D = _pieces.get(id)
		if piece_node != null:
			_halos[id].global_position = piece_node.global_position
	for target in _targets:
		target.global_position = _cell_world(target.chunk, target.cell) + (target.get_meta("nudge", Vector2.ZERO) as Vector2)

# --- Cámara ---------------------------------------------------------------------------

func _focus_initial() -> void:
	_focused_once = true
	var seat := 0
	var mine: Dictionary = GameNet.player(GameNet.me)
	if mine.has("seat"):
		seat = int(mine.seat)
	seat = clampi(seat, 0, BoardMap.SEATS - 1)
	if not _chunks.has(seat):
		seat = int(_chunks.keys()[0])
	_cam_y = _cell_world(seat, Vector2i(-1, 3)).y - STRIP_SCREEN_DROP
	_cam_target_x = _slot_x(BoardMap.slot_of_seat(seat))
	if camera != null:
		camera.global_position = Vector2(_cam_target_x, _cam_y)
		_update_chunks()

## Flechas del teclado o botones de la interfaz.
func _pan_input() -> int:
	var dir := _pan_dir
	if _press_dir != 0 and _now() - _press_time >= TAP_TIME:
		dir = _press_dir                        # mantenida: recorre el mapa
	if Input.is_action_pressed("ui_left"):
		dir -= 1
	if Input.is_action_pressed("ui_right"):
		dir += 1
	return clampi(dir, -1, 1)

## Cámara continua: sigue a la ficha que se desliza o se acerca suave a su objetivo.
## Si el jugador la mueve a mano, manda él hasta que haya otro motivo para moverla.
func _update_camera(delta: float) -> void:
	if camera == null or not _focused_once:
		return
	if _view_lane >= 0:
		camera.global_position = _lanes[_view_lane].view_center()
		if _pan_input() != 0:                    # mover la camara a mano saca del corredor
			_cam_target_x = _stairs_world(_view_lane).x
			_switch_view(-1)
		return
	var dir := _pan_input()
	if dir != 0:
		_follow_piece = ""
		_cam_target_x = camera.global_position.x + dir * PAN_SPEED * delta
		camera.global_position = Vector2(_cam_target_x, _cam_y)
		return
	if _follow_piece != "":
		var node: Variant = _pieces.get(_follow_piece)
		if node != null and is_instance_valid(node) and _on_strip(_follow_piece):
			_cam_target_x = (node as Node2D).global_position.x
	var t := 1.0 - exp(-CAM_SMOOTH * delta)
	camera.global_position = Vector2(
			lerpf(camera.global_position.x, _cam_target_x, t),
			lerpf(camera.global_position.y, _cam_y, t))

# --- Fichas y celdas ----------------------------------------------------------------

func _piece_node(id: String, seat: int) -> Node2D:
	if _pieces.has(id):
		return _pieces[id]
	var node := PIECE_SCENE.instantiate() as Node2D
	node.name = id
	_pieces_layer.add_child(node)
	if node.has_method("set_seat"):
		node.call("set_seat", seat)               # esqueleto del color del asiento
	else:
		node.modulate = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	var anim := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation(IDLE_ANIMATION):
		anim.play(IDLE_ANIMATION)
	_pieces[id] = node
	return node

## Centro de la celda en coordenadas del mundo.
func _cell_world(seat: int, cell: Vector2i) -> Vector2:
	if _is_lane_cell(cell) and _lanes.has(seat):
		return _lanes[seat].cell_pos(BoardMap.LANE_LEN - 1 - cell.x)   # (7,4) es la casilla 1 del corredor
	var ground: Node2D = _chunks[seat].ground
	var p: Vector2 = ground.to_global(ground.map_to_local(cell))
	if cell.y == 1 or cell.y == 2:
		# casa: el hueco del fondo de este color (HomeCrowd); la ficha n usa el hueco n
		var homes: Array = _chunks[seat].homes
		var number := maxi(homes.find(cell), 0)
		return ground.to_global(ground.map_to_local(Vector2i(-1, 3))) + BoardMap.home_offset(seat, number)
	return p + Vector2(0, FOOT_Y)

## Las casillas de la fila del corredor viejo ahora son de la pantalla del corredor final.
static func _is_lane_cell(cell: Vector2i) -> bool:
	return cell.y == LANE_ROW and cell.x >= 0 and cell.x < BoardMap.LANE_LEN

## Pie de la escalera de bajada de un chunk, en el tablero.
func _stairs_world(seat: int) -> Vector2:
	return _cell_world(seat, BoardMap.stairs_cell()) + STAIRS_DROP_VEC * 0.6

## Donde se dibuja el destino de un movimiento. Si la ficha aun esta en el tablero y el
## destino es del corredor (otra pantalla), se marca en la escalera, uno bajo otro.
func _marker_spot(placed: Dictionary, piece_id: String, slot: int) -> Dictionary:
	var cell: Vector2i = placed.cell
	var nudge := Vector2.ZERO
	if _is_lane_cell(cell):
		var pl: Dictionary = _placements.get(piece_id, {})
		if pl.is_empty() or not _is_lane_cell(pl.cell):
			cell = BoardMap.stairs_cell()
			nudge = Vector2(0, -20.0 * slot)           # sobre la casilla de la escalera (compuerta), uno sobre otro
	return {"chunk": int(placed.seat), "cell": cell, "nudge": nudge}

func _chunk_center(seat: int) -> Vector2:
	var ground: Node2D = _chunks[seat].ground
	var cells := _used_cells(ground)
	if cells.is_empty():
		return ground.global_position
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var local: Vector2 = (ground.map_to_local(lo) + ground.map_to_local(hi)) / 2.0
	return ground.to_global(local)

## Busca dentro de un chunk: quién tiene `number_part`, el TileMap/TileMapLayer del
## suelo y el de PrisonCell. {} si el nodo no es un chunk.
func _chunk_parts(root: Node) -> Dictionary:
	var holder: Node = null
	var ground: Node = null
	var prison: Node = null
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var n: Node = pending.pop_front()
		if holder == null and "number_part" in n:
			holder = n
		if n.has_method("map_to_local"):
			if n.name == &"PrisonCell":
				prison = n
			elif n.name != &"ArrivalsCorridor" and ground == null:
				ground = n
		pending.append_array(n.get_children())
	if holder == null or ground == null:
		return {}
	return {"holder": holder, "ground": ground, "prison": prison if prison != null else ground}

## Celdas de la cárcel del chunk, ordenadas por fila y columna: la ficha n usa la n.
func _read_homes(prison: Node) -> Array[Vector2i]:
	var cells := _used_cells(prison)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	if cells.size() != 4:
		push_warning("BoardView: la cárcel tiene %d celdas y deberían ser 4" % cells.size())
	return cells

static func _used_cells(node: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if node.is_class("TileMapLayer"):
		out.assign(node.get_used_cells())
	else:
		out.assign(node.get_used_cells(0))    # TileMap
	return out
