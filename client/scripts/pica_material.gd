class_name PicaMaterial
## Recreates an X/Y (3DS PICA200) material as a Godot shader, so models look like they do in the game.
## The importer writes each model's materials to <model>.pica.json (importer/BchTool/Pica.cs): the
## texture-combiner stages, the per-pixel ("fragment") lighting with its lookup tables (LUTs), bump
## mapping, constants and the alpha test. This builds the matching shader, following SPICA's own
## generator (SPICA.Rendering/Shaders/FragmentShaderGenerator.cs). Shaders are cached by their code.
##
## Lighting: one directional light fixed to the camera (above and a little to the left), with the
## SPICA viewer's light colors; the 3DS works in view space too, so models light the same from any
## angle, as in the game. Math is done on the stored (sRGB) values like the 3DS and converted at the end.

const LIGHT_DIR := Vector3(-0.25, 0.45, 1.0) # view space, towards the light
const LIGHT_AMBIENT := Color(0.1, 0.1, 0.1)
const LIGHT_DIFFUSE := Color(0.9, 0.9, 0.9)
const LIGHT_SPECULAR0 := Color(0.8, 0.8, 0.8)
const LIGHT_SPECULAR1 := Color(0.4, 0.4, 0.4)
const CHAR_AMBIENT := Color(0.55, 0.55, 0.55)
const CHAR_DIFFUSE := Color(0.5, 0.5, 0.5)

static var _shaders := {} # code -> Shader
static var _infos := {} # json path -> Dictionary
static var _luts := {} # path -> Texture2D

const LUT_KEYS := ["dist0", "dist1", "fresnel", "reflecR", "reflecG", "reflecB"]
const LUT_INPUT_NAMES := ["Dist0", "Dist1", "Fresnel", "ReflecR", "ReflecG", "ReflecB"]
const SCALES := {"One": 1.0, "Two": 2.0, "Four": 4.0, "Eight": 8.0, "Quarter": 0.25, "Half": 0.5}


