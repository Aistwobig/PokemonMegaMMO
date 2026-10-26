// The 3DS (PICA200) material of every mesh, for the client's shader builder (client/scripts/pica_material.gd).
//
// X/Y models aren't drawn with plain textures: each material is a small program for the 3DS GPU —
// up to six texture-combiner stages mixing the three textures, the vertex color, constants and the
// result of per-pixel ("fragment") lighting, whose shading curves come from lookup tables (LUTs) in
// the model. The DAE export keeps none of this, so it's written next to it as <name>.pica.json, with
// each LUT as a 256×1 grey PNG (<name>_lut_<table>_<sampler>.png). Field names follow SPICA
// (SPICA.Rendering/Shaders/FragmentShaderGenerator.cs is the reference for what they mean).

using System;
using System.Collections;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using SPICA.Formats.CtrH3D;
using SPICA.Formats.CtrH3D.LUT;
using SPICA.Formats.CtrH3D.Model;
using SPICA.Formats.CtrH3D.Model.Material;
using SPICA.Math3D;

static class Pica
{
    public static void Write(H3D scene, H3DModel model, string outDir, string name)
    {
        var luts = new Dictionary<string, string>(); // "table/sampler" -> png file name
        var materials = new Dictionary<string, object>();
        // The vertex shader's switches (Game Freak's PokePack: bit 3 Phong, 4 rim, 5 inverse light,
        // 6 lighting) are per sub-mesh; gather them per material.
        var bools = new Dictionary<int, int>();
        foreach (var mesh in model.Meshes)
            foreach (var sm in mesh.SubMeshes)
                bools[mesh.MaterialIndex] = (bools.TryGetValue(mesh.MaterialIndex, out int b) ? b : 0) | sm.BoolUniforms;
        int matIndex = -1;
        foreach (H3DMaterial mat in model.Materials)
        {
            matIndex++;
            H3DMaterialParams p = mat.MaterialParams;
            var textures = new List<object>();
            string[] names = { mat.Texture0Name, mat.Texture1Name, mat.Texture2Name };
            for (int i = 0; i < 3; i++)
            {
                var t = p.TextureCoords[i].GetTransform();
                textures.Add(new Dictionary<string, object>
                {
                    ["name"] = names[i] ?? "",
                    ["map"] = p.TextureCoords[i].MappingType.ToString(),
                    ["m"] = new[] { t.M11, t.M12, t.M21, t.M22, t.M41, t.M42 },
                    ["wrapU"] = mat.TextureMappers[i].WrapU.ToString(),
                    ["wrapV"] = mat.TextureMappers[i].WrapV.ToString(),
                });
            }
            var stages = new List<object>();
            for (int i = 0; i < p.TexEnvStages.Length; i++)
            {
                var s = p.TexEnvStages[i];
                stages.Add(new Dictionary<string, object>
                {
                    ["srcC"] = s.Source.Color.Select(x => x.ToString()).ToArray(),
                    ["srcA"] = s.Source.Alpha.Select(x => x.ToString()).ToArray(),
                    ["opC"] = s.Operand.Color.Select(x => (int)x).ToArray(),
                    ["opA"] = s.Operand.Alpha.Select(x => (int)x).ToArray(),
                    ["combC"] = s.Combiner.Color.ToString(),
                    ["combA"] = s.Combiner.Alpha.ToString(),
                    ["scaleC"] = 1 << (int)s.Scale.Color,
                    ["scaleA"] = 1 << (int)s.Scale.Alpha,
                    ["passC"] = s.IsColorPassThrough,
                    ["passA"] = s.IsAlphaPassThrough,
                    ["updC"] = s.UpdateColorBuffer,
                    ["updA"] = s.UpdateAlphaBuffer,
                    ["const"] = p.GetConstantIndex(i),
                });
            }
            var lutRefs = new Dictionary<string, object>();
            foreach (var (key, table, sampler) in new[] {
                ("dist0", p.LUTDist0TableName, p.LUTDist0SamplerName), ("dist1", p.LUTDist1TableName, p.LUTDist1SamplerName),
                ("fresnel", p.LUTFresnelTableName, p.LUTFresnelSamplerName), ("reflecR", p.LUTReflecRTableName, p.LUTReflecRSamplerName),
                ("reflecG", p.LUTReflecGTableName, p.LUTReflecGSamplerName), ("reflecB", p.LUTReflecBTableName, p.LUTReflecBSamplerName) })
            {
                if (string.IsNullOrEmpty(table) || string.IsNullOrEmpty(sampler)) continue;
                string file = Lut(scene, table, sampler, outDir, name, luts);
                lutRefs[key] = file ?? ("missing:" + table + "/" + sampler);
            }
            materials[mat.Name] = new Dictionary<string, object>
            {
                ["textures"] = textures,
                ["texCoordConfig"] = p.TexCoordConfig.ToString(),
                ["stages"] = stages,
                ["buffer"] = Rgba(p.TexEnvBufferColor),
                ["emission"] = Rgba(p.EmissionColor), ["ambient"] = Rgba(p.AmbientColor), ["diffuse"] = Rgba(p.DiffuseColor),
                ["specular0"] = Rgba(p.Specular0Color), ["specular1"] = Rgba(p.Specular1Color),
                ["constants"] = new[] { p.Constant0Color, p.Constant1Color, p.Constant2Color, p.Constant3Color, p.Constant4Color, p.Constant5Color }.Select(Rgba).ToArray(),
                ["fragmentFlags"] = p.FragmentFlags.ToString(),
                ["bumpMode"] = p.BumpMode.ToString(),
                ["bumpTexture"] = (int)p.BumpTexture,
                ["fresnel"] = p.FresnelSelector.ToString(),
                ["lutInput"] = Fields(p.LUTInputSelection),
                ["lutScale"] = Fields(p.LUTInputScale),
                ["lutAbs"] = Fields(p.LUTInputAbsolute),
                ["luts"] = lutRefs,
                ["alphaTest"] = Fields(p.AlphaTest),
                ["blend"] = Fields(p.BlendFunction),
                ["colorOp"] = Fields(p.ColorOperation),
                ["depth"] = Fields(p.DepthColorMask),
                ["cull"] = p.FaceCulling.ToString(),
                ["translucency"] = p.TranslucencyKind.ToString(),
                ["shader"] = p.ShaderReference ?? "",
                ["vtxBools"] = bools.TryGetValue(matIndex, out int vb) ? vb : 0,
                ["vtxUniforms"] = p.VtxShaderUniforms.ToDictionary(kv => kv.Key.ToString(), kv => new[] { kv.Value.X, kv.Value.Y, kv.Value.Z, kv.Value.W }),
            };
        }
        File.WriteAllText(Path.Combine(outDir, name + ".pica.json"),
            new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(materials));
    }

