extends Control
## Menú previo a la sala: crear una sala (US-003) o unirse con un código (US-004).
## Los mensajes de error (sala llena, código incorrecto, partida iniciada,
## expulsado) los manda lobby-service y aquí solo se muestran.

@onready var create_button = %CreateButton    # JoinButton (tiene set_text)
@onready var code_input: LineEdit = %CodeInput
@onready var join_button = %JoinButton          # JoinButton (tiene set_text)
@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	create_button.set_text("New")
	join_button.set_text("Join")
	status_label.text = Lobby.notice    # p. ej. "Fuiste expulsado de la sala"
	Lobby.notice = ""
	code_input.text_changed.connect(_on_code_input_text_changed)
	code_input.text_submitted.connect(func(_text: String): _on_join_button_pressed())

func _on_create_button_pressed() -> void:
	_set_busy(true)
	status_label.text = "Creando sala..."
	var result := await Lobby.create()
	_after_enter(result)

func _on_join_button_pressed() -> void:
	var code := code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Escribe el codigo de la sala"
		return
	_set_busy(true)
	status_label.text = "Entrando a la sala..."
	var result := await Lobby.join(code)
	_after_enter(result)

func _after_enter(result: Dictionary) -> void:
	if result.ok:
		GameState.set_state(GameState.State.LOBBY)
		get_tree().change_scene_to_file(GameState.LOADING_SCENE)
	else:
		status_label.text = result.error
		_set_busy(false)

## El código siempre se escribe en mayúsculas (los códigos de sala lo son).
func _on_code_input_text_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var caret := code_input.caret_column
		code_input.text = upper
		code_input.caret_column = caret

func _set_busy(busy: bool) -> void:
	create_button.disabled = busy
	join_button.disabled = busy
	code_input.editable = not busy
