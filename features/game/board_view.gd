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
const IDLE_ANIMATION := &"idl_ground_pice"
const CHUNK_WIDTH := 32.0 * 17.0      # 17 columnas de 32 px (igual que player_ground.gd)
const SHARED_CELL_SPACING := 8.0      # separación entre fichas que comparten casilla
const CAMERA_TIME := 0.35
## Desplazamiento vertical de la cámara respecto al centro del chunk. Negativo = el
## mapa se ve más abajo. El suelo mide 5 filas (160 px) y el minimapa llega a y≈196:
## con -48 la fila del recorrido queda por debajo del minimapa. Ajustar aquí.
const CAMERA_OFFSET_Y := -128.0
const CLICK_RADIUS := 16.0            # qué tan cerca del centro hay que tocar una ficha o un destino
const SLIDE_TIME := 0.28              # tiempo que tarda una ficha en deslizarse a su casilla nueva

const COLOR_CAPTURE := Color(1.0, 0.4, 0.4)
const COLOR_CROWN := Color(1.0, 0.85, 0.25)
const COLOR_RELEASE := Color(0.45, 1.0, 0.55)
const COLOR_SAFE := Color(0.4, 0.8, 1.0)
const COLOR_PLAIN := Color(1.0, 1.0, 1.0)

var world: Node2D
var camera: Camera2D

var _chunks := {}                     # asiento -> {holder, ground, prison, homes}
var _assigned := {}                   # asiento -> slot en que está ahora (sin límite, no módulo 4)
var _center_x := 0.0                  # x del centro de un chunk en el slot 0
var _pieces_layer: Node2D
var _pieces := {}                     # id de ficha -> Node2D
var _placements := {}                 # id de ficha -> {chunk, cell, shift}
var _focus_index := 0                 # slot enfocado, sin límite: izquierda/derecha lo restan/suman
var _focused_once := false
var _camera_tween: Tween

var _halo_layer: Node2D               # aros bajo las fichas
var _target_layer: Node2D             # destinos de la ficha elegida
var _halos := {}                      # id de ficha -> MoveMarker (HALO)
var _targets: Array = []              # MoveMarker (TARGET) de la ficha elegida
var _selected_piece := ""
var _focused_piece := ""              # última ficha a la que se llevó la cámara
var _focused_card := ""               # último desafío de carta al que se llevó la cámara
var _prev_placements := {}            # colocación de las fichas antes del último refresh()
var _slide := {}                      # id de ficha -> desfase que se va apagando (animación)
var _slide_tweens := {}
var _pending_state := {}              # último estado recibido mientras ruedan los dados
var _pending_events: Array = []       # eventos recibidos en ese lapso
var _was_holding := false

func setup(world_node: Node2D) -> void:
	world = world_node
	camera = world.get_node_or_null("Camera2D") as Camera2D
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
	_pieces_layer = Node2D.new()
	_pieces_layer.name = "Pieces"
	_pieces_layer.z_index = 10
	world.add_child(_pieces_layer)
	_halo_layer = Node2D.new()
	_halo_layer.name = "Halos"
	_halo_layer.z_index = 9          # bajo las fichas
	world.add_child(_halo_layer)
	_target_layer = Node2D.new()
	_target_layer.name = "Targets"
	_target_layer.z_index = 12       # sobre las fichas (un destino puede ser una casilla ocupada)
	world.add_child(_target_layer)

func _process(_delta: float) -> void:
	if _chunks.is_empty():
		return
	var holding := RollHold.active()
	if _was_holding and not holding:
		_flush_pending()
	_was_holding = holding
	_update_chunks()
	_place_pieces()

## Repinta todas las fichas desde un snapshot (conectar a GameNet.state_changed).
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
	_rebuild_overlays()
	_update_chunks()
	_place_pieces()

## Mueve la vista al chunk contiguo: -1 izquierda, 1 derecha. Sin fin: da vueltas al anillo.
func step_focus(direction: int) -> void:
	_focus_index += direction
	_move_camera(true)

