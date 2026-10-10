 // BchTool: converts Pokémon X BCH files to DAE + PNG using SPICA (public domain).
//
//   BchTool info   <file.bch>...                    list models, materials, textures, animations
//   BchTool export <outDir> <name> <file.bch>... [--motions <motionpack>]
//       merge the files and write <name>.dae + textures. With --motions, also write each motion of
//       a GF motion pack (X/Y overworld characters, the 2nd file of an "MM" pack) as
//       <name>_motNN.dae: the skeleton plus one animation, no meshes.
//
//   BchTool parts <outDir> <base.bch> <part.bch>... [--textures <file.bch>...] [--motions <pack>]
//       character customization: every part is merged into the base skeleton once (so all share
//       one skeleton), then written as its own <partName>.dae. Also writes base.dae (skeleton
//       only), every color variant PNG of the parts, the motions, and manifest.json listing each
//       part's category, materials and color variants.
//
// For characters, pass the body ("base") first and then each clothing part: every part's meshes
// are moved into the first model, so the result is one model with one skeleton.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SPICA.Formats.CtrH3D;
using SPICA.Formats.CtrH3D.Animation;
using SPICA.Formats.CtrH3D.Model;
using SPICA.Formats.CtrH3D.Model.Material;
using SPICA.Formats.CtrH3D.Model.Mesh;
using SPICA.Formats.Generic.COLLADA;
using SPICA.Formats.GFL;
using SPICA.Formats.GFL.Motion;

static class Program
{
    static int Main(string[] args)
    {
        try
        {
            if (args.Length >= 2 && args[0] == "info") return Info(args.Skip(1));
            if (args.Length >= 4 && args[0] == "export") return Export(args[1], args[2], args.Skip(3).ToList());
            if (args.Length >= 3 && args[0] == "parts") return Parts(args[1], args.Skip(2).ToList());
            Console.Error.WriteLine("usage: BchTool info <file.bch>... | export <outDir> <name> <file.bch>... | parts <outDir> <base.bch> <part.bch>...");
            return 2;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("error: " + e);
            return 1;
        }
    }

    static int Info(IEnumerable<string> files)
    {
        foreach (string file in files)
        {
            H3D scene = H3D.Open(File.ReadAllBytes(file));
            Console.WriteLine($"{Path.GetFileName(file)}: {scene.Models.Count} model(s), {scene.Textures.Count} texture(s), {scene.SkeletalAnimations.Count} skeletal anim(s)");
            foreach (H3DModel m in scene.Models)
            {
                Console.WriteLine($"  model {m.Name}: {m.Meshes.Count} meshes, {m.Skeleton.Count} bones, {m.Materials.Count} materials");
                foreach (H3DMaterial mat in m.Materials)
                    Console.WriteLine($"    material {mat.Name}: {mat.Texture0Name} | {mat.Texture1Name} | {mat.Texture2Name}");
            }
            foreach (var t in scene.Textures) Console.WriteLine($"  texture {t.Name} {t.Width}x{t.Height} {t.Format}");
            foreach (var a in scene.SkeletalAnimations) Console.WriteLine($"  anim {a.Name} ({a.FramesCount} frames)");
        }
        return 0;
    }

