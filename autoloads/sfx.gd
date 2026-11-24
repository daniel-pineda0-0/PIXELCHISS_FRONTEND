extends Node
## Efectos de sonido (8 bits). Suenan por el bus "SFX" (lo crea el autoload Settings),
## asi que el deslizador de efectos de la ventana de ajustes los controla, aparte de la
## musica. Son cortos y suaves a proposito: no deben tapar la musica.
##
## Uso:   Sfx.play(&"confirm")          Sfx.play_group(&"vulture")
##
## Los botones, casillas, deslizadores y campos de texto suenan SOLOS: este autoload se
## engancha a cada nodo que entra al arbol. El sonido de un boton sale de BUTTON_SOUNDS
## (por nombre del nodo) o de un metadato:  boton.set_meta(&"sfx", &"vote")
## Con "" (o &"none") ese boton queda en silencio (porque la pantalla lo suena a mano).

const DIR := "res://service/assets/audio/sfx/"
const SOUNDS: Array[StringName] = [
	&"hover", &"click", &"confirm", &"back", &"ready_on", &"ready_off", &"start", &"copy",
	&"vote", &"gear", &"error", &"toggle_on", &"toggle_off", &"tick", &"type", &"select",
	&"player_join", &"player_leave", &"bot_add", &"bot_remove", &"kick", &"load_done",
	&"step", &"login_ok", &"fireball", &"explosion", &"collapse", &"rebuild",
	&"vulture_1", &"vulture_2", &"eye_fly", &"eye_turn", &"eye_stare",
	# partida
	&"dice_roll", &"dice_land", &"release", &"capture", &"captured", &"blow", &"crown",
	&"safe", &"trivia_start", &"trivia_right", &"trivia_wrong", &"card_draw", &"turn_mine",
	&"countdown", &"win", &"lose",
]
## Sonidos que se eligen al azar de un grupo, con un descanso minimo entre dos.
const GROUPS := {
	&"vulture": {"sounds": [&"vulture_1", &"vulture_2"], "gap": 4.0},
}
## Sonido de cada boton segun el nombre de su nodo. Los que no estan aqui hacen "click".
const BUTTON_SOUNDS := {
	"Button": &"confirm",          # entrar (login)
	"CreateButton": &"confirm",
	"JoinButton": &"confirm",
	"StartButton": &"start",
	"ReadyButton": &"",            # la sala lo suena segun quede listo o no
	"ExitButton": &"back",
	"QuitButton": &"back",
	"CloseButton": &"back",
	"LogoutButton": &"back",
	"CopyButton": &"copy",
	"VoteButton": &"vote",
	"OpenButton": &"gear",         # la tuerca
	"KickButton": &"kick",
	"PlayerButton": &"select",
}
const BASE_DB := -3.0              # nivel general de todos los efectos
const POOL_SIZE := 8
const HOVER_GAP := 0.05
const SLIDER_GAP := 0.06
const TYPE_GAP := 0.035

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _last_play := {}               # nombre -> ultimo momento en que sono (s)

func _ready() -> void:
	for sound in SOUNDS:
		var path := "%s%s.wav" % [DIR, sound]
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("Sfx: falta el sonido '%s'" % path)
			continue
		_streams[sound] = stream
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = Settings.BUS_SFX
		add_child(player)
		_players.append(player)
	get_tree().node_added.connect(_on_node_added)

# --- Reproducir ---

## Toca un sonido. `db` lo sube o baja; `pitch` lo hace mas agudo o grave;
## `min_gap` evita que se repita antes de esos segundos.
func play(sound: StringName, db := 0.0, pitch := 1.0, min_gap := 0.0) -> void:
	if sound == &"" or sound == &"none" or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and now - float(_last_play.get(sound, -100.0)) < min_gap:
		return
	_last_play[sound] = now
	var player := _free_player()
	player.stream = _streams[sound]
	player.volume_db = BASE_DB + db
	player.pitch_scale = pitch
	player.play()

## Toca uno al azar de un grupo de GROUPS, respetando el descanso del grupo.
func play_group(group: StringName, db := 0.0, pitch_min := 0.9, pitch_max := 1.1) -> void:
	if not GROUPS.has(group):
		return
	var info: Dictionary = GROUPS[group]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(group, -100.0)) < float(info.gap):
		return
	_last_play[group] = now
	var sounds: Array = info.sounds
	play(sounds[randi() % sounds.size()], db, randf_range(pitch_min, pitch_max))

## Corta un sonido largo que siga sonando (p. ej. al salir de la pantalla).
func stop(sound: StringName) -> void:
	for player in _players:
		if player.playing and player.stream == _streams.get(sound):
			player.stop()

func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]             # todos ocupados: se pisa el mas viejo

# --- Enganche automatico a controles ---

func _on_node_added(node: Node) -> void:
	if node.has_meta(&"sfx_hooked"):
		return
	if node is BaseButton:
		_hook_button(node as BaseButton)
	elif node is Slider:
		_hook_slider(node as Slider)
	elif node is LineEdit:
		_hook_line_edit(node as LineEdit)

func _hook_button(button: BaseButton) -> void:
	button.set_meta(&"sfx_hooked", true)
	button.mouse_entered.connect(func():
		if not button.disabled:
			play(&"hover", 0.0, 1.0, HOVER_GAP))
	if button is OptionButton:
		(button as OptionButton).item_selected.connect(func(_i: int): play(&"select"))
	elif button is CheckBox or button is CheckButton:
		button.toggled.connect(func(on: bool): play(&"toggle_on" if on else &"toggle_off"))
	else:
		button.pressed.connect(func(): play(_sound_for(button)))

func _sound_for(button: BaseButton) -> StringName:
	if button.has_meta(&"sfx"):
		return button.get_meta(&"sfx")
	return BUTTON_SOUNDS.get(String(button.name), &"click")

## Un tic mientras se arrastra (el tono sube con el valor). Si el valor lo pone el codigo
## (al abrir la pantalla) no suena: solo cuando el jugador tiene el raton pulsado o el foco.
func _hook_slider(slider: Slider) -> void:
	slider.set_meta(&"sfx_hooked", true)
	slider.value_changed.connect(func(value: float):
		if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or slider.has_focus()):
			return
		var span := maxf(slider.max_value - slider.min_value, 0.0001)
		var ratio := clampf((value - slider.min_value) / span, 0.0, 1.0)
		play(&"tick", 0.0, 0.75 + ratio * 0.7, SLIDER_GAP))

func _hook_line_edit(edit: LineEdit) -> void:
	edit.set_meta(&"sfx_hooked", true)
	edit.text_changed.connect(func(_t: String): play(&"type", 0.0, randf_range(0.92, 1.1), TYPE_GAP))
