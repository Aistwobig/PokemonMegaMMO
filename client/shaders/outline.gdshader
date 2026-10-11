shader_type spatial;
// X/Y's black outline around characters and Pokémon: an inverted hull drawn as a second pass. The
// back faces are pushed out along the normal by a fixed number of pixels (in clip space), so the
// line keeps its thickness at any distance or model scale.
render_mode unshaded, cull_front, shadows_disabled;

uniform float width_px = 1.6;
uniform vec4 color : source_color = vec4(0.05, 0.05, 0.08, 1.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(dir) > 0.0001) {
		clip.xy += normalize(dir) * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
}
