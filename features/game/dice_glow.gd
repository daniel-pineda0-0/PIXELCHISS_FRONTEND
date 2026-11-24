class_name DiceGlow
extends Control
## Resalte del panel de dados cuando te toca lanzar: marco dorado pulsante y el letrero «¡LANZA!».
## Va como hijo del panel grande de dados (se estira con él) y no intercepta clics.

const GOLD := Color(1.0, 0.85, 0.25)

var _pulse := 0.0
var _label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.text = "¡LANZA!"
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", GOLD)
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.position.y = -4.0
	add_child(_label)
	visible = false
	set_process(false)

func set_on(on: bool) -> void:
	if on == visible:
		return
	visible = on
	set_process(on)
	if not on:
		_pulse = 0.0

func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()

func _draw() -> void:
	var k := 0.5 + 0.5 * sin(_pulse * 6.0)
	for i in 3:                                   # halo exterior que respira
		var grow := 2.0 + float(i) * 2.5 + k * 3.0
		draw_rect(Rect2(Vector2(-grow, -grow), size + Vector2(grow, grow) * 2.0),
				Color(GOLD.r, GOLD.g, GOLD.b, (0.28 - 0.08 * float(i)) * (0.6 + 0.4 * k)), false, 2.0)
	draw_rect(Rect2(Vector2(-1, -1), size + Vector2(2, 2)),
			Color(1.0, 0.95, 0.6, 0.75 + 0.25 * k), false, 2.0)