    static int Export(string outDir, string name, List<string> files)
    {
        string motions = null;
        int flag = files.IndexOf("--motions");
        if (flag >= 0)
        {
            motions = files[flag + 1];
            files.RemoveRange(flag, 2);
        }

        H3D scene = H3D.Open(File.ReadAllBytes(files[0]));
        foreach (string file in files.Skip(1)) scene.Merge(H3D.Open(File.ReadAllBytes(file)));
        if (scene.Models.Count == 0) throw new Exception("no model in " + files[0]);

        H3DModel target = scene.Models[0];
        if (target.Name.EndsWith("_base") && scene.Models.Count > 1)
            target.ClearMeshes(); // character bodies hold a placeholder cube; the parts are the real meshes
        // In the order given: a bone shared by parts (e.g. "acchat", where accessories sit) gets its
        // parent from the first part that has it, so pass the hat before the glasses.
        while (scene.Models.Count > 1)
        {
            MergeInto(target, scene.Models[1]);
            scene.Models.Remove(scene.Models[1]);
        }
        SortSkeletonDepthFirst(target);
        int fixedMaterials = FixProjectionDummies(target);

        // Texture files can hold many color variants; only write the ones a material uses.
        var used = new HashSet<string>(target.Materials.SelectMany(m => new[] { m.Texture0Name, m.Texture1Name, m.Texture2Name })
            .Where(n => !string.IsNullOrEmpty(n)));
        int written = 0;
        Directory.CreateDirectory(outDir);
        new DAE(scene, 0).Save(Path.Combine(outDir, name + ".dae"));
        foreach (var t in scene.Textures)
        {
            if (!used.Contains(t.Name)) continue;
            t.ToBitmap().Save(Path.Combine(outDir, t.Name + ".png"), System.Drawing.Imaging.ImageFormat.Png);
            written++;
        }
        var missing = used.Where(n => !scene.Textures.Contains(n) && !n.StartsWith("projection_dummy")).ToList();

        Console.WriteLine($"{name}.dae: {target.Meshes.Count} meshes, {target.Skeleton.Count} bones, {written} textures, {fixedMaterials} material(s) re-pointed off projection_dummy");
        if (missing.Count > 0) Console.WriteLine("  textures not found: " + string.Join(", ", missing));

        if (motions != null) ExportMotions(scene, outDir, name, motions);
        return 0;
    }

    static int Parts(string outDir, List<string> args)
    {
        string motions = TakeOption(args, "--motions", 1).FirstOrDefault();
        List<string> textureFiles = TakeOption(args, "--textures", int.MaxValue);
        H3D scene = H3D.Open(File.ReadAllBytes(args[0]));
        H3DModel body = scene.Models[0];
        body.ClearMeshes(); // the body only holds a placeholder cube

        var partMeshes = new List<KeyValuePair<string, List<H3DMesh>>>();
        foreach (string file in args.Skip(1))
        {
            H3D partScene = H3D.Open(File.ReadAllBytes(file));
            foreach (H3DModel part in partScene.Models.ToList())
            {
                int before = body.Meshes.Count;
                MergeInto(body, part);
                partMeshes.Add(new KeyValuePair<string, List<H3DMesh>>(part.Name, body.Meshes.Skip(before).ToList()));
            }
        }
        foreach (string file in textureFiles)
            foreach (var t in H3D.Open(File.ReadAllBytes(file)).Textures)
                if (!scene.Textures.Contains(t.Name)) scene.Textures.Add(t);
        SortSkeletonDepthFirst(body);
        FixProjectionDummies(body);

        Directory.CreateDirectory(outDir);
        var manifest = new List<object>();
        var neededTextures = new HashSet<string>();
        foreach (var part in partMeshes)
        {
            body.ClearMeshes();
            body.AddMeshes(part.Value);
            new DAE(scene, 0).Save(Path.Combine(outDir, part.Key + ".dae"));

            var materials = part.Value.Select(m => body.Materials[m.MaterialIndex]).Distinct().Select(mat =>
            {
                string stem = VariantStem(mat.Texture0Name);
                string[] variants = ColorVariants(stem, scene);
                foreach (string v in variants) neededTextures.Add(stem + v);
                if (!string.IsNullOrEmpty(mat.Texture0Name)) neededTextures.Add(mat.Texture0Name);
                return new Dictionary<string, object>
                {
                    ["name"] = mat.Name, ["texture"] = mat.Texture0Name ?? "", ["stem"] = stem ?? "", ["variants"] = variants,
                };
            }).ToList();
            manifest.Add(new Dictionary<string, object> { ["name"] = part.Key, ["category"] = Category(part.Key), ["materials"] = materials });
        }

        body.ClearMeshes();
        new DAE(scene, 0).Save(Path.Combine(outDir, "base.dae"));
        // "_m" textures are skin masks: X/Y fills the masked areas with the chosen skin tone.
        foreach (string n in neededTextures.ToList()) neededTextures.Add(n + "_m");
        int written = 0;
        foreach (var t in scene.Textures)
        {
            if (!neededTextures.Contains(t.Name)) continue;
            t.ToBitmap().Save(Path.Combine(outDir, t.Name + ".png"), System.Drawing.Imaging.ImageFormat.Png);
            written++;
        }
        var doc = new Dictionary<string, object> { ["skeleton"] = body.Name, ["bones"] = body.Skeleton.Count, ["parts"] = manifest };
        File.WriteAllText(Path.Combine(outDir, "manifest.json"), new System.Web.Script.Serialization.JavaScriptSerializer().Serialize(doc));
        Console.WriteLine($"{partMeshes.Count} parts, {body.Skeleton.Count} bones, {written} textures → {outDir}");

        if (motions != null) ExportMotions(scene, outDir, "motion", motions);
        return 0;
    }

