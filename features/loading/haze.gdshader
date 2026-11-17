shader_type canvas_item;
// Calor que ondula el paisaje: cada fila de 3 px se corre un poco a los lados,
// mas abajo (cerca de la lava) que arriba (cielo).

uniform float strength = 1.6;   // desplazamiento maximo, en pixeles de la textura
uniform float speed = 0.6;

void fragment() {
	float row = floor(UV.y * 120.0);
	float wave = sin(row * 0.55 + TIME * speed * 2.0) + 0.6 * sin(row * 0.23 - TIME * speed * 1.3);
	float amp = strength * (0.25 + 0.75 * smoothstep(0.30, 0.85, UV.y));
	vec2 uv = vec2(clamp(UV.x + wave * amp * TEXTURE_PIXEL_SIZE.x, 0.0, 1.0), UV.y);
	COLOR = texture(TEXTURE, uv);
}
