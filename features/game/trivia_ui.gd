extends Control
## Trivia de las casillas de carta (US-007).
##
## Todo sale de `Presenter.view().trivia` y de TRIVIA_RESOLVED: aquí no se decide si
## una respuesta es correcta (el servidor nunca manda la respuesta antes de
## resolver) ni se vence el tiempo (solo se muestra la cuenta atrás).
## - El jugador de `trivia.playerId` ve botones; los demás ven la pregunta y quién
##   responde, sin poder tocar nada.
## - Al resolverse se resalta la respuesta correcta unos segundos y se cierra.
## - Tiempo agotado: el servidor lo cuenta como incorrecta, aquí se avisa.
## Mientras ruedan unos dados (RollHold) no se abre ni se cierra nada, para que
## la ficha termine de moverse antes de que salga la pregunta.

const LABEL_WHITE := preload("res://service/assets/ui/prefabs/PixelFontWhite.tres")
const OPTION_SIZE := Vector2(150, 30)
const LETTERS := ["A", "B", "C", "D", "E", "F"]
const RESULT_TIME := 1.8
const LOW_TIME := 5
const OK_COLOR := Color(0.55, 1.0, 0.6)
const BAD_COLOR := Color(1.0, 0.5, 0.45)
const PICKED_COLOR := Color(1.0, 0.95, 0.5)
const DISABLED_COLOR := Color(1, 1, 1, 0.6)
const URGENT_COLOR := Color(1.0, 0.45, 0.4)

@onready var _panel: PanelContainer = %PromptContainer
@onready var _dim: ColorRect = %Dim
@onready var _prompt: Label = %PromptLabel
@onready var _grid: GridContainer = %GridContainer
@onready var _bar: ProgressBar = %TimerBar

@onready var _who: Label = %WhoLabel
@onready var _timer: Label = %TimerLabel
@onready var _result: Label = %ResultLabel

var _buttons: Array[BaseButton] = []
var _total := 0.0                  # segundos que tenia la cuenta atras al abrirse (para la barra)
var _pop: Tween
var _current := {}                  # trivia que está en pantalla
var _shown_id := ""
var _answered := false
var _picked := -1
var _result_left := 0.0
var _pending_events: Array = []

func _ready() -> void:
	visible = false
	_dim.color.a = 0.0

	Presenter.events_shown.connect(_on_events)
	GameNet.action_rejected.connect(func(_code: String, _message: String): _answered = false)

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
	if Presenter.view().get("status") != "ACTIVE":
		return {}
	var trivia: Variant = Presenter.view().get("trivia")
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
	_total = 0.0
	_bar.visible = true
	_bar.value = 1.0
	_timer.label_settings.font_color = Color.WHITE
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP if mine else Control.MOUSE_FILTER_IGNORE    # quien responde no toca el tablero
	var options: Array = trivia.get("options", []) if trivia.get("options") is Array else []
	for i in options.size():
		var button := Button.new()                   # estilo ladrillo del tema, igual que las opciones de ajustes
		button.custom_minimum_size = OPTION_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = "%s  %s" % [LETTERS[i % LETTERS.size()], str(options[i])]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(button)
		button.pressed.connect(_on_option_pressed.bind(i))
		_buttons.append(button)
	visible = true
	Sfx.play(&"trivia_start")
	_panel.reset_size.call_deferred()
	_play_pop.call_deferred()

## Entrada: el fondo se oscurece y la pestaña "salta" un poco hacia su tamano.
func _play_pop() -> void:
	if _pop != null:
		_pop.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.88, 0.88)
	_panel.modulate.a = 0.0
	_pop = create_tween().set_parallel(true)
	_pop.tween_property(_dim, "color:a", 0.6, 0.18)
	_pop.tween_property(_panel, "modulate:a", 1.0, 0.14)
	_pop.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _close() -> void:
	visible = false
	_dim.color.a = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var locked :bool= _answered or GameNet.busy or not _is_mine(trivia)
	for i in _buttons.size():
		_buttons[i].disabled = locked
		_buttons[i].modulate = PICKED_COLOR if i == _picked else (DISABLED_COLOR if locked else Color.WHITE)
	var seconds := GameText.seconds_until(trivia.get("deadline"))
	_timer.text = "" if seconds < 0 else "%ds" % seconds
	var urgent := seconds >= 0 and seconds <= LOW_TIME
	_timer.label_settings.font_color = URGENT_COLOR if urgent else Color.WHITE
	if seconds >= 0:
		_total = maxf(_total, float(seconds))
		_bar.value = clampf(float(seconds) / maxf(_total, 1.0), 0.0, 1.0)
	_bar.modulate = URGENT_COLOR if urgent else Color.WHITE

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
	if str(data.get("reason", "")) != "CATALOG_UNAVAILABLE":
		Sfx.play(&"trivia_right" if correct else &"trivia_wrong", 0.0 if mine else -6.0)
	_result.label_settings.font_color = OK_COLOR if correct else BAD_COLOR
	_timer.text = ""
	_bar.visible = false
	_who.text = "Resultado"
	_result_left = RESULT_TIME
	_panel.reset_size.call_deferred()
