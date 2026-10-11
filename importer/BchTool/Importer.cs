// BchTool import <romfs> <assetCache> [--work <dir>]
//
// Builds the client's whole asset cache from a decrypted Pokémon X RomFS in one go: the overworld
// (Vaniville to Route 2), the player's house, the player's clothing parts, story characters,
// trainers, Pokémon, tall grass and the game text. It does what the Python tools in importer/tools
// do (GARC archives, LZ11, GF packs, text, tile grids), so players only need this one program.
// Every step is listed in Steps(); importer/README.md explains where the data comes from.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

static class Importer
{
    static string romfs, cache, work;
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

    public static int Run(List<string> args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        string workArg = TakeOption(args, "--work");
        if (args.Count < 2)
        {
            Console.Error.WriteLine("usage: BchTool import <romfs folder> <client asset-cache folder> [--work <temp folder>]");
            return 2;
        }
        romfs = args[0];
        cache = args[1];
        work = workArg ?? Path.Combine(Path.GetTempPath(), "PokemonMegaMMO-import");
        if (!File.Exists(R("a/0/0/7")))
        {
            Console.Error.WriteLine($"error: {romfs} doesn't look like a Pokémon X RomFS (no a/0/0/7).");
            Console.Error.WriteLine("It should be the folder that contains the 'a' folder, dumped from your own cartridge and decrypted.");
            return 1;
        }
        Directory.CreateDirectory(cache);
        Directory.CreateDirectory(work);
        var steps = Steps();
        for (int i = 0; i < steps.Count; i++)
        {
            Console.WriteLine($"[{i + 1}/{steps.Count}] {steps[i].Key}");
            steps[i].Value();
        }
        Console.WriteLine("Done. Asset cache: " + Path.GetFullPath(cache));
        return 0;
    }

    static List<KeyValuePair<string, Action>> Steps()
    {
        var s = new List<KeyValuePair<string, Action>>();
        Action<string, Action> add = (name, a) => s.Add(new KeyValuePair<string, Action>(name, a));
        add("Game text", Text);
        add("Overworld: Vaniville Town to Route 2", Overworld);
        add("The player's house", House);
        add("Title screen town and Garchomp", Phase0);
        add("Player clothing (girl)", () => PlayerParts("f1", 8, Range(9, 63).Except(new[] { 52, 53 }).Concat(new[] { 7 }), Range(65, 396), 1));
        add("Player clothing (boy)", () => PlayerParts("f2", 398, Range(399, 432).Except(new[] { 425, 426 }).Concat(new[] { 397 }), Range(433, 630), 2));
        add("Story characters and trainers", Characters);
        add("Tall grass", Grass);
        add("Pokémon", Pokemon);
        return s;
    }

    // --- steps ------------------------------------------------------------------------------------

    static void Text()
    {
        foreach (var (garc, folder) in new[] { ("a/0/7/4", "game"), ("a/0/8/2", "story") })
        {
            var g = new Garc(R(garc));
            string dir = Path.Combine(cache, "text", folder);
            Directory.CreateDirectory(dir);
            for (int i = 0; i < g.Count; i++)
            {
                List<string> lines;
                try { lines = TextFile.Decode(g.Get(i)); }
                catch (Exception) { continue; }
                File.WriteAllText(Path.Combine(dir, i + ".json"), Json.Serialize(lines), new UTF8Encoding(false));
            }
        }
    }

    /// map01: every chunk of map matrix 0 with area 2's textures, plus its tile grid.
    static void Overworld()
    {
        var ad = Pack(Garcs("a/0/1/3").Get(2), "ad2");
        var grs = Garcs("a/0/4/1");
        byte[] matrix = PackFiles(Garcs("a/0/4/2").Get(0))[0];
        int w = BitConverter.ToUInt16(matrix, 4), h = BitConverter.ToUInt16(matrix, 6);
        string outDir = Path.Combine(cache, "maps", "map01");
        for (int cy = 0; cy < h; cy++)
            for (int cx = 0; cx < w; cx++)
            {
                int gr = BitConverter.ToUInt16(matrix, 8 + 2 * (cy * w + cx));
                if (gr == 0xFFFF) continue;
                var files = Pack(grs.Get(gr), "gr" + gr);
                string name = $"map01_{cx:D2}_{cy:D2}";
                Program.Export(outDir, name, new List<string> { files[1], ad[11], ad[1] });
                WriteTiles(files[0], Path.Combine(outDir, name + ".tiles.json"));
            }
    }