    static string Lut(H3D scene, string table, string sampler, string outDir, string name, Dictionary<string, string> done)
    {
        string key = table + "/" + sampler;
        if (done.TryGetValue(key, out string file)) return file;
        H3DLUT lut = scene.LUTs.FirstOrDefault(l => l.Name == table);
        H3DLUTSampler s = lut?.Samplers.FirstOrDefault(x => x.Name == sampler);
        if (s == null) return null;
        file = $"{name}_lut_{Safe(table)}_{Safe(sampler)}.png";
        // The PICA indexes a LUT with a cosine. Laid out like SPICA's viewer (SPICA.Rendering/LUT.cs):
        // 512 entries covering [-1, 1], sampled at (x + 1) / 2. Signed tables store [0, 1) in entries
        // 0–127 and [-1, 0) in 128–255; absolute ones only cover [0, 1].
        var values = new float[512];
        bool absolute = (s.Flags & H3DLUTFlags.IsAbsolute) != 0;
        for (int i = 0; i < 256; i++)
        {
            if (absolute) { values[i + 256] = s.Table[i]; values[i] = s.Table[0]; }
            else if (i % 2 == 0)
            {
                int pos = i >> 1, neg = pos + 128;
                values[i + 256] = values[i + 257] = s.Table[pos];
                values[i] = values[i + 1] = s.Table[neg];
            }
        }
        using (var bmp = new Bitmap(512, 1, PixelFormat.Format32bppArgb))
        {
            for (int i = 0; i < 512; i++)
            {
                int v = Math.Max(0, Math.Min(255, (int)Math.Round(values[i] * 255)));
                bmp.SetPixel(i, 0, Color.FromArgb(255, v, v, v));
            }
            bmp.Save(Path.Combine(outDir, file), ImageFormat.Png);
        }
        done[key] = file;
        return file;
    }

    static string Safe(string s) => new string(s.Select(c => char.IsLetterOrDigit(c) ? c : '_').ToArray());

    static int[] Rgba(RGBA c) => new int[] { c.R, c.G, c.B, c.A };

    /// Public fields and properties of a settings struct, enums as their names.
    static Dictionary<string, object> Fields(object o)
    {
        var d = new Dictionary<string, object>();
        if (o == null) return d;
        foreach (var f in o.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance))
            d[f.Name] = Value(f.GetValue(o));
        foreach (var pr in o.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
            if (pr.GetIndexParameters().Length == 0 && pr.CanRead)
                try { d[pr.Name] = Value(pr.GetValue(o)); } catch (Exception) { }
        return d;
    }

    static object Value(object v)
    {
        if (v == null) return null;
        if (v is Enum) return v.ToString();
        if (v is RGBA c) return Rgba(c);
        if (v is bool || v is float || v is double || v is int || v is uint || v is byte || v is sbyte || v is short || v is ushort) return v;
        return v.ToString();
    }

