extends Control
## Tarjeta de un mapa votable (US-012). Solo pinta; la sala decide qué hacer
## cuando el jugador la selecciona (vista previa) o vota.

signal selected(map_id: String)
signal vote_pressed(map_id: String)

# La imagen del minimapa la pone el cliente según el id del mapa (ver GET /api/lobbies/maps).
const MINIMAPS := {
	"classic": preload("res://service/assets/ui/icons/ph_map_card_minimap_1.png"),
	"science": preload("res://service/assets/ui/icons/ph_map_card_minimap_2.png"),
}
const VOTED_COLOR := Color(0.6, 1.0, 0.6)
const DIMMED_COLOR := Color(0.75, 0.75, 0.75)

@onready var panel: PanelContainer = $PanelContainer
@onready var count_label: Label = %CountLabel
@onready var mini_map: TextureRect = %MiniMap
@onready var vote_button: TextureButton = %VoteButton

var map_id := ""

func _ready() -> void:
	panel.mouse_entered.connect(func(): selected.emit(map_id))
	panel.gui_input.connect(_on_panel_gui_input)
	vote_button.pressed.connect(_on_vote_button_pressed)

func setup(map: Dictionary) -> void:
	map_id = map.id
	mini_map.texture = MINIMAPS.get(map_id, MINIMAPS["classic"])

func set_votes(count: int) -> void:
	count_label.text = "%02d" % count

## El botón de votar se tiñe de verde en el mapa por el que ya votó el jugador.
func set_voted(voted: bool) -> void:
	vote_button.self_modulate = VOTED_COLOR if voted else Color.WHITE

func set_selected(is_selected: bool) -> void:
	modulate = Color.WHITE if is_selected else DIMMED_COLOR

func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		selected.emit(map_id)

func _on_vote_button_pressed() -> void:
	selected.emit(map_id)
	vote_pressed.emit(map_id)
