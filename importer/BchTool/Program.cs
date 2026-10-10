// BchTool: converts Pokémon X BCH files to DAE + PNG using SPICA (public domain).
//
//   BchTool info   <file.bch>...                    list models, materials, textures, animations
//   BchTool export <outDir> <name> <file.bch>... [--motions <motionpack>]
//       merge the files and write <name>.dae + textures. With --motions, also write each motion of
//       a GF motion pack (X/Y overworld characters, the 2nd file of an "MM" pack) as
//       <name>_motNN.dae: the skeleton plus one animation, no meshes.
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
            Console.Error.WriteLine("usage: BchTool info <file.bch>... | export <outDir> <name> <file.bch>...");
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