func focus_seat(seat: int, animate := true) -> void:
	var base := BoardMap.slot_of_seat(seat)
	# La copia del chunk más cercana al enfoque actual, para no dar media vuelta al mundo.
	_focus_index = base + BoardMap.SEATS * roundi((_focus_index - base) / float(BoardMap.SEATS))
	_move_camera(animate)

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
			"PIECE_CAPTURED", "CARD_PIECE_RETURNED":
				# El estado nuevo ya sacó la ficha del tablero: el destello va donde estaba.
				# (CARD_PIECE_RETURNED: carta o castigo que la devolvió a casa, sin ficha atacante.)
				var prev: Dictionary = _prev_placements.get(piece_id, {})
				if prev.is_empty() or not _chunks.has(prev.chunk):
					continue
				MoveMarker.burst(_pieces_layer, _cell_world(prev.chunk, prev.cell) + Vector2(prev.shift, 0))
			"PIECE_MOVED":
				if str(data.get("status", "")) != "CROWNED":
					continue
				# Coronación (US-015): destello dorado en la corona, donde ya está la ficha.
				var now: Dictionary = _placements.get(piece_id, {})
				if now.is_empty() or not _chunks.has(now.chunk):
					continue
				MoveMarker.burst(_pieces_layer, _cell_world(now.chunk, now.cell) + Vector2(now.shift, 0), COLOR_CROWN)

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
	if RollHold.active() or GameNet.busy or not GameNet.is_my_turn():
		return []
	var turn: Variant = GameNet.state.get("turn")
	if not (turn is Dictionary) or not bool(turn.get("rolled", false)):
		return []
	if GameNet.state.get("trivia") != null or GameNet.state.get("card") != null:
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
		var halo: MoveMarker = _halos.get(id)
		if halo == null:
			halo = MoveMarker.new()
			halo.kind = MoveMarker.Kind.HALO
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
			var target := MoveMarker.new()
			target.kind = MoveMarker.Kind.TARGET
			target.label = str(die_value)
			target.color = _move_color(m)
			target.move = m
			target.chunk = int(placed.seat)
			target.cell = placed.cell
			_target_layer.add_child(target)
			_targets.append(target)

	_add_card_targets(card_choices)

	# La cámara sigue a la ficha elegida (solo cuando cambia la elección).
	if _selected_piece != _focused_piece:
		_focused_piece = _selected_piece
		if _selected_piece != "" and _placements.has(_selected_piece):
			focus_seat(int(_placements[_selected_piece].chunk))
	_focus_card_targets(card_choices)
	_place_pieces()

# --- Objetivos de carta (Fase 4) ---------------------------------------------------------

## Opciones de `state.card` que el jugador local puede tocar ahora. Vacío si la
## carta no es suya, ruedan unos dados o hay una acción en vuelo.
func _usable_card_choices() -> Array:
	if RollHold.active() or GameNet.busy:
		return []
	var card: Variant = GameNet.state.get("card")
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
	var card: Variant = GameNet.state.get("card")
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
		var target := MoveMarker.new()
		target.kind = MoveMarker.Kind.TARGET
		target.label = str(marker.label)
		target.color = marker.color
		target.move = c
		target.is_card = true
		target.chunk = int(placed.seat)
		target.cell = placed.cell
		_target_layer.add_child(target)
		_targets.append(target)

## Al abrirse una carta con casillas por elegir, la cámara va a la primera si ninguna se ve.
func _focus_card_targets(card_choices: Array) -> void:
	var card: Variant = GameNet.state.get("card")
	var card_id := GameText.s(card.get("id")) if card is Dictionary else ""
	if card_id == "":
		_focused_card = ""
		return
	if card_choices.is_empty() or card_id == _focused_card:
		return
	_focused_card = card_id
	if _selected_piece != "" or _targets.is_empty():
		return                                             # con ficha elegida la cámara ya la sigue
	var current_seat := BoardMap.seat_of_slot(posmod(_focus_index, BoardMap.SEATS))
	for target in _targets:
		if target.chunk == current_seat:
			return
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
		var halo: MoveMarker = _halos[id]
		if not halo.movable:
			continue
		var distance := halo.global_position.distance_to(pos)
		if distance <= best_distance:
			best = str(id)
			best_distance = distance
	if best != "":
		get_viewport().set_input_as_handled()
		_selected_piece = best
		_rebuild_overlays()

# --- Deslizamiento de fichas -----------------------------------------------------------