    static void House()
    {
        var ad74 = Pack(Garcs("a/0/1/3").Get(74), "ad74");
        var ad118 = Pack(Garcs("a/0/1/3").Get(118), "ad118");
        var grs = Garcs("a/0/4/1");
        string outDir = Path.Combine(cache, "maps", "t01r01");
        foreach (var (gr, name, tex) in new[] {
            (162, "house_1f", new[] { ad118[11], ad118[1], ad74[11], ad74[1] }),
            (163, "bedroom_f1", new[] { ad74[11], ad74[1] }),
            (168, "bedroom_f2", new[] { ad74[11], ad74[1] }) })
        {
            var files = Pack(grs.Get(gr), "gr" + gr);
            Program.Export(outDir, name, new List<string> { files[1] }.Concat(tex).ToList());
            WriteTiles(files[0], Path.Combine(outDir, name + ".tiles.json"));
        }
    }

    /// The login screen's background scene (scenes/phase0.tscn) uses Vaniville and a Garchomp.
    static void Phase0()
    {
        var ad = Pack(Garcs("a/0/1/3").Get(2), "ad2");
        var grs = Garcs("a/0/4/1");
        string dir = Path.Combine(cache, "phase0", "vaniville");
        Program.Export(dir, "vaniville_north", new List<string> { Pack(grs.Get(12), "gr12")[1], ad[11], ad[1] });
        Program.Export(dir, "vaniville_south", new List<string> { Pack(grs.Get(14), "gr14")[1], ad[11], ad[1] });
        ExportPokemon(445, "garchomp", Path.Combine(cache, "phase0"));
    }

    /// Clothing parts from a/0/8/8 on one skeleton, with the overworld motions (a/0/2/1 pack 1/2).
    static void PlayerParts(string gender, int baseEntry, IEnumerable<int> parts, IEnumerable<int> textures, int motionPack)
    {
        var g = Garcs("a/0/8/8");
        string dir = Path.Combine(work, "a088");
        Directory.CreateDirectory(dir);
        Func<int, string> file = i =>
        {
            string p = Path.Combine(dir, $"{i:D5}.bch");
            if (!File.Exists(p)) File.WriteAllBytes(p, g.Get(i));
            return p;
        };
        // A few entries in these ranges aren't BCH files (e.g. 390–396, 626–628): skip them.
        Func<int, bool> isBch = i => { var d = g.Get(i); return d.Length > 3 && d[0] == 'B' && d[1] == 'C' && d[2] == 'H'; };
        var args = new List<string> { file(baseEntry) };
        args.AddRange(parts.Where(isBch).Select(file));
        args.Add("--textures");
        args.AddRange(textures.Where(isBch).Select(file));
        args.Add("--motions");
        args.Add(Pack(Garcs("a/0/2/1").Get(motionPack), "mm" + motionPack)[1]);
        Program.Parts(Path.Combine(cache, "trainers", gender), args);
    }

    /// Overworld characters (a/0/2/1 entry → name): friends, the professor, Mom, trainers, Rhyhorn.
    static void Characters()
    {
        var g = Garcs("a/0/2/1");
        var list = new (int entry, string name)[] {
            (3, "tr0003"), (4, "tr0004"), (5, "tr0005"), (6, "tr0006"), (7, "tr0007"),
            (67, "tr0100"), (71, "tr0104"), (257, "pm0111"),
        };
        foreach (var (entry, name) in list)
        {
            var files = Pack(g.Get(entry), "chr" + entry);
            Program.Export(Path.Combine(cache, "npc", name), name, new List<string> { files[0], "--motions", files[1] });
        }
    }

    static void Grass()
    {
        var files = Pack(Garcs("a/2/3/0").Get(0), "grass");
        Program.Export(Path.Combine(cache, "npc", "grass00"), "grass00", new List<string> { files[7], files[8] });
    }

    static readonly (int dex, string id)[] PokemonList = {
        (650, "chespin"), (651, "quilladin"), (652, "chesnaught"), (653, "fennekin"), (654, "braixen"),
        (655, "delphox"), (656, "froakie"), (657, "frogadier"), (658, "greninja"), (661, "fletchling"),
        (662, "fletchinder"), (663, "talonflame"), (659, "bunnelby"), (660, "diggersby"), (664, "scatterbug"),
        (665, "spewpa"), (666, "vivillon"), (263, "zigzagoon"), (264, "linoone"), (25, "pikachu"), (26, "raichu"),
        (16, "pidgey"), (17, "pidgeotto"), (10, "caterpie"), (11, "metapod"), (13, "weedle"), (14, "kakuna"),
    };

