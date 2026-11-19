extends Control
## Trivia de las casillas de carta (US-007).
##
## Todo sale de `GameNet.state.trivia` y de TRIVIA_RESOLVED: aquí no se decide si
## una respuesta es correcta (el servidor nunca manda la respuesta antes de
## resolver) ni se vence el tiempo (solo se muestra la cuenta atrás).
## - El jugador de `trivia.playerId` ve botones; los demás ven la pregunta y quién
##   responde, sin poder tocar nada.
## - Al resolverse se resalta la respuesta correcta unos segundos y se cierra.
## - Tiempo agotado: el servidor lo cuenta como incorrecta, aquí se avisa.
## Mientras ruedan unos dados (RollHold) no se abre ni se cierra nada, para que
## la ficha termine de moverse antes de que salga la pregunta.

const LABEL_WHITE := preload("res://service/assets/ui/prefabs/PixelFontWhite.tres")
const PANEL_WIDTH := 300.0
const OPTION_SIZE := Vector2(144, 30)
const RESULT_TIME := 1.8
const LOW_TIME := 5
const OK_COLOR := Color(0.55, 1.0, 0.6)
const BAD_COLOR := Color(1.0, 0.5, 0.45)
const PICKED_COLOR := Color(1.0, 0.95, 0.5)
const DISABLED_COLOR := Color(1, 1, 1, 0.6)
const URGENT_COLOR := Color(1.0, 0.45, 0.4)

@onready var _panel := $PromptContainer as PanelContainer
@onready var _box := $PromptContainer/MarginContainer/VBoxContainer as VBoxContainer
@onready var _prompt := $PromptContainer/MarginContainer/VBoxContainer/PromptLabel as Label
@onready var _grid := $PromptContainer/MarginContainer/VBoxContainer/GridContainer as GridContainer

var _who: Label
var _timer: Label
var _result: Label
var _buttons: Array[TextureButton] = []
var _current := {}                  # trivia que está en pantalla
var _shown_id := ""
var _answered := false
var _picked := -1
var _result_left := 0.0
var _pending_events: Array = []

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE         # el cuadro vacío del centro no debe tapar el tablero
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size.x = PANEL_WIDTH
	for child in _grid.get_children():                  # los botones de prueba de la escena
		child.queue_free()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_box.add_theme_constant_override("separation", 6)

	_who = _make_label()
	_box.add_child(_who)
	_box.move_child(_who, 0)
	_prompt.label_settings = LABEL_WHITE.duplicate() as LabelSettings
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size.x = PANEL_WIDTH - 16.0
	_timer = _make_label()
	_box.add_child(_timer)
	_result = _make_label()
	_box.add_child(_result)

	GameNet.events_received.connect(_on_events)
	GameNet.action_rejected.connect(func(_code: String, _message: String): _answered = false)

func _make_label() -> Label:
	var label := Label.new()
	label.label_settings = LABEL_WHITE.duplicate() as LabelSettings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = PANEL_WIDTH - 16.0
	return label

func _on_events(events: Array, _version: int) -> void:
	for e in events:
		if e is Dictionary and str(e.get("type", "")) == "TRIVIA_RESOLVED":
			_pending_events.append(e)

func _process(delta: float) -> void:
	if RollHold.active():
		return
	_flush_events()
	if _result_left > 0.0:
		_result_left -= delta
		if _result_left <= 0.0:
			_close()
		return
	var trivia := _trivia_state()
	if trivia.is_empty():
		if _shown_id != "":
			_close()
		return
	if str(trivia.get("id", "")) != _shown_id:
		_open(trivia)
	_update_live(trivia)

func _trivia_state() -> Dictionary:
	if GameNet.state.get("status") != "ACTIVE":
		return {}
	var trivia: Variant = GameNet.state.get("trivia")
	return trivia if trivia is Dictionary else {}

# --- Abrir y cerrar ---------------------------------------------------------------------