## La ficha aparece en su casilla nueva con un desfase hacia la vieja y lo va
## apagando. Se aplica sobre la posición, así sigue funcionando con el mundo en bucle.
func _start_slide(id: String, old: Dictionary, placement: Dictionary) -> void:
	var from_pos := _cell_world(old.chunk, old.cell) + Vector2(old.shift, 0)
	var to_pos := _cell_world(placement.chunk, placement.cell) + Vector2(placement.shift, 0)
	var offset := from_pos - to_pos
	var ring := BoardMap.SEATS * CHUNK_WIDTH
	offset.x = fposmod(offset.x + ring / 2.0, ring) - ring / 2.0   # el camino corto por el anillo
	if _slide_tweens.has(id):
		(_slide_tweens[id] as Tween).kill()
	_slide[id] = offset
	var tween := create_tween()
	tween.tween_method(_set_slide.bind(id, offset), 0.0, 1.0, SLIDE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_end_slide.bind(id))
	_slide_tweens[id] = tween

func _set_slide(t: float, id: String, offset: Vector2) -> void:
	_slide[id] = offset.lerp(Vector2.ZERO, t)

func _end_slide(id: String) -> void:
	_slide.erase(id)
	_slide_tweens.erase(id)

# --- Mundo en bucle ---------------------------------------------------------------

func _slot_x(slot: float) -> float:
	return _center_x + slot * CHUNK_WIDTH

## Coloca cada chunk en la copia del anillo más cercana a la cámara.
func _update_chunks() -> void:
	var cam_x := camera.global_position.x if camera != null else _slot_x(_focus_index)
	var cam_slot := (cam_x - _center_x) / CHUNK_WIDTH
	for seat in _chunks:
		var base := BoardMap.slot_of_seat(seat)
		var slot := base + BoardMap.SEATS * roundi((cam_slot - base) / float(BoardMap.SEATS))
		if slot != int(_assigned[seat]):
			_assigned[seat] = slot
			_chunks[seat].holder.number_part = slot

## Las fichas siguen a su chunk, que cambia de copia al dar la vuelta.
func _place_pieces() -> void:
	for id in _placements:
		var pl: Dictionary = _placements[id]
		var node: Node2D = _pieces.get(id)
		if node != null:
			var slide: Vector2 = _slide.get(id, Vector2.ZERO)
			node.global_position = _cell_world(pl.chunk, pl.cell) + Vector2(pl.shift, 0) + slide
	for id in _halos:
		var piece_node: Node2D = _pieces.get(id)
		if piece_node != null:
			_halos[id].global_position = piece_node.global_position
	for target in _targets:
		target.global_position = _cell_world(target.chunk, target.cell)

# --- Cámara ---------------------------------------------------------------------------

func _focus_initial() -> void:
	_focused_once = true
	var seat := 0
	var mine: Dictionary = GameNet.player(GameNet.me)
	if mine.has("seat"):
		seat = int(mine.seat)
	_focus_index = BoardMap.slot_of_seat(clampi(seat, 0, BoardMap.SEATS - 1))
	_move_camera(false)

func _move_camera(animate: bool) -> void:
	if camera == null or _chunks.is_empty():
		return
	var seat := BoardMap.seat_of_slot(posmod(_focus_index, BoardMap.SEATS))
	if not _chunks.has(seat):
		return
	var target := Vector2(_slot_x(_focus_index), _chunk_center(seat).y + CAMERA_OFFSET_Y)
	if _camera_tween != null:
		_camera_tween.kill()
	if not animate:
		camera.global_position = target
		_update_chunks()
		return
	_camera_tween = create_tween()
	_camera_tween.tween_property(camera, "global_position", target, CAMERA_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# --- Fichas y celdas ----------------------------------------------------------------

func _piece_node(id: String, seat: int) -> Node2D:
	if _pieces.has(id):
		return _pieces[id]
	var node := PIECE_SCENE.instantiate() as Node2D
	node.name = id
	node.modulate = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	_pieces_layer.add_child(node)
	var anim := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation(IDLE_ANIMATION):
		anim.play(IDLE_ANIMATION)
	_pieces[id] = node
	return node

## Centro de la celda en coordenadas del mundo.
func _cell_world(seat: int, cell: Vector2i) -> Vector2:
	var ground: Node2D = _chunks[seat].ground
	return ground.to_global(ground.map_to_local(cell))

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
