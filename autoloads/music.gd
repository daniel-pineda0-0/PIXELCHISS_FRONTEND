extends Node
## Musica de fondo. Suena por el bus "Music" (lo crea el autoload Settings),
## asi que los deslizadores de volumen de la ventana de ajustes la controlan.
## Uso:  Music.play(&"login")      Music.stop()

const TRACKS := {
	&"login": "res://service/assets/audio/music/login_theme.ogg",
}
const SILENT_DB := -40.0

var _player := AudioStreamPlayer.new()
var _current: StringName = &""
var _tween: Tween

func _ready() -> void:
	_player.bus = Settings.BUS_MUSIC
	add_child(_player)

## Empieza una pista con fundido de entrada. Si ya suena otra, la baja primero.
## Si es la misma que ya esta sonando, no hace nada (no se reinicia al cambiar de pantalla).
func play(track: StringName, fade := 1.5) -> void:
	if track == _current and _player.playing:
		return
	if not TRACKS.has(track):
		push_warning("Music: pista desconocida '%s'" % track)
		return
	_current = track
	if _player.playing:
		await _fade_to(SILENT_DB, 0.6)
		if _current != track:         # llegó otra orden mientras bajaba
			return
	var stream := load(TRACKS[track]) as AudioStream
	if stream == null:
		push_warning("Music: no se pudo cargar '%s'" % TRACKS[track])
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true            # el loop no depende de la casilla de importacion
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play()
	_fade_to(0.0, fade)

func stop(fade := 1.0) -> void:
	_current = &""
	if not _player.playing:
		return
	await _fade_to(SILENT_DB, fade)
	if _current == &"":
		_player.stop()

func _fade_to(db: float, seconds: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", db, seconds)
	await _tween.finished
