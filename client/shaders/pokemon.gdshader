shader_type spatial;
// X/Y model materials: the UV transform and wrap modes the DAE export drops (written by BchTool to
// <model>.materials.json). Pokémon textures are often half a body, scaled 2x and mirrored.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// [M11, M12, M21, M22] and [M41, M42]: u' = u*M11 + v*M21 + M41, v' = u*M12 + v*M22 + M42, in 3DS UV
// space (v up; Godot's is v down).
uniform vec4 uv_m = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 uv_t = vec2(0.0);
uniform bool mirror_u = false;
uniform bool mirror_v = false;
uniform bool clamp_u = false;
uniform bool clamp_v = false;

float wrap(float x, bool mirror, bool clamp_it) {
	if (clamp_it) return clamp(x, 0.0, 1.0);
	if (mirror) {
		float m = mod(x, 2.0);
		return m > 1.0 ? 2.0 - m : m;
	}
	return fract(x);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 t = vec2(uv.x * uv_m.x + uv.y * uv_m.z + uv_t.x, uv.x * uv_m.y + uv.y * uv_m.w + uv_t.y);
	t = vec2(wrap(t.x, mirror_u, clamp_u), wrap(t.y, mirror_v, clamp_v));
	vec4 c = texture(albedo_tex, vec2(t.x, 1.0 - t.y));
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.8;
}