    /// BchTool pica <file.bch>...: prints the materials' settings (debugging).
    public static int Dump(IEnumerable<string> files)
    {
        H3D scene = null;
        foreach (string f in files)
        {
            var s = H3D.Open(File.ReadAllBytes(f));
            if (scene == null) scene = s; else scene.Merge(s);
        }
        string dir = Path.Combine(Path.GetTempPath(), "bchtool-pica");
        Directory.CreateDirectory(dir);
        Console.WriteLine($"LUT tables in the files: {string.Join(", ", scene.LUTs.Select(l => l.Name + "(" + string.Join("/", l.Samplers.Select(x => x.Name)) + ")"))}");
        Write(scene, scene.Models[0], dir, "dump");
        Console.WriteLine(File.ReadAllText(Path.Combine(dir, "dump.pica.json")));
        return 0;
    }
}

/// Per-motion extras of a Pokémon's battle animation pack (a/0/0/7, the "PB" entry): next to the bone
/// motions (file 0), file 2 + slot is the motion's visibility animation (which meshes show: open/closed
/// eyes, mouth shapes) and file 20 + slot its texture animation (eyes and mouth sliding across their
/// expression atlas). Written as <name>.motions.json:
///   { "<slot>": { "frames": n, "uv": { "<material>/<coord>": [[m41, m42] per frame] },
///                 "vis": { "<mesh>": [true/false per frame] } } }
/// The uv values are the texture matrix's translation (M41, M42), computed like the material's own.
static class PicaMotions
{
    public static void Write(H3D model, List<byte[]> pack, string outDir, string name)
    {
        var mats = model.Models[0].Materials;
        var outp = new Dictionary<string, object>();
        for (int slot = 0; slot < 18; slot++)
        {
            var entry = new Dictionary<string, object>();
            var uv = new Dictionary<string, object>();
            var vis = new Dictionary<string, object>();
            int frames = 0;
            H3D matScene = Open(pack, 20 + slot), visScene = Open(pack, 2 + slot);
            foreach (var anim in matScene?.MaterialAnimations ?? new SPICA.Formats.CtrH3D.H3DDict<SPICA.Formats.CtrH3D.Animation.H3DMaterialAnim>())
            {
                frames = Math.Max(frames, (int)anim.FramesCount);
                foreach (var el in anim.Elements)
                {
                    string t = el.TargetType.ToString();
                    if (!t.StartsWith("MaterialTexCoord") || !t.EndsWith("Trans")) continue;
                    int coord = t[16] - '0';
                    var mat = mats.FirstOrDefault(m => m.Name == el.Name);
                    if (mat == null || !(el.Content is SPICA.Formats.CtrH3D.Animation.H3DAnimVector2D v)) continue;
                    var tc = mat.MaterialParams.TextureCoords[coord];
                    var values = new List<float[]>();
                    for (int f = 0; f <= anim.FramesCount; f++)
                    {
                        var c = tc;
                        c.Translation = new System.Numerics.Vector2(
                            v.X.Exists ? v.X.GetFrameValue(f) : tc.Translation.X,
                            v.Y.Exists ? v.Y.GetFrameValue(f) : tc.Translation.Y);
                        var m = c.GetTransform();
                        values.Add(new[] { m.M41, m.M42 });
                    }
                    uv[el.Name + "/" + coord] = values;
                }
            }
            foreach (var anim in visScene?.VisibilityAnimations ?? new SPICA.Formats.CtrH3D.H3DDict<SPICA.Formats.CtrH3D.Animation.H3DAnimation>())
            {
                frames = Math.Max(frames, (int)anim.FramesCount);
                foreach (var el in anim.Elements)
                {
                    if (!(el.Content is SPICA.Formats.CtrH3D.Animation.H3DAnimBoolean b)) continue;
                    var values = new List<bool>();
                    for (int f = 0; f <= anim.FramesCount; f++) values.Add(b.GetFrameValue(f));
                    vis[el.Name] = values;
                }
            }
            if (uv.Count == 0 && vis.Count == 0) continue;
            entry["frames"] = frames;
            entry["uv"] = uv;
            entry["vis"] = vis;
            outp[slot.ToString()] = entry;
        }
        File.WriteAllText(Path.Combine(outDir, name + ".motions.json"),
            new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(outp));
    }

    static H3D Open(List<byte[]> pack, int i)
    {
        if (i >= pack.Count || pack[i].Length < 4 || pack[i][0] != 'B' || pack[i][1] != 'C' || pack[i][2] != 'H') return null;
        try { return H3D.Open(pack[i]); } catch (Exception) { return null; }
    }
}