func _open(trivia: Dictionary) -> void:
	_clear_buttons()
	_current = trivia
	_shown_id = str(trivia.get("id", ""))
	_answered = false
	_picked = -1
	_result_left = 0.0
	var mine := _is_mine(trivia)
	_who.text = "Responde la trivia" if mine else "%s responde la trivia" % GameText.who(str(trivia.get("playerId", "")))
	_prompt.text = str(trivia.get("prompt", ""))
	_result.text = ""
	_result.visible = false
	var options: Array = trivia.get("options", []) if trivia.get("options") is Array else []
	for i in options.size():
		var button := GameText.make_button(str(options[i]), OPTION_SIZE)
		_grid.add_child(button)
		button.pressed.connect(_on_option_pressed.bind(i))
		_buttons.append(button)
	visible = true
	_panel.reset_size.call_deferred()

func _close() -> void:
	visible = false
	_clear_buttons()
	_current = {}
	_shown_id = ""
	_result_left = 0.0
	_answered = false
	_picked = -1

func _clear_buttons() -> void:
	for button in _buttons:
		button.queue_free()
	_buttons.clear()

func _is_mine(trivia: Dictionary) -> bool:
	return str(trivia.get("playerId", "")) == GameNet.me

# --- Respuesta ----------------------------------------------------------------------------------

func _on_option_pressed(index: int) -> void:
	if _answered or GameNet.busy or _result_left > 0.0 or not _is_mine(_current):
		return
	if GameNet.answer_trivia(index):
		_answered = true
		_picked = index
		_update_live(_current)

## Cuenta atrás y estado de los botones (se llama cada frame mientras hay trivia).
func _update_live(trivia: Dictionary) -> void:
	var locked := _answered or GameNet.busy or not _is_mine(trivia)
	for i in _buttons.size():
		_buttons[i].disabled = locked
		_buttons[i].modulate = PICKED_COLOR if i == _picked else (DISABLED_COLOR if locked else Color.WHITE)
	var seconds := GameText.seconds_until(trivia.get("deadline"))
	_timer.text = "" if seconds < 0 else "%ds" % seconds
	_timer.label_settings.font_color = URGENT_COLOR if seconds >= 0 and seconds <= LOW_TIME else Color.WHITE

# --- Resultado (TRIVIA_RESOLVED) -------------------------------------------------------

func _flush_events() -> void:
	while not _pending_events.is_empty():
		_show_result(_pending_events.pop_front())

## El estado nuevo ya no trae la trivia: lo que se resalta sale de la que quedó guardada.
func _show_result(e: Dictionary) -> void:
	var data: Dictionary = e.data if e.get("data") is Dictionary else {}
	if _current.is_empty() or str(data.get("challengeId", "")) != _shown_id:
		return
	var mine := _is_mine(_current)
	var correct := bool(data.get("correct", false))
	var correct_index: Variant = data.get("correctIndex")
	for i in _buttons.size():
		_buttons[i].disabled = true
		_buttons[i].modulate = DISABLED_COLOR
	if correct_index != null and int(correct_index) >= 0 and int(correct_index) < _buttons.size():
		_buttons[int(correct_index)].modulate = OK_COLOR
	if not correct and _picked >= 0 and _picked < _buttons.size():
		_buttons[_picked].modulate = BAD_COLOR
	var answerer := GameText.who(str(data.get("playerId", _current.get("playerId", ""))))
	var text := ""
	if str(data.get("reason", "")) == "CATALOG_UNAVAILABLE":
		text = "La trivia no está disponible"
	elif correct:
		text = "¡Correcto! Ganas una carta buff" if mine else "%s acertó: gana un buff" % answerer
	elif mine and _picked < 0:
		text = "Tiempo agotado: cuenta como incorrecta"     # US-007 esc. 4
	elif mine:
		text = "Incorrecto: recibes un nerf"
	else:
		text = "%s falló: recibe un nerf" % answerer
	_result.text = text
	_result.visible = true
	_result.label_settings.font_color = OK_COLOR if correct else BAD_COLOR
	_timer.text = ""
	_who.text = "Resultado"
	_result_left = RESULT_TIME
	_panel.reset_size.call_deferred()
