extends CanvasLayer
## HUD de la partida. US-020: minimapa con las fichas de todos los jugadores y
## botones para recorrer los chunks del tablero (game.gd los conecta a BoardView).

signal view_step(direction: int)    # -1 izquierda, 1 derecha

const SHARED_CELL_SPACING := 2.0

var _layer: Node2D                  # TileMapLayer del minimapa: las fichas van dentro, así comparten su transformación
var _pieces_root: Node2D
var _pieces := {}                   # id de ficha -> MinimapPiece

func _ready() -> void:
	var minimap := find_child("MiniMap", true, false)
	if minimap != null:
		_layer = minimap.find_child("TileMapLayer", true, false) as Node2D
	var test_piece := find_child("GamePice", true, false)
	if test_piece != null:
		test_piece.queue_free()     # ficha de prueba de la escena
	if _layer != null:
		_pieces_root = Node2D.new()
		_pieces_root.name = "MiniPieces"
		_layer.add_child(_pieces_root)
	else:
		push_warning("GameUI: no se encontró el TileMapLayer del minimapa")

	var left := find_child("ButtonL", true, false) as Button
	var right := find_child("ButtonR", true, false) as Button
	if left != null:
		left.pressed.connect(func(): view_step.emit(-1))
	if right != null:
		right.pressed.connect(func(): view_step.emit(1))

	GameNet.state_changed.connect(_refresh_minimap)
	if not GameNet.state.is_empty():
		_refresh_minimap(GameNet.state)

func _refresh_minimap(state: Dictionary) -> void:
	if _pieces_root == null:
		return
	var entries: Array = []
	var group_sizes := {}
	for p in state.get("pieces", []):
		var seat := BoardMap.seat_of_piece(p)
		if seat < 0:
			continue
		var cell := Vector2i.ZERO
		var key := ""
		if BoardMap.is_home(p):
			cell = BoardMap.minimap_home(seat, int(p.get("number", 0)))
			key = "home-%s" % str(p.get("id", ""))
		else:
			var cell_id := BoardMap.piece_cell_id(p, seat)
			if not BoardMap.is_valid_id(cell_id):
				continue
			cell = BoardMap.minimap_cell(cell_id)
			key = "cell-%d" % cell_id
		group_sizes[key] = int(group_sizes.get(key, 0)) + 1
		entries.append({"piece": p, "seat": seat, "key": key, "cell": cell})

	var placed_count := {}
	var seen := {}
	for e in entries:
		var id := str(e.piece.get("id", ""))
		seen[id] = true
		var index := int(placed_count.get(e.key, 0))
		placed_count[e.key] = index + 1
		var shift := (index - (int(group_sizes[e.key]) - 1) / 2.0) * SHARED_CELL_SPACING
		var node := _piece_node(id, e.seat)
		node.position = _layer.map_to_local(e.cell) + Vector2(shift, 0)

	for id in _pieces.keys():
		if not seen.has(id):
			_pieces[id].queue_free()
			_pieces.erase(id)

func _piece_node(id: String, seat: int) -> MinimapPiece:
	if _pieces.has(id):
		return _pieces[id]
	var node := MinimapPiece.new()
	node.name = id
	node.color = BoardMap.SEAT_COLORS[posmod(seat, BoardMap.SEATS)]
	_pieces_root.add_child(node)
	_pieces[id] = node
	return node