## A model's materials (material name -> settings), or {} for older asset caches without the file.
static func load_info(folder: String, model: String) -> Dictionary:
	var path := folder.path_join(model + ".pica.json")
	if not _infos.has(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_infos[path] = data if data is Dictionary else {}
	return _infos[path]


## The game's material for one surface. `textures` maps texture names to textures (the DAE's own,
## or recolored ones for character parts); missing ones fall back to files in `folder`.
static func build(info: Dictionary, folder: String, textures := {}) -> ShaderMaterial:
	var code := _shader_code(info)
	if not _shaders.has(code):
		var sh := Shader.new()
		sh.code = code
		_shaders[code] = sh
	var m := ShaderMaterial.new()
	m.shader = _shaders[code]
	var tex_infos: Array = info.get("textures", [])
	for i in 3:
		var tname: String = tex_infos[i].name if i < tex_infos.size() else ""
		var tex: Texture2D = textures.get(tname)
		if tex == null and tname != "":
			tex = _load_texture(folder.path_join(tname + ".png"))
		if tex:
			m.set_shader_parameter("tex%d" % i, tex)
		elif tname != "":
			m.set_shader_parameter("tex%d" % i, _black()) # missing highlight maps: no highlight, not white
	var luts: Dictionary = info.get("luts", {})
	for i in LUT_KEYS.size():
		var file: String = luts.get(LUT_KEYS[i], "")
		if file != "" and not file.begins_with("missing:"):
			var lut := _load_lut(folder.path_join(file))
			if lut:
				m.set_shader_parameter("lut%d" % i, lut)
	return m


static var _black_tex: Texture2D

static func _black() -> Texture2D:
	if _black_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
		_black_tex = ImageTexture.create_from_image(img)
	return _black_tex


## LUTs are read straight from the PNG: the import's compression would blur the shading curves.
static func _load_lut(path: String) -> Texture2D:
	if not _luts.has(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else null
		_luts[path] = ImageTexture.create_from_image(img) if img else null
	return _luts[path]


static func _load_texture(path: String) -> Texture2D:
	if _luts.has(path):
		return _luts[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			tex = ImageTexture.create_from_image(img)
	_luts[path] = tex
	return tex


static func _shader_code(info: Dictionary) -> String:
	var flags: String = info.get("fragmentFlags", "")
	var stages: Array = info.get("stages", [])
	var tex_infos: Array = info.get("textures", [])
	var consts: Array = info.get("constants", [])
	var used_tex := [false, false, false]
	var need_light := false
	for s: Dictionary in stages:
		for src: String in s.srcC + s.srcA:
			if src.begins_with("Texture"):
				used_tex[int(src.substr(7))] = true
			if src.begins_with("Fragment"):
				need_light = true
	var bump: String = info.get("bumpMode", "NotUsed")
	var bump_tex := int(info.get("bumpTexture", 0))
	if need_light and bump in ["AsBump", "AsTangent"]:
		used_tex[bump_tex] = true

	var c := PackedStringArray()
	var cull: String = info.get("cull", "BackFace")
	c.append("shader_type spatial;")
	var blend: Dictionary = info.get("blend", {})
	var dst := str(blend.get("ColorDstFunc", "Zero"))
	var mode := ""
	if dst == "One":
		mode = ", blend_add, depth_draw_never" # glows, light shafts
	elif dst == "OneMinusSourceAlpha":
		mode = ", blend_mix, depth_draw_%s" % ("always" if info.get("depth", {}).get("DepthWrite", true) else "never")
	c.append("render_mode unshaded, %s%s;" % [("cull_back" if cull == "BackFace" else "cull_front" if cull == "FrontFace" else "cull_disabled"), mode])
	for i in 3:
		var repeat := "repeat_enable" if true else ""
		c.append("uniform sampler2D tex%d : filter_linear_mipmap, %s;" % [i, repeat])
	for i in 6:
		c.append("uniform sampler2D lut%d : filter_linear, repeat_disable;" % i)
	c.append("uniform vec4 tint : source_color = vec4(1.0);") # hair color, skin tone (character parts)
	c.append("uniform vec2 uv_shift = vec2(0.0);")
	c.append("uniform float mouth_split = -1.0;")
	c.append("")
	c.append("float wrapc(float x, int mode) { if (mode == 1) { float m = mod(x, 2.0); return m > 1.0 ? 2.0 - m : m; } if (mode == 2) return clamp(x, 0.0, 1.0); return fract(x); }")
	c.append("vec3 to_linear(vec3 s) { return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), s)); }")
	c.append("float lut(sampler2D t, float x, float s) { return min(texture(t, vec2((x + 1.0) * 0.5, 0.5)).r * s, 1.0); }")
	c.append("vec3 vrot(vec3 v) { return v; }")
	c.append("")
	c.append("void fragment() {")
	c.append("\tvec2 uv3 = vec2(UV.x, 1.0 - UV.y);")
	for i in 3:
		if not used_tex[i]:
			continue
		var t: Dictionary = tex_infos[i] if i < tex_infos.size() else {}
		var m: Array = t.get("m", [1, 0, 0, 1, 0, 0])
		c.append("\tvec2 t%d = vec2(uv3.x * %s + uv3.y * %s + %s, uv3.x * %s + uv3.y * %s + %s);" % [i, _f(m[0]), _f(m[2]), _f(m[4]), _f(m[1]), _f(m[3]), _f(m[5])])
		if str(t.get("name", "")).contains("face"):
			# another cell of the expression sheet, below `mouth_split` only (LipSync: an open mouth
			# under the same eyes)
			c.append("\tif (UV.y > mouth_split) t%d += uv_shift;" % i)
		c.append("\tt%d = vec2(wrapc(t%d.x, %d), wrapc(t%d.y, %d));" % [i, i, _wrap(t.get("wrapU", "")), i, _wrap(t.get("wrapV", ""))])
		c.append("\tvec4 Color%d = texture(tex%d, vec2(t%d.x, 1.0 - t%d.y));" % [i, i, i, i])
	if _is_gf(info):
		_gf_primary(c, info)
	else:
		c.append("\tvec4 Prim = COLOR;")
	c.append("\tvec4 Output = vec4(0.0); vec4 Previous = vec4(0.0);")
	c.append("\tvec4 CombBuffer = %s;" % _vec4(info.get("buffer", [0, 0, 0, 255])))
	for i in 6:
		c.append("\tvec4 Const%d = %s;" % [i, _vec4(consts[i] if i < consts.size() else [0, 0, 0, 0])])
	if need_light:
		_lighting(c, info, flags, bump, bump_tex)
	for i in stages.size():
		var s: Dictionary = stages[i]
		var k := "Const%d" % int(s.get("const", 0))
		var ca := PackedStringArray()
		var aa := PackedStringArray()
		for p in 3:
			ca.append(_color_arg(_src(s.srcC[p], k), int(s.opC[p])))
			aa.append(_alpha_arg(_src(s.srcA[p], k), int(s.opA[p])))
		if not s.passC:
			c.append("\tOutput.rgb = %s;" % _combine(s.combC, ca, true))
		if not s.passA:
			c.append("\tOutput.a = %s;" % _combine(s.combA, aa, false))
		if int(s.scaleC) != 1:
			c.append("\tOutput.rgb = min(Output.rgb * %s, vec3(1.0));" % _f(s.scaleC))
		if int(s.scaleA) != 1:
			c.append("\tOutput.a = min(Output.a * %s, 1.0);" % _f(s.scaleA))
		if s.updC:
			c.append("\tCombBuffer.rgb = Previous.rgb;")
		if s.updA:
			c.append("\tCombBuffer.a = Previous.a;")
		if i < 5 and not (s.passC and s.passA):
			c.append("\tPrevious = Output;")
	var at: Dictionary = info.get("alphaTest", {})
	if at.get("Enabled", false):
		var ref := _f(float(at.get("Reference", 0)) / 255.0)
		match str(at.get("Function", "Always")):
			"Never": c.append("\tdiscard;")
			"Equal": c.append("\tif (Output.a != %s) discard;" % ref)
			"Notequal": c.append("\tif (Output.a == %s) discard;" % ref)
			"Less": c.append("\tif (Output.a >= %s) discard;" % ref)
			"Lequal": c.append("\tif (Output.a > %s) discard;" % ref)
			"Greater": c.append("\tif (Output.a <= %s) discard;" % ref)
			"Gequal": c.append("\tif (Output.a < %s) discard;" % ref)
	c.append("\tALBEDO = to_linear(clamp(Output.rgb, 0.0, 1.0)) * tint.rgb;")
	if dst in ["One", "OneMinusSourceAlpha"]:
		c.append("\tALPHA = clamp(Output.a, 0.0, 1.0);")
	c.append("}")
	return "\n".join(c)


## Game Freak's own vertex shaders (Pokémon "PokePack"): Primary Color isn't the vertex color but
## per-vertex lighting: x = 1, y = inverse (back) light, z = Phong highlight, w = rim light, each
## switched by the mesh's vertex-shader bools and scaled by LightPowScale (register 22).
static func _is_gf(info: Dictionary) -> bool:
	return str(info.get("shader", "")).contains("Poke")


static func _gf_primary(c: PackedStringArray, info: Dictionary) -> void:
	var bools := int(info.get("vtxBools", 0))
	var lps: Array = info.get("vtxUniforms", {}).get("22", [1, 1, 1, 1])
	if not bools & (1 << 6):
		c.append("\tvec4 Prim = vec4(1.0);")
		return
	c.append("\tvec3 pn = normalize(NORMAL);")
	c.append("\tvec3 pl = normalize(vec3(%s, %s, %s));" % [_f(LIGHT_DIR.x), _f(LIGHT_DIR.y), _f(LIGHT_DIR.z)])
	c.append("\tvec4 Prim = vec4(1.0, 0.0, 0.0, 0.0);")
	if bools & (1 << 5):
		c.append("\tPrim.y = max(dot(pn, -pl), 0.0) * (0.5 + 0.5 * max(-pl.z, 0.0));")
	if bools & (1 << 3):
		c.append("\tPrim.z = clamp(dot(pn, normalize(pl + vec3(0.0, 0.0, 1.0))), 0.0, 1.0) * %s;" % _f(float(lps[2]) * float(lps[3])))
	if bools & (1 << 4):
		c.append("\tPrim.w = (1.0 - clamp(pn.z, 0.0, 1.0)) * %s;" % _f(float(lps[0]) * float(lps[1])))
	c.append("\tPrim = clamp(Prim, 0.0, 1.0);")


## Per-pixel lighting (FragPriColor = diffuse, FragSecColor = specular), one directional light.
static func _lighting(c: PackedStringArray, info: Dictionary, flags: String, bump: String, bump_tex: int) -> void:
	var sel: Dictionary = info.get("lutInput", {})
	var sc: Dictionary = info.get("lutScale", {})
	var luts: Dictionary = info.get("luts", {})
	c.append("\tvec4 MatAmbient = %s; vec4 MatDiffuse = %s; vec4 MatSpec0 = %s; vec4 MatSpec1 = %s;" % [
		_vec4(info.get("ambient", [0, 0, 0, 0])), _vec4(info.get("diffuse", [0, 0, 0, 0])),
		_vec4(info.get("specular0", [0, 0, 0, 0])), _vec4(info.get("specular1", [0, 0, 0, 0]))])
	c.append("\tvec4 FragPriColor = vec4((%s + MatAmbient * 0.0).rgb, 1.0);" % _vec4(info.get("emission", [0, 0, 0, 0])))
	c.append("\tvec4 FragSecColor = vec4(0.0, 0.0, 0.0, 1.0);")
	var surf := "vec3(0.0, 0.0, 1.0)"
	if bump == "AsBump":
		surf = "Color%d.xyz * 2.0 - 1.0" % bump_tex
	c.append("\tvec3 SurfNormal = %s;" % surf)
	if bump == "AsBump" and flags.contains("IsBumpRenormalizeEnabled"):
		c.append("\tSurfNormal.z = sqrt(max(1.0 - dot(SurfNormal.xy, SurfNormal.xy), 0.0));")
	c.append("\tvec3 N = normalize(NORMAL);")
	c.append("\tvec3 Tangent = normalize(TANGENT);")
	c.append("\tvec3 Light = normalize(vec3(%s, %s, %s));" % [_f(LIGHT_DIR.x), _f(LIGHT_DIR.y), _f(LIGHT_DIR.z)])
	if _is_gf(info):
		# Game Freak's shaders: the bump map holds model-space normals, and the vertex shader passes the
		# light direction where the view vector goes, so every term compares the surface with the light.
		if bump == "AsBump":
			c.append("\tvec3 Normal = normalize(mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * SurfNormal);")
		else:
			c.append("\tvec3 Normal = N;")
		c.append("\tvec3 V = Light;")
	else:
		c.append("\tvec3 Normal = normalize(TANGENT * SurfNormal.x + BINORMAL * SurfNormal.y + N * SurfNormal.z);")
		c.append("\tvec3 V = normalize(VIEW);")
	c.append("\tvec3 Half = normalize(V + Light);")
	c.append("\tfloat CosNormalHalf = dot(Normal, Half);")
	c.append("\tfloat CosViewHalf = dot(V, Half);")
	c.append("\tfloat CosNormalView = dot(Normal, V);")
	c.append("\tfloat CosLightNormal = dot(Light, Normal);")
	c.append("\tfloat CosLightSpot = dot(Light, -Light);")
	c.append("\tfloat CosPhi = dot(Half - Normal / dot(Normal, Normal) * dot(Normal, Half), Tangent);")
	c.append("\tfloat ln = abs(CosLightNormal);") # the viewer's light is two-sided
	var spec0 := "MatSpec0"
	var spec1 := "MatSpec1"
	var clamp_hl := ""
	if flags.contains("IsClampHighLightEnabled"):
		clamp_hl = " * fi"
		c.append("\tfloat fi = CosLightNormal < 0.0 ? 0.0 : 1.0;")
	if flags.contains("IsLUTDist0Enabled"):
		spec0 += " * d0"
		c.append("\tfloat d0 = %s;" % _lut_input(sel, sc, luts, 0))
	if flags.contains("IsLUTReflectionEnabled"):
		spec1 = "r"
		c.append("\tvec4 r = vec4(%s, %s, %s, 1.0);" % [_lut_input(sel, sc, luts, 3), _lut_input(sel, sc, luts, 4), _lut_input(sel, sc, luts, 5)])
	if flags.contains("IsLUTDist1Enabled"):
		spec1 += " * d1"
		c.append("\tfloat d1 = %s;" % _lut_input(sel, sc, luts, 1))
	if flags.contains("IsLUTGeoFactor0Enabled") or flags.contains("IsLUTGeoFactor1Enabled"):
		c.append("\tfloat g = ln / abs(dot(Half, Half));")
		if flags.contains("IsLUTGeoFactor0Enabled"):
			spec0 += " * g"
		if flags.contains("IsLUTGeoFactor1Enabled"):
			spec1 += " * g"
	# Field characters (the player, NPCs) stand in the towns' bright ambient light; the toon table then
	# draws the shadow side. The viewer's dim ambient leaves them grey.
	var field_char := str(info.get("shader", "")).contains("FieldChar")
	var amb := CHAR_AMBIENT if field_char else LIGHT_AMBIENT
	var dif := CHAR_DIFFUSE if field_char else LIGHT_DIFFUSE
	c.append("\tvec4 Diffuse = MatAmbient * %s + MatDiffuse * %s * clamp(ln, 0.0, 1.0);" % [_vec4c(amb), _vec4c(dif)])
	c.append("\tvec4 Specular = %s * %s + %s * %s;" % [spec0, _vec4c(LIGHT_SPECULAR0), spec1, _vec4c(LIGHT_SPECULAR1)])
	c.append("\tFragPriColor.rgb += Diffuse.rgb;")
	c.append("\tFragSecColor.rgb += Specular.rgb%s;" % clamp_hl)
	var fres: String = info.get("fresnel", "No")
	if fres.contains("Pri"):
		c.append("\tFragPriColor.a = %s;" % _lut_input(sel, sc, luts, 2))
	if fres.contains("Sec"):
		c.append("\tFragSecColor.a = %s;" % _lut_input(sel, sc, luts, 2))
	c.append("\tFragPriColor = clamp(FragPriColor, 0.0, 1.0);")
	c.append("\tFragSecColor = clamp(FragSecColor, 0.0, 1.0);")


static func _lut_input(sel: Dictionary, sc: Dictionary, luts: Dictionary, i: int) -> String:
	var name: String = LUT_INPUT_NAMES[i]
	if str(luts.get(LUT_KEYS[i], "")) == "" or str(luts.get(LUT_KEYS[i], "")).begins_with("missing:"):
		return "1.0" # no table: the PICA reads 1
	var input: String = sel.get(name, "CosNormalHalf")
	return "lut(lut%d, %s, %s)" % [i, input, _f(SCALES.get(str(sc.get(name, "One")), 1.0))]


static func _src(name: String, k: String) -> String:
	match name:
		"PrimaryColor": return "Prim"
		"FragmentPrimaryColor": return "FragPriColor"
		"FragmentSecondaryColor": return "FragSecColor"
		"Texture0": return "Color0"
		"Texture1": return "Color1"
		"Texture2": return "Color2"
		"PreviousBuffer": return "CombBuffer"
		"Constant": return k
		"Previous": return "Previous"
	return "Prim"


static func _color_arg(src: String, op: int) -> String:
	var a := src
	match op & ~1:
		2: a = "%s.aaaa" % src
		4: a = "%s.rrrr" % src
		8: a = "%s.gggg" % src
		12: a = "%s.bbbb" % src
	if op & 1:
		a = "(vec4(1.0) - %s)" % a
	return a


static func _alpha_arg(src: String, op: int) -> String:
	var a: String = "%s.%s" % [src, ["a", "r", "g", "b"][(op & ~1) >> 1]]
	if op & 1:
		a = "(1.0 - %s)" % a
	return a


static func _combine(mode: String, a: PackedStringArray, color: bool) -> String:
	var x := ".rgb" if color else ""
	var one := "vec3(1.0)" if color else "1.0"
	var zero := "vec3(0.0)" if color else "0.0"
	var p0 := "(%s)%s" % [a[0], x]
	var p1 := "(%s)%s" % [a[1], x]
	var p2 := "(%s)%s" % [a[2], x]
	match mode:
		"Replace": return p0
		"Modulate": return "%s * %s" % [p0, p1]
		"Add": return "min(%s + %s, %s)" % [p0, p1, one]
		"AddSigned": return "clamp(%s + %s - 0.5, %s, %s)" % [p0, p1, zero, one]
		"Interpolate": return "mix(%s, %s, %s)" % [p1, p0, p2]
		"Subtract": return "max(%s - %s, %s)" % [p0, p1, zero]
		"DotProduct3Rgb":
			return "vec3(min(dot((%s).rgb, (%s).rgb), 1.0))" % [a[0], a[1]] if color else "min(dot(vec3(%s), vec3(%s)), 1.0)" % [a[0], a[1]]
		"DotProduct3Rgba":
			return "vec3(min(dot(%s, %s), 1.0))" % [a[0], a[1]] if color else "min(dot(vec4(%s), vec4(%s)), 1.0)" % [a[0], a[1]]
		"MultAdd": return "min(%s * %s + %s, %s)" % [p0, p1, p2, one]
		"AddMult": return "min(%s + %s, %s) * %s" % [p0, p1, one, p2]
	return p0


static func _wrap(mode: String) -> int:
	if mode == "Mirror":
		return 1
	if mode.begins_with("Clamp"):
		return 2
	return 0


static func _vec4(rgba: Array) -> String:
	return "vec4(%s, %s, %s, %s)" % [_f(rgba[0] / 255.0), _f(rgba[1] / 255.0), _f(rgba[2] / 255.0), _f(rgba[3] / 255.0)]


static func _vec4c(col: Color) -> String:
	return "vec4(%s, %s, %s, 1.0)" % [_f(col.r), _f(col.g), _f(col.b)]


static func _f(v: Variant) -> String:
	var s := "%.6f" % float(v)
	return s
