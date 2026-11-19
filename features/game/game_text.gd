class_name GameText
extends RefCounted
## Textos y utilidades de la partida que comparten varias pantallas (Fase 4):
## catálogo de cartas, efectos, motivos de descarte, nombres de jugador y el
## botón de opciones. Solo datos de presentación: las reglas las decide el servidor.

const JOIN_BUTTON := preload("res://features/lobby/join_button.tscn")

const SEAT_NAMES := ["Rojo", "Azul", "Verde", "Amarillo"]

## Catálogo actual de cartas (guía §7.5). Cuando el servidor manda `name` y
## `description` (estado `card`), se usan esos; esta tabla cubre los eventos que
## solo traen `cardId` (EFFECT_APPLIED, CARD_DISCARDED).
const CARDS := {
	"kill-next": {
		"name": "Matar al más cercano", "buff": true,
		"desc": "Captura la ficha rival más cercana. Ignora las zonas seguras.",
	},
	"kill-chosen": {
		"name": "Matar a tu elección", "buff": true,
		"desc": "Elige una casilla del recorrido con fichas rivales y captúralas. Ignora las zonas seguras.",
	},
	"advance-safe": {
		"name": "Avanzar a zona segura", "buff": true,
		"desc": "Lleva una ficha tuya al siguiente seguro de su ruta que tenga cupo.",
	},
	"skip-turn": {
		"name": "Turno perdido", "buff": false,
		"desc": "Pierdes tu próximo turno.",
	},
	"instant-death": {
		"name": "Muerte súbita", "buff": false,
		"desc": "Tu ficha más adelantada vuelve a casa.",
	},
	"doubles-death": {
		"name": "Castigo de pares", "buff": false,
		"desc": "Penalización al sacar pares: una de tus fichas vuelve a casa.",
	},
}

const DEBUFF_EFFECTS := ["SKIP_NEXT_TURN", "LOSE_LEADING_PIECE", "DOUBLES_PENALTY", "DICE_MAX_LIMIT"]

## Etiqueta corta para la tarjeta del jugador (`players[].effects`).
const EFFECT_TAGS := {
	"SKIP_NEXT_TURN": "-TURNO",
	"DOUBLES_PENALTY": "-PARES",
	"DICE_MAX_LIMIT": "DADO-",
	"CHOOSE_DICE": "DADOS+",
}

const EFFECT_NAMES := {
	"SKIP_NEXT_TURN": "Pierde su próximo turno",
	"DOUBLES_PENALTY": "Castigo de pares",
	"DICE_MAX_LIMIT": "Dado limitado",
	"CHOOSE_DICE": "Elige sus dados",
}

const DISCARD_TEXT := {
	"NO_LEGAL_TARGET": "La carta no tiene efecto: no hay objetivo válido",
	"TIMEOUT": "Se acabó el tiempo: la carta se descartó",
	"EMPTY_CATALOG": "No hay cartas disponibles",
	"CATALOG_UNAVAILABLE": "No se pudo obtener la carta",
}

static func card_name(card_id: String, fallback := "Carta") -> String:
	return str(CARDS[card_id].name) if CARDS.has(card_id) else fallback

static func card_desc(card_id: String) -> String:
	return str(CARDS[card_id].desc) if CARDS.has(card_id) else ""

## true = buff. Una carta que no está en la tabla se clasifica por su efecto.
static func card_is_buff(card_id: String, effect_code := "") -> bool:
	if CARDS.has(card_id):
		return bool(CARDS[card_id].buff)
	return effect_code not in DEBUFF_EFFECTS

static func discard_text(reason: String) -> String:
	return str(DISCARD_TEXT.get(reason, "La carta se descartó"))

static func effect_name(code: String) -> String:
	return str(EFFECT_NAMES.get(code, code))

## Texto de las etiquetas de efecto de un jugador: "-TURNO -PARES". "" si no tiene.
static func effects_tags(effects: Array) -> String:
	var tags := PackedStringArray()
	for e in effects:
		if e is Dictionary:
			tags.append(str(EFFECT_TAGS.get(str(e.get("code", "")), str(e.get("code", "")))))
	return " ".join(tags)

## Texto largo (tooltip) de los efectos de un jugador.
static func effects_tooltip(effects: Array) -> String:
	var lines := PackedStringArray()
	for e in effects:
		if not (e is Dictionary):
			continue
		var line := effect_name(str(e.get("code", "")))
		var turns := int(e.get("remainingTurns", 0))
		if turns > 0:
			line += " (%d)" % turns
		lines.append(line)
	return "\n".join(lines)

# --- Nombres ---------------------------------------------------------------------------

## Game solo conoce ids; los nombres vienen de la sala (Lobby.data) si aún está.
static func player_name(pid: String) -> String:
	for entry in Lobby.data.get("players", []):
		if str(entry.get("user_id", "")) == pid:
			var shown := str(entry.get("display_name", ""))
			if shown != "":
				return shown
	var seat := int(GameNet.player(pid).get("seat", -1))
	if seat >= 0 and seat < SEAT_NAMES.size():
		return SEAT_NAMES[seat]
	return "Jugador"

static func short_name(full_name: String) -> String:
	return full_name if full_name.length() <= 10 else full_name.substr(0, 10)

## "tú" si es el jugador local, si no su nombre corto.
static func who(pid: String) -> String:
	return "tú" if pid == GameNet.me else short_name(player_name(pid))

## Texto de un valor que puede venir null del JSON ("" si es null).
static func s(value: Variant) -> String:
	return "" if value == null else str(value)

## Segundos que quedan hasta un `deadline` (Unix ms del servidor); -1 si no hay.
## Solo se muestra: el servidor decide cuándo vence.
static func seconds_until(deadline_ms: Variant) -> int:
	var deadline := float(deadline_ms) if deadline_ms != null else 0.0
	if deadline <= 0.0:
		return -1
	return maxi(0, ceili((deadline - Time.get_unix_time_from_system() * 1000.0) / 1000.0))

# --- Botón de opciones -----------------------------------------------------------------

## Botón del juego (join_button) estirado a `min_size`, con el texto en varias líneas.
## Se usa en las respuestas de la trivia y en las opciones de carta.
static func make_button(text: String, min_size: Vector2) -> TextureButton:
	var button := JOIN_BUTTON.instantiate() as TextureButton
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	var label := button.get_node("Label") as Label
	label.text = text
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 3.0
	label.offset_top = 2.0
	label.offset_right = -3.0
	label.offset_bottom = -2.0
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button
