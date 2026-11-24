shader_type canvas_item;
// Lleva el sprite de una ficha en casa a la paleta de su fondo, para que no se vea pegado encima:
// menos saturacion, luz ambiente de la zona, negros que suben hacia el color de sombra del fondo
// y blancos topados (el craneo no destaca mas que la ilustracion). Mantiene el alfa y el modulate.
uniform vec4 ambient : source_color = vec4(1.0);
uniform vec4 shadow_tint : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.75;
uniform float sat : hint_range(0.0, 1.5) = 0.82;
uniform float lift : hint_range(0.0, 1.0) = 0.35;
uniform float cap : hint_range(0.3, 1.0) = 0.8;

void fragment() {
	vec4 col = COLOR;
	float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 c = mix(vec3(l), col.rgb, sat);
	c *= mix(vec3(1.0), ambient.rgb, amount);
	c = mix(c, shadow_tint.rgb, lift * (1.0 - smoothstep(0.0, 0.7, l)));
	float peak = max(c.r, max(c.g, c.b));
	if (peak > cap) {
		c *= cap / peak;
	}
	COLOR = vec4(c, col.a);
}