    static void Pokemon()
    {
        foreach (var (dex, id) in PokemonList) ExportPokemon(dex, id, Path.Combine(cache, "pokemon"));
    }

    /// a/0/0/7: entry 0 indexes models (u16 model per species); each form has 8 entries from
    /// 4 + 8 × model: 0 model, 2 textures, 5 animations (file 0 = battle motion pack).
    static void ExportPokemon(int dex, string id, string outRoot)
    {
        var g = Garcs("a/0/0/7");
        int model = BitConverter.ToUInt16(g.Get(0), (dex - 1) * 4);
        int b = 4 + 8 * model;
        string Save(int k, string what)
        {
            string p = Path.Combine(work, $"pm{dex}_{what}.bin");
            File.WriteAllBytes(p, PackFiles(g.Get(b + k))[0]);
            return p;
        }
        Program.Export(Path.Combine(outRoot, id), id, new List<string> { Save(0, "model"), Save(2, "tex"), "--motions", Save(5, "anim") });
    }

    // --- helpers ----------------------------------------------------------------------------------

    static string R(string garc) => Path.Combine(romfs, garc.Replace('/', Path.DirectorySeparatorChar));

    static readonly Dictionary<string, Garc> garcs = new Dictionary<string, Garc>();
    static Garc Garcs(string path)
    {
        if (!garcs.ContainsKey(path)) garcs[path] = new Garc(R(path));
        return garcs[path];
    }

    static IEnumerable<int> Range(int from, int to) => Enumerable.Range(from, to - from + 1);

    /// The files of a GF pack ("PC", "GR", "AD", "MM", ...): 2-char magic, u16 count, u32 offsets.
    public static List<byte[]> PackFiles(byte[] d)
    {
        int count = BitConverter.ToUInt16(d, 2);
        var files = new List<byte[]>();
        for (int i = 0; i < count; i++)
        {
            int start = BitConverter.ToInt32(d, 4 + 4 * i), end = BitConverter.ToInt32(d, 8 + 4 * i);
            files.Add(d.Skip(start).Take(end - start).ToArray());
        }
        return files;
    }

    /// Writes a pack's files to the work folder and returns their paths (by index).
    static List<string> Pack(byte[] data, string name)
    {
        string dir = Path.Combine(work, name);
        Directory.CreateDirectory(dir);
        var paths = new List<string>();
        var files = PackFiles(data);
        for (int i = 0; i < files.Count; i++)
        {
            string p = Path.Combine(dir, $"{i}.bin");
            File.WriteAllBytes(p, files[i]);
            paths.Add(p);
        }
        return paths;
    }

    /// The tile grid (u16 width, u16 height, u32 per tile) as {width, height, tiles}.
    static void WriteTiles(string gridFile, string outPath)
    {
        byte[] d = File.ReadAllBytes(gridFile);
        int w = BitConverter.ToUInt16(d, 0), h = BitConverter.ToUInt16(d, 2);
        var tiles = new uint[w * h];
        for (int i = 0; i < tiles.Length; i++) tiles[i] = BitConverter.ToUInt32(d, 4 + 4 * i);
        File.WriteAllText(outPath, Json.Serialize(new Dictionary<string, object> { ["width"] = w, ["height"] = h, ["tiles"] = tiles }));
    }

    static string TakeOption(List<string> args, string name)
    {
        int i = args.IndexOf(name);
        if (i < 0 || i + 1 >= args.Count) return null;
        string v = args[i + 1];
        args.RemoveRange(i, 2);
        return v;
    }
}

/// A GARC archive (the RomFS's container format), entries LZ11-decompressed on read.
class Garc
{
    readonly byte[] buf;
    readonly List<(int start, int end)> entries = new List<(int, int)>();

    public Garc(string path)
    {
        buf = File.ReadAllBytes(path);
        if (Encoding.ASCII.GetString(buf, 0, 4) != "CRAG") throw new Exception(path + " is not a GARC");
        int dataOff = BitConverter.ToInt32(buf, 0x10);
        int fatoSize = BitConverter.ToInt32(buf, 0x20);
        int count = BitConverter.ToUInt16(buf, 0x24);
        int pos = 0x1C + fatoSize + 12; // BTAF header
        for (int i = 0; i < count; i++)
        {
            uint bits = BitConverter.ToUInt32(buf, pos);
            pos += 4;
            bool first = true;
            for (int b = 0; b < 32; b++)
            {
                if ((bits >> b & 1) == 0) continue;
                int s = BitConverter.ToInt32(buf, pos), e = BitConverter.ToInt32(buf, pos + 4);
                pos += 12;
                if (first) entries.Add((dataOff + s, dataOff + e)); // only the first sub-entry is used
                first = false;
            }
            if (first) entries.Add((0, 0));
        }
    }

