class_name HomeCrowd
extends Node2D
## Las 4 fichas en casa de un asiento, dibujadas en el fondo de su zona (reemplaza a la antigua "losa"
## con las fichas encima). Hay un HomeSlot por ficha (la n usa el hueco n) y solo se ven los de las
## fichas que de verdad estan en casa: al salir una desaparece su hueco, al volver (captura) reaparece.
## Es hijo de strip_signs, asi que se mueve con su chunk y usa las mismas coordenadas locales que el suelo.

## Plataforma bajo las fichas (si el asiento la tiene): y de la esquina superior respecto al centro del grupo.
const PLATFORM_TOP: Dictionary = {0: -26.0, 1: -17.0, 2: -28.0}

var seat := 0
var ground: Node2D
var slots: Array[HomeSlot] = []

func _ready() -> void:
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var origin: Vector2 = ground.map_to_local(Vector2i(-1, 3))
	var pp := "res://service/assets/game/home/platform_%d.png" % seat
	if PLATFORM_TOP.has(seat) and ResourceLoader.exists(pp):
		var tex: Texture2D = load(pp)
		var plat := Sprite2D.new()
		plat.texture = tex
		plat.centered = false
		plat.offset = Vector2(-tex.get_width() * 0.5, PLATFORM_TOP[seat])
		plat.position = origin + BoardMap.HOME_CENTER[seat] + Vector2(-3.0, 0.0)
		add_child(plat)
	var order: Array[int] = [0, 1, 2, 3]
	order.sort_custom(func(a: int, b: int) -> bool:
		return BoardMap.home_offset(seat, a).y < BoardMap.home_offset(seat, b).y)
	var by_number := {}
	for n in order:                       # de atras hacia delante: los mas bajos tapan a los de detras
		var slot := HomeSlot.new()
		slot.setup(seat)
		slot.position = origin + BoardMap.home_offset(seat, n)
		add_child(slot)
		by_number[n] = slot
	for n in 4:
		slots.append(by_number[n])

func is_present(number: int) -> bool:
	return slots[posmod(number, slots.size())].is_present()

## La ficha `number` llega a casa (present) o sale de ella.
func set_present(number: int, present: bool, instant := false) -> void:
	var slot := slots[posmod(number, slots.size())]
	if present:
		slot.show_home(instant)
	else:
		slot.hide_home()
