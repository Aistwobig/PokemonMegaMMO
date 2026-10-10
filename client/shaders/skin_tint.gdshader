// Trainer clothing with bare skin: X/Y marks skin areas in a "_m" mask texture and tints them with
// the chosen skin tone. Everything outside the mask keeps the clothing color.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask_tex : filter_linear;
uniform vec3 tone : source_color = vec3(1.0);
uniform float alpha_scissor = 0.5;

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < alpha_scissor) {
		discard;
	}
	float skin = texture(mask_tex, UV).a;
	ALBEDO = c.rgb * mix(vec3(1.0), tone, skin);
}