    /// Removes "--name value..." from args and returns the values. count = how many values to take
    /// (int.MaxValue: everything up to the next "--option").
    static List<string> TakeOption(List<string> args, string name, int count)
    {
        int i = args.IndexOf(name);
        if (i < 0) return new List<string>();
        var values = args.Skip(i + 1).TakeWhile(a => !a.StartsWith("--")).Take(count).ToList();
        args.RemoveRange(i, 1 + values.Count);
        return values;
    }

    /// "f2_tops_jersey" → "tops", "f2_face01" → "face", "f2_bngl01" → "bangle".
    /// Part names are <set>_<category>[NN][_<style>].
    static string Category(string partName)
    {
        string[] bits = partName.Split('_');
        string cat = bits.Length > 1 ? bits[1].TrimEnd("0123456789".ToCharArray()) : partName;
        return cat == "bngl" ? "bangle" : cat;
    }

    /// The part of a texture name shared by its color variants, or null if it has none.
    /// Clothing: "f2_topsjer_d01b01" → "f2_topsjer_" (siblings "…_d01b02", "…_d02co01").
    /// Girls' legs: "f1_socks_od01p01" → "f1_socks_" — the sock styles ("none", "kd01p01",
    /// "od01p03"...) are the variants. Faces and hair have none.
    static string VariantStem(string texture)
    {
        if (string.IsNullOrEmpty(texture)) return null;
        int socks = texture.IndexOf("_socks_");
        if (socks >= 0) return texture.Substring(0, socks + "_socks_".Length);
        var m = System.Text.RegularExpressions.Regex.Match(texture, @"^(.*_)d\d\d[a-z]*\d*$");
        return m.Success ? m.Groups[1].Value : null;
    }

    /// Variant codes for a stem: every texture starting with it, minus "_m" skin masks.
    static string[] ColorVariants(string stem, H3D scene)
    {
        if (stem == null) return new string[0];
        return scene.Textures.Select(t => t.Name)
            .Where(n => n.StartsWith(stem) && !n.EndsWith("_m") && n.Length > stem.Length)
            .Select(n => n.Substring(stem.Length)).OrderBy(n => n).ToArray();
    }

    static void ExportMotions(H3D scene, string outDir, string name, string motionPack)
    {
        H3DModel model = scene.Models[0];
        using (var input = new MemoryStream(File.ReadAllBytes(motionPack)))
        {
            foreach (GF1Motion mot in new GF1MotionPack(input))
            {
                H3DAnimation anim = mot.ToH3DSkeletalAnimation(model.Skeleton);
                anim.Name = $"mot{mot.Index:D2}";
                scene.SkeletalAnimations.Add(anim);
            }
        }

        model.ClearMeshes(); // motion files only need the skeleton
        for (int i = 0; i < scene.SkeletalAnimations.Count; i++)
        {
            H3DAnimation anim = scene.SkeletalAnimations[i];
            new DAE(scene, 0, i).Save(Path.Combine(outDir, $"{name}_{anim.Name}.dae"));
        }
        Console.WriteLine($"{scene.SkeletalAnimations.Count} motions → {name}_motNN.dae");
    }