/// Cutscene cameras: X/Y keeps them in CGFX files (a/1/6/5 next to each scene's models), one camera
/// and one camera animation each. Written as <out>.camera.json with the value of every frame (30 fps):
///   { "name", "view": "Aim"|"LookAt"|"Rotate", "frames": n,
///     "pos": [[x,y,z]...], "target": [[x,y,z]...], "up": [[x,y,z]...], "rot": [[x,y,z]...] (radians),
///     "twist": [..], "fovy": [..] (radians) }   — only the arrays the view type uses.
static class CutsceneCamera
{
    public static void Write(string cgfx, string outPath)
    {
        var g = SPICA.Formats.CtrGfx.Gfx.Open(cgfx);
        var cam = g.Cameras[0];
        var anim = g.CameraAnimations.Count > 0 ? g.CameraAnimations[0].ToH3DAnimation() : null;
        int frames = anim != null ? (int)anim.FramesCount : 0;
        var el = new Dictionary<string, object>();
        if (anim != null) foreach (var e in anim.Elements) el[e.Name] = e.Content;
        float At(SPICA.Formats.CtrH3D.Animation.H3DFloatKeyFrameGroup k, int f, float rest) => k != null && k.Exists ? k.GetFrameValue(f) : rest;

        var pos = new List<float[]>(); var target = new List<float[]>(); var up = new List<float[]>(); var rot = new List<float[]>();
        var twist = new List<float>(); var fovy = new List<float>();
        string view = cam.ViewType.ToString();
        var aim = cam.View as SPICA.Formats.CtrGfx.Camera.GfxCameraViewAim;
        var look = cam.View as SPICA.Formats.CtrGfx.Camera.GfxCameraViewLookAt;
        var persp = cam.Projection as SPICA.Formats.CtrGfx.Camera.GfxCameraProjectionPerspective;
        // The rotate view's angles aren't public in SPICA; read them by reflection.
        var rotField = cam.View?.GetType().GetField("Rotation", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        var restRot = rotField != null ? (System.Numerics.Vector3)rotField.GetValue(cam.View) : System.Numerics.Vector3.Zero;
        for (int f = 0; f <= frames; f++)
        {
            var t = el.TryGetValue("Transform", out object tc) ? tc as SPICA.Formats.CtrH3D.Animation.H3DAnimTransform : null;
            pos.Add(new[] { At(t?.TranslationX, f, cam.TransformTranslation.X), At(t?.TranslationY, f, cam.TransformTranslation.Y), At(t?.TranslationZ, f, cam.TransformTranslation.Z) });
            var target0 = aim != null ? aim.Target : look != null ? look.Target : System.Numerics.Vector3.Zero;
            var tv = el.TryGetValue("ViewUpdater.TargetPosition", out object tp) ? tp as SPICA.Formats.CtrH3D.Animation.H3DAnimVector3D : null;
            target.Add(new[] { At(tv?.X, f, target0.X), At(tv?.Y, f, target0.Y), At(tv?.Z, f, target0.Z) });
            var up0 = look != null ? look.UpVector : System.Numerics.Vector3.UnitY;
            var uv = el.TryGetValue("ViewUpdater.UpwardVector", out object uvc) ? uvc as SPICA.Formats.CtrH3D.Animation.H3DAnimVector3D : null;
            up.Add(new[] { At(uv?.X, f, up0.X), At(uv?.Y, f, up0.Y), At(uv?.Z, f, up0.Z) });
            var rv = el.TryGetValue("ViewUpdater.ViewRotate", out object rvc) ? rvc as SPICA.Formats.CtrH3D.Animation.H3DAnimVector3D : null;
            rot.Add(new[] { At(rv?.X, f, restRot.X), At(rv?.Y, f, restRot.Y), At(rv?.Z, f, restRot.Z) });
            var tw = el.TryGetValue("ViewUpdater.Twist", out object twc) ? twc as SPICA.Formats.CtrH3D.Animation.H3DAnimFloat : null;
            twist.Add(At(tw?.Value, f, aim?.Twist ?? 0));
            var fv = el.TryGetValue("ProjectionUpdater.Fovy", out object fvc) ? fvc as SPICA.Formats.CtrH3D.Animation.H3DAnimFloat : null;
            fovy.Add(At(fv?.Value, f, persp?.FOVY ?? 0.8f));
        }
        var doc = new Dictionary<string, object> { ["name"] = cam.Name, ["view"] = view, ["frames"] = frames, ["pos"] = pos, ["fovy"] = fovy };
        if (view == "Aim") { doc["target"] = target; doc["twist"] = twist; }
        else if (view == "LookAt") { doc["target"] = target; doc["up"] = up; }
        else doc["rot"] = rot;
        File.WriteAllText(outPath, new System.Web.Script.Serialization.JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(doc));
    }
}