    public int Count => entries.Count;

    public byte[] Get(int i)
    {
        var (s, e) = entries[i];
        var raw = new byte[e - s];
        Array.Copy(buf, s, raw, 0, raw.Length);
        if (raw.Length > 4 && raw[0] == 0x11)
        {
            try { return Lz11.Decompress(raw); } catch (Exception) { }
        }
        return raw;
    }
}

static class Lz11
{
    public static byte[] Decompress(byte[] src)
    {
        int size = src[1] | src[2] << 8 | src[3] << 16;
        int pos = 4;
        if (size == 0) { size = BitConverter.ToInt32(src, 4); pos = 8; }
        var o = new byte[size];
        int n = 0;
        while (n < size)
        {
            int flags = src[pos++];
            for (int bit = 7; bit >= 0 && n < size; bit--)
            {
                if ((flags >> bit & 1) == 0) { o[n++] = src[pos++]; continue; }
                int b0 = src[pos], ind = b0 >> 4, length, disp;
                if (ind == 0)
                {
                    length = ((b0 & 0xF) << 4 | src[pos + 1] >> 4) + 0x11;
                    disp = ((src[pos + 1] & 0xF) << 8 | src[pos + 2]) + 1;
                    pos += 3;
                }
                else if (ind == 1)
                {
                    length = ((b0 & 0xF) << 12 | src[pos + 1] << 4 | src[pos + 2] >> 4) + 0x111;
                    disp = ((src[pos + 2] & 0xF) << 8 | src[pos + 3]) + 1;
                    pos += 4;
                }
                else
                {
                    length = ind + 1;
                    disp = ((b0 & 0xF) << 8 | src[pos + 1]) + 1;
                    pos += 2;
                }
                for (int k = 0; k < length && n < size; k++, n++) o[n] = o[n - disp];
            }
        }
        return o;
    }
}

/// Gen 6 text files: per-line XOR key stream; variables kept as [VAR XXXX(args)] (see text.py).
static class TextFile
{
    public static List<string> Decode(byte[] d)
    {
        int sections = BitConverter.ToUInt16(d, 0), count = BitConverter.ToUInt16(d, 2);
        int sdo = BitConverter.ToInt32(d, 12);
        if (sections != 1) throw new Exception("not a text file");
        var lines = new List<string>();
        int key = 0x7C89;
        for (int i = 0; i < count; i++)
        {
            int entry = sdo + 4 + i * 8;
            int off = BitConverter.ToInt32(d, entry) + sdo;
            int length = BitConverter.ToUInt16(d, entry + 4);
            var chars = new int[length];
            int k = key;
            for (int j = 0; j < length; j++)
            {
                chars[j] = BitConverter.ToUInt16(d, off + j * 2) ^ k;
                k = ((k << 3) | (k >> 13)) & 0xFFFF;
            }
            lines.Add(Render(chars));
            key = (key + 0x2983) & 0xFFFF;
        }
        return lines;
    }

    static string Render(int[] c)
    {
        var o = new StringBuilder();
        for (int i = 0; i < c.Length;)
        {
            int ch = c[i++];
            if (ch == 0) break;
            if (ch == 0x10)
            {
                int n = c[i], code = c[i + 1];
                var args = c.Skip(i + 2).Take(n - 1).ToArray();
                i += 1 + n;
                if (code == 0xBE00) o.Append("\\r");
                else if (code == 0xBE01) o.Append("\\c");
                else if (code == 0xBE02) o.Append($"[WAIT {(args.Length > 0 ? args[0] : 0)}]");
                else o.Append($"[VAR {code:X4}{(args.Length > 0 ? "(" + string.Join(",", args.Select(a => a.ToString("X4"))) + ")" : "")}]");
            }
            else if (ch == 0xE000) o.Append("\\n");
            else if (ch == 0x25BC) o.Append("\\r");
            else if (ch == 0x25BD) o.Append("\\c");
            else if (ch == 0xE07F) o.Append(' ');
            else if (ch == 0xE08D) o.Append('…');
            else if (ch == 0xE08E) o.Append('♂');
            else if (ch == 0xE08F) o.Append('♀');
            else o.Append((char)ch);
        }
        return o.ToString();
    }
}
