extends Node
## Autoload (Singleton).
## Guarda los datos del jugador mientras la app está abierta, para que
## cualquier escena (login, sala, tablero) pueda leerlos sin pasarlos a mano.
##
## Se llenan por primera vez justo después del login con Google
## (ver ApiClient.mock_login), y luego al crear/unirse a una sala.

var player_id: String = ""
var nombre: String = ""
var token: String = ""

var room_code: String = ""
var es_host: bool = false

func limpiar_sala() -> void:
	room_code = ""
	es_host = false

func tiene_sesion() -> bool:
	return player_id != ""
