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

const PIECE_SCENE := preload("res://features/game/ground_pice.tscn")
const IDLE_ANIMATION := &"idl_ground_pice"
const CHUNK_WIDTH := 32.0 * 17.0      # 17 columnas de 32 px (igual que player_ground.gd)
const SHARED_CELL_SPACING := 8.0      # separación entre fichas que comparten casilla
const CAMERA_TIME := 0.35

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

func _process(_delta: float) -> void:
	if _chunks.is_empty():
		return
	_update_chunks()
	_place_pieces()

## Repinta todas las fichas desde un snapshot (conectar a GameNet.state_changed).
func refresh(state: Dictionary) -> void:
	if _pieces_layer == null or _chunks.is_empty():
		return
	if not _focused_once:
		_focus_initial()

	var entries: Array = []
	var group_sizes := {}
	for p in state.get("pieces", []):
		var seat := BoardMap.seat_of_piece(p)
		if seat < 0 or not _chunks.has(seat):
			continue
		var key := ""
		var chunk := seat
		var cell := Vector2i.ZERO
		if BoardMap.is_home(p):
			var homes: Array = _chunks[seat].homes
			if homes.is_empty():
				continue
			key = "home-%s" % str(p.get("id", ""))
			cell = homes[posmod(int(p.get("number", 0)), homes.size())]
		else:
			var cell_id := BoardMap.piece_cell_id(p, seat)
			var placed := BoardMap.strip_cell(cell_id)
			if placed.is_empty() or not _chunks.has(placed.seat):
				continue
			key = "cell-%d" % cell_id
			chunk = placed.seat
			cell = placed.cell
		group_sizes[key] = int(group_sizes.get(key, 0)) + 1
		entries.append({"piece": p, "seat": seat, "key": key, "chunk": chunk, "cell": cell})

	var placed_count := {}
	var seen := {}
	for e in entries:
		var id := str(e.piece.get("id", ""))
		seen[id] = true
		var index := int(placed_count.get(e.key, 0))
		placed_count[e.key] = index + 1
		var shift := (index - (int(group_sizes[e.key]) - 1) / 2.0) * SHARED_CELL_SPACING
		_piece_node(id, e.seat)
		_placements[id] = {"chunk": e.chunk, "cell": e.cell, "shift": shift}

	for id in _pieces.keys():
		if not seen.has(id):
			_pieces[id].queue_free()
			_pieces.erase(id)
			_placements.erase(id)
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
			node.global_position = _cell_world(pl.chunk, pl.cell) + Vector2(pl.shift, 0)

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
	var target := Vector2(_slot_x(_focus_index), _chunk_center(seat).y)
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
