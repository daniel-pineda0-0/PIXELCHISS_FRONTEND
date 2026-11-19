class_name CardPanel
extends Control
## Panel de carta (US-008 y US-009), arriba al centro bajo el aviso de turno.
##
## - Carta que pide objetivo (`state.card`): muestra el nombre, el efecto y la
##   cuenta atrás. No hay inventario ni forma de guardarla: o se elige objetivo o
##   el servidor la descarta al vencer el plazo. Quien elige toca el objetivo en
##   el tablero (lo dibuja BoardView); si alguna opción no se puede dibujar ahí,
##   se ofrece como botón en este panel.
## - Carta ya aplicada (EFFECT_APPLIED) o descartada (CARD_DISCARDED): aviso breve
##   con lo que hizo, para todos los jugadores.
## El panel no deja de pasar los clics al tablero, salvo en sus propios botones.

const LABEL_WHITE := preload("res://service/assets/ui/prefabs/PixelFontWhite.tres")
const PANEL_WIDTH := 232.0
const TOP_OFFSET := 44.0            # bajo el aviso de turno (game_ui)
const REVEAL_TIME := 2.6
const LOW_TIME := 5
const CHOICE_SIZE := Vector2(110, 24)
const BUFF_COLOR := Color(0.55, 1.0, 0.6)
const DEBUFF_COLOR := Color(1.0, 0.5, 0.45)
const URGENT_COLOR := Color(1.0, 0.45, 0.4)

var _panel: PanelContainer
var _kind: Label
var _title: Label
var _desc: Label
var _hint: Label
var _timer: Label
var _choices_box: VBoxContainer
var _shown_id := ""                 # desafío de carta que está en pantalla
var _reveal_left := 0.0
var _pending_events: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = TOP_OFFSET
	_panel.offset_bottom = TOP_OFFSET
	_panel.custom_minimum_size.x = PANEL_WIDTH

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	_kind = _make_label(box)
	_title = _make_label(box)
	_desc = _make_label(box)
	_hint = _make_label(box)
	_timer = _make_label(box)
	_choices_box = VBoxContainer.new()
	_choices_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choices_box.add_theme_constant_override("separation", 3)
	box.add_child(_choices_box)

	GameNet.events_received.connect(_on_events)

func _make_label(parent: Node) -> Label:
	var label := Label.new()
	label.label_settings = LABEL_WHITE.duplicate() as LabelSettings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = PANEL_WIDTH - 12.0
	parent.add_child(label)
	return label

func _on_events(events: Array, _version: int) -> void:
	for e in events:
		if e is Dictionary and str(e.get("type", "")) in ["EFFECT_APPLIED", "CARD_DISCARDED"]:
			_pending_events.append(e)

func _process(delta: float) -> void:
	if RollHold.active():
		return
	_flush_events()
	var card := _card_state()
	if not card.is_empty():
		_reveal_left = 0.0                                  # el desafío manda sobre un aviso
		if str(card.get("id", "")) != _shown_id:
			_open_challenge(card)
		_update_challenge(card)
		return
	if _shown_id != "":                                     # se resolvió: el evento trae el aviso
		_shown_id = ""
		_clear_choices()
		if _reveal_left <= 0.0:
			_panel.visible = false
	if _reveal_left > 0.0:
		_reveal_left -= delta
		if _reveal_left <= 0.0:
			_panel.visible = false

func _card_state() -> Dictionary:
	if GameNet.state.get("status") != "ACTIVE":
		return {}
	var card: Variant = GameNet.state.get("card")
	return card if card is Dictionary else {}

# --- Carta que pide objetivo -------------------------------------------------------------------

func _open_challenge(card: Dictionary) -> void:
	_clear_choices()
	_shown_id = str(card.get("id", ""))
	var pid := str(card.get("playerId", ""))
	var mine := pid == GameNet.me
	var effect_code := GameText.s(card.get("effectCode"))
	_fill(GameText.s(card.get("cardId")), GameText.s(card.get("name")),
			GameText.s(card.get("description")), effect_code, pid)
	if mine:
		_hint.text = _hint_for(effect_code)
		_build_fallback_choices(card)
	else:
		_hint.text = "%s elige un objetivo" % GameText.who(pid)
	_hint.visible = _hint.text != ""
	_panel.visible = true
	_panel.reset_size.call_deferred()