    /// Moves the meshes and materials of part into target, remapping bone indices by bone name.
    static void MergeInto(H3DModel target, H3DModel part)
    {
        int materialOffset = target.Materials.Count;
        foreach (H3DMaterial mat in part.Materials)
        {
            if (target.Materials.Contains(mat.Name)) mat.Name = part.Name + "_" + mat.Name;
            target.Materials.Add(mat);
        }

        // Parts can bring bones the body lacks: hair strands, a hat's accessory bone, or an unused
        // extra root (e.g. "dressup_sample"). Bones a vertex uses are added to the body skeleton
        // under the same parent; unused ones are skipped.
        var usedBones = part.Meshes.SelectMany(m => m.SubMeshes)
            .SelectMany(sm => sm.BoneIndices.Take(sm.BoneIndicesCount)).Select(i => (int)i);
        HashSet<int> needed = WithAncestors(part, usedBones); // before any ParentIndex changes below
        var boneMap = new Dictionary<int, int>();
        for (int i = 0; i < part.Skeleton.Count; i++)
        {
            H3DBone bone = part.Skeleton[i];
            int j = target.Skeleton.Find(bone.Name);
            if (j < 0 && needed.Contains(i))
            {
                int parent = bone.ParentIndex >= 0 && boneMap.TryGetValue(bone.ParentIndex, out int p) ? p : 0;
                bone.ParentIndex = (short)Math.Max(parent, 0);
                target.Skeleton.Add(bone);
                j = target.Skeleton.Count - 1;
            }
            boneMap[i] = j;
        }

        foreach (H3DMesh mesh in part.Meshes.ToList())
        {
            mesh.MaterialIndex = (ushort)(mesh.MaterialIndex + materialOffset);
            foreach (var sm in mesh.SubMeshes)
                for (int k = 0; k < sm.BoneIndicesCount; k++)
                {
                    int mapped = boneMap[sm.BoneIndices[k]];
                    if (mapped < 0)
                    {
                        Console.WriteLine($"  warning: {part.Name} uses bone {part.Skeleton[sm.BoneIndices[k]].Name}, not in {target.Name}; using the root");
                        mapped = 0;
                    }
                    sm.BoneIndices[k] = (ushort)mapped;
                }
            mesh.NodeIndex = 0;
            target.AddMesh(mesh);
        }
    }

    /// Reorders bones so each comes right before its children (depth-first, siblings in original
    /// order). Godot numbers a DAE skeleton's bones in that order; vertex weights only line up with
    /// Godot's bones if the exported order is the same.
    static void SortSkeletonDepthFirst(H3DModel model)
    {
        var bones = model.Skeleton.ToList();
        var children = bones.Select(_ => new List<int>()).ToList();
        var roots = new List<int>();
        for (int i = 0; i < bones.Count; i++)
        {
            int p = bones[i].ParentIndex;
            if (p >= 0 && p < bones.Count && p != i) children[p].Add(i); else roots.Add(i);
        }

        var order = new List<int>();
        var stack = new Stack<int>(Enumerable.Reverse(roots));
        while (stack.Count > 0)
        {
            int b = stack.Pop();
            order.Add(b);
            for (int c = children[b].Count - 1; c >= 0; c--) stack.Push(children[b][c]);
        }
        if (order.SequenceEqual(Enumerable.Range(0, bones.Count))) return;

        var newIndex = new int[bones.Count];
        for (int n = 0; n < order.Count; n++) newIndex[order[n]] = n;

        model.Skeleton.Clear();
        foreach (int old in order)
        {
            H3DBone b = bones[old];
            b.ParentIndex = (short)(b.ParentIndex >= 0 && b.ParentIndex != old ? newIndex[b.ParentIndex] : -1);
            model.Skeleton.Add(b);
        }
        foreach (H3DMesh mesh in model.Meshes)
            foreach (var sm in mesh.SubMeshes)
                for (int k = 0; k < sm.BoneIndicesCount; k++)
                    sm.BoneIndices[k] = (ushort)newIndex[sm.BoneIndices[k]];
    }

    /// The given bones plus all their ancestors. Stops at a root (-1) or a bone pointing at itself.
    static HashSet<int> WithAncestors(H3DModel part, IEnumerable<int> bones)
    {
        var result = new HashSet<int>();
        foreach (int b in bones)
            for (int k = b; k >= 0 && k < part.Skeleton.Count && result.Add(k); k = part.Skeleton[k].ParentIndex) { }
        return result;
    }

    /// SPICA's DAE export only uses texture slot 0. Map materials often put a projection helper
    /// there and the real texture in slot 1 or 2.
    static int FixProjectionDummies(H3DModel model)
    {
        int count = 0;
        foreach (H3DMaterial mat in model.Materials)
        {
            if (mat.Texture0Name == null || !mat.Texture0Name.StartsWith("projection_dummy")) continue;
            string real = new[] { mat.Texture1Name, mat.Texture2Name }
                .FirstOrDefault(n => !string.IsNullOrEmpty(n) && !n.StartsWith("projection_dummy"));
            if (real == null) continue;
            mat.Texture0Name = real;
            count++;
        }
        return count;
    }
}