func _hint_for(effect_code: String) -> String:
	match effect_code:
		"CAPTURE_CHOSEN_CELL":
			return "Toca una casilla marcada en el tablero"
		"MOVE_SAFE":
			return "Toca una ficha y luego su destino"
	return "Elige un objetivo"

func _update_challenge(card: Dictionary) -> void:
	var seconds := GameText.seconds_until(card.get("deadline"))
	_timer.text = "" if seconds < 0 else "%ds" % seconds
	_timer.visible = seconds >= 0
	_timer.label_settings.font_color = URGENT_COLOR if seconds >= 0 and seconds <= LOW_TIME else Color.WHITE
	for button in _choices_box.get_children():
		(button as TextureButton).disabled = GameNet.busy

## Opciones que no se pueden tocar en el tablero (sin casilla ni ficha objetivo): botones.
func _build_fallback_choices(card: Dictionary) -> void:
	var choices: Array = card.get("choices", []) if card.get("choices") is Array else []
	for i in choices.size():
		var choice: Dictionary = choices[i] if choices[i] is Dictionary else {}
		if choice.is_empty() or GameText.s(choice.get("targetPosition")) != "" \
				or GameText.s(choice.get("targetPieceId")) != "":
			continue
		var text := "Opción %d" % (i + 1)
		if GameText.s(choice.get("targetPlayerId")) != "":
			text = GameText.short_name(GameText.player_name(GameText.s(choice.get("targetPlayerId"))))
		elif GameText.s(choice.get("pieceId")) != "":
			var parts := GameText.s(choice.get("pieceId")).split("-")
			text = "Ficha %d" % (int(parts[parts.size() - 1]) + 1)
		var button := GameText.make_button(text, CHOICE_SIZE)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_on_choice_pressed.bind(choice))
		_choices_box.add_child(button)

func _on_choice_pressed(choice: Dictionary) -> void:
	if not GameNet.busy:
		GameNet.pick_card(choice)

func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()

# --- Aviso de carta aplicada o descartada ---------------------------------------------

func _flush_events() -> void:
	while not _pending_events.is_empty():
		var e: Dictionary = _pending_events.pop_front()
		var data: Dictionary = e.data if e.get("data") is Dictionary else {}
		match str(e.get("type", "")):
			"EFFECT_APPLIED":
				_reveal(GameText.s(data.get("cardId")), GameText.s(data.get("playerId")),
						GameText.s(data.get("effectCode")), "")
			"CARD_DISCARDED":
				if data.get("cardId") != null:               # sin cardId solo hay aviso de texto (game_ui)
					_reveal(str(data.get("cardId")), "", "",
							GameText.discard_text(str(data.get("reason", ""))))

func _reveal(card_id: String, pid: String, effect_code: String, note: String) -> void:
	if not _card_state().is_empty():
		return                                              # hay un desafío en curso: no se pisa
	_clear_choices()
	_fill(card_id, "", "", effect_code, pid)
	_hint.text = note
	_hint.visible = note != ""
	_timer.visible = false
	_reveal_left = REVEAL_TIME
	_panel.visible = true
	_panel.reset_size.call_deferred()

# --- Contenido -----------------------------------------------------------------------------------

## `title` y `desc` vacíos se completan con el catálogo local.
func _fill(card_id: String, title: String, desc: String, effect_code: String, pid: String) -> void:
	var buff := GameText.card_is_buff(card_id, effect_code)
	var tag := "BUFF" if buff else "NERF"
	_kind.text = tag if pid == "" else "%s - %s" % [tag, GameText.who(pid)]
	_kind.label_settings.font_color = BUFF_COLOR if buff else DEBUFF_COLOR
	_title.text = title if title != "" else GameText.card_title(card_id, effect_code)
	_desc.text = desc if desc != "" else GameText.card_desc(card_id)
	_desc.visible = _desc.text != ""
	_timer.visible = false
