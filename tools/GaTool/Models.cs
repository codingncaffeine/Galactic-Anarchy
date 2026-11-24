// The model compiler: reads the .model files and writes models.inc.
//
// A .model file holds any number of models. Lines (# starts a comment):
//   model NAME            a new model; NAME is used in the source as MODEL_NAME
//   title TEXT            the name shown on the panel (default: NAME in capitals)
//   roster                list it in the roster scene
//   solid                 hidden-line removal: edges on the far side of the model's
//                         convex hull are not drawn (asteroids are always solid)
//   v NAME X Y Z          a vertex (x right, y up, z forward; -127 to 127)
//   m NAME X Y Z          a mirrored pair: NAME.l at -X and NAME.r at X
//   ring NAME N R Z       N vertices NAME0.. on a circle of radius R around the z axis
//   e A B C ...           edges A-B, B-C, ...
//   me A B C ...          the same chain on both sides: a mirrored name means its .l
//                         vertex on the left pass and its .r vertex on the right pass
//   loop A B C ...        a closed chain; NAME* stands for all of a ring's vertices
//   pairs A B             ring A's vertex i to ring B's vertex i
//   frame                 an animation frame: the v/m/ring lines after it move the named
//                         vertices; edges stay the model's own. Frames play in order and
//                         loop back to the model.
//   asteroid SIZE R SEED  a rock: SIZE large (10 vertices, 15 edges), medium (8, 12) or
//                         small (4, 6), radius about R, shape from SEED
// Every vertex must be used by an edge, and duplicate edges are dropped.

using System.Text;

sealed class ModelException(string message) : Exception(message);

static class Models
{
    sealed class Model
    {
        public required string Name;
        public string? Title;
        public bool Roster;
        public bool Solid;
        public readonly List<string> Order = [];
        public readonly Dictionary<string, (int X, int Y, int Z)> Verts = [];
        public readonly List<(string A, string B)> Edges = [];
        public readonly List<Dictionary<string, (int X, int Y, int Z)>> Frames = [];
        public readonly Dictionary<string, int> Rings = [];
    }

    // For the preview: every model and animation frame as (label, title, vertices, edges).
    public static List<(string Label, string Title, (int X, int Y, int Z)[] V, (int A, int B)[] E, bool Solid)> Load(string dir)
    {
        var list = new List<(string, string, (int, int, int)[], (int, int)[], bool)>();
        foreach (var file in Directory.GetFiles(dir, "*.model").OrderBy(f => f, StringComparer.Ordinal))
            foreach (var m in Parse(file))
            {
                var edges = Resolve(m).ToArray();
                var title = (m.Title ?? m.Name).ToUpperInvariant();
                list.Add((m.Name, title, m.Order.Select(n => m.Verts[n]).ToArray(), edges, m.Solid));
                for (var i = 0; i < m.Frames.Count; i++)
                {
                    var pos = new Dictionary<string, (int, int, int)>(m.Verts);
                    foreach (var (k, v) in m.Frames[i]) pos[k] = v;
                    list.Add(($"{m.Name}_f{i + 1}", title, m.Order.Select(n => pos[n]).ToArray(), edges, m.Solid));
                }
            }
        return list;
    }

    public static string Generate(string dir)
    {
        var models = new List<Model> { Builtin("cube", Cube(100)), Builtin("ico", Icosahedron(60, 97)) };
        foreach (var file in Directory.GetFiles(dir, "*.model").OrderBy(f => f, StringComparer.Ordinal))
            models.AddRange(Parse(file));
        if (models.Select(m => m.Name).Distinct().Count() != models.Count)
            throw new ModelException("models: two models share a name");
        return Write(models);
    }

    static Model Builtin(string name, ((int, int, int)[] V, (int, int)[] E) shape)
    {
        var m = new Model { Name = name };
        for (var i = 0; i < shape.V.Length; i++) { m.Order.Add($"p{i}"); m.Verts[$"p{i}"] = shape.V[i]; }
        foreach (var (a, b) in shape.E) m.Edges.Add(($"p{a}", $"p{b}"));
        return m;
    }

    static IEnumerable<Model> Parse(string file)
    {
        var result = new List<Model>();
        Model? m = null;
        Dictionary<string, (int, int, int)>? frame = null;
        var lineNo = 0;
        foreach (var raw in File.ReadLines(file))
        {
            lineNo++;
            var line = raw.Split('#')[0].Trim();
            if (line.Length == 0) continue;
            var t = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            string Where() => $"{Path.GetFileName(file)}:{lineNo}";
            int Num(int i)
            {
                if (i >= t.Length || !int.TryParse(t[i], out var v)) throw new ModelException($"{Where()}: number expected");
                return v;
            }
            if (t[0] == "model")
            {
                m = new Model { Name = t[1] };
                frame = null;
                result.Add(m);
                continue;
            }
            if (m is null) throw new ModelException($"{Where()}: 'model' expected first");

            void Put(string name, (int X, int Y, int Z) p)
            {
                if (frame is not null)
                {
                    if (!m.Verts.ContainsKey(name)) throw new ModelException($"{Where()}: frame moves unknown vertex {name}");
                    frame[name] = p;
                    return;
                }
                if (m.Verts.ContainsKey(name)) throw new ModelException($"{Where()}: vertex {name} defined twice");
                m.Order.Add(name);
                m.Verts[name] = p;
            }

            switch (t[0])
            {
                case "title": m.Title = line[6..].Trim(); break;
                case "roster": m.Roster = true; break;
                case "solid": m.Solid = true; break;
                case "v": Put(t[1], (Num(2), Num(3), Num(4))); break;
                case "m":
                    Put(t[1] + ".l", (-Num(2), Num(3), Num(4)));
                    Put(t[1] + ".r", (Num(2), Num(3), Num(4)));
                    break;
                case "ring":
                {
                    var n = Num(2); var r = Num(3); var z = Num(4);
                    if (frame is null) m.Rings[t[1]] = n;
                    for (var i = 0; i < n; i++)
                    {
                        var a = 2 * Math.PI * i / n;
                        Put($"{t[1]}{i}", ((int)Math.Round(r * Math.Sin(a)), (int)Math.Round(r * Math.Cos(a)), z));
                    }
                    break;
                }
                case "e": Chain(m, Expand(m, t.Skip(1), Where), false, Where); break;
                case "loop": Chain(m, Expand(m, t.Skip(1), Where), true, Where); break;
                case "me":
                    foreach (var side in new[] { ".l", ".r" })
                        Chain(m, t.Skip(1).Select(n => m.Verts.ContainsKey(n + side) ? n + side : n).ToList(), false, Where);
                    break;
                case "pairs":
                {
                    var a = Expand(m, [t[1] + "*"], Where); var b = Expand(m, [t[2] + "*"], Where);
                    if (a.Count != b.Count) throw new ModelException($"{Where()}: rings differ in size");
                    for (var i = 0; i < a.Count; i++) m.Edges.Add((a[i], b[i]));
                    break;
                }
                case "frame":
                    frame = [];
                    m.Frames.Add(frame);
                    break;
                case "asteroid":
                {
                    var (v, e) = Asteroid(t[1], Num(2), Num(3), Where);
                    m.Solid = true;
                    for (var i = 0; i < v.Length; i++) Put($"p{i}", v[i]);
                    foreach (var (a, b) in e) m.Edges.Add(($"p{a}", $"p{b}"));
                    break;
                }
                default: throw new ModelException($"{Where()}: unknown line '{t[0]}'");
            }
        }
        return result;
    }

    static List<string> Expand(Model m, IEnumerable<string> names, Func<string> where)
    {
        var list = new List<string>();
        foreach (var n in names)
        {
            if (n.EndsWith('*'))
            {
                var ring = n[..^1];
                if (!m.Rings.TryGetValue(ring, out var count)) throw new ModelException($"{where()}: no ring {ring}");
                for (var i = 0; i < count; i++) list.Add($"{ring}{i}");
            }
            else list.Add(n);
        }
        return list;
    }

    static void Chain(Model m, List<string> names, bool closed, Func<string> where)
    {
        foreach (var n in names)
            if (!m.Verts.ContainsKey(n)) throw new ModelException($"{where()}: unknown vertex {n}");
        for (var i = 0; i + 1 < names.Count; i++) m.Edges.Add((names[i], names[i + 1]));
        if (closed && names.Count > 2) m.Edges.Add((names[^1], names[0]));
    }

    // Checks a model and returns its edges as index pairs, without duplicates.
    static List<(int A, int B)> Resolve(Model m)
    {
        var index = m.Order.Select((n, i) => (n, i)).ToDictionary(p => p.n, p => p.i);
        var seen = new HashSet<(int, int)>();
        var edges = new List<(int, int)>();
        foreach (var (a, b) in m.Edges)
        {
            if (a == b) throw new ModelException($"{m.Name}: edge from {a} to itself");
            var key = (Math.Min(index[a], index[b]), Math.Max(index[a], index[b]));
            if (seen.Add(key)) edges.Add((index[a], index[b]));
        }
        if (m.Solid && m.Frames.Count > 0) throw new ModelException($"{m.Name}: a solid model cannot have frames");
        var used = edges.SelectMany(e => new[] { e.Item1, e.Item2 }).ToHashSet();
        var unused = m.Order.Where((n, i) => !used.Contains(i)).ToList();
        if (unused.Count > 0) throw new ModelException($"{m.Name}: vertices on no edge: {string.Join(", ", unused)}");
        if (m.Order.Count > 64) throw new ModelException($"{m.Name}: {m.Order.Count} vertices (at most 64)");
        if (edges.Count > 64) throw new ModelException($"{m.Name}: {edges.Count} edges (at most 64)");
        foreach (var (name, p) in m.Verts.Concat(m.Frames.SelectMany(f => f)))
            if (new[] { p.X, p.Y, p.Z }.Any(c => c < -127 || c > 127))
                throw new ModelException($"{m.Name}: vertex {name} out of range (-127 to 127)");
        return edges;
    }

    static string Write(List<Model> models)
    {
        var sb = new StringBuilder();
        sb.AppendLine("; Generated by tools/GaTool from models/*.model. Do not edit.");
        sb.AppendLine("; Per model: x/y/z arrays and the two vertex indices of each edge. Coordinates");
        sb.AppendLine("; are stored biased (signed value + 128), the form the transform indexes its");
        sb.AppendLine("; multiply tables with. Animation frames are models of their own that share");
        sb.AppendLine("; their first frame's edges; model_next names the frame after each one.");
        sb.AppendLine("        .segment \"RODATA\"");

        // Entries: every model, then its frames.
        var entries = new List<(Model M, string Label, Dictionary<string, (int X, int Y, int Z)> Pos, int Next)>();
        foreach (var m in models)
        {
            var first = entries.Count;
            entries.Add((m, m.Name, m.Verts, first));
            foreach (var (f, i) in m.Frames.Select((f, i) => (f, i)))
            {
                var pos = new Dictionary<string, (int, int, int)>(m.Verts);
                foreach (var (k, v) in f) pos[k] = v;
                entries.Add((m, $"{m.Name}_f{i + 1}", pos, first));
            }
            for (var i = first; i < entries.Count; i++)
                entries[i] = entries[i] with { Next = i + 1 < entries.Count ? i + 1 : first };
        }

        var edgeLists = models.ToDictionary(m => m.Name, Resolve);
        for (var i = 0; i < entries.Count; i++)
        {
            var (m, label, pos, _) = entries[i];
            sb.AppendLine($"MODEL_{label.ToUpperInvariant()} = {i}");
            var verts = m.Order.Select(n => pos[n]).ToList();
            Emit.Bytes(sb, $"model_{label}_x", verts.Select(v => v.X + 128));
            Emit.Bytes(sb, $"model_{label}_y", verts.Select(v => v.Y + 128));
            Emit.Bytes(sb, $"model_{label}_z", verts.Select(v => v.Z + 128));
        }
        foreach (var m in models)
        {
            Emit.Bytes(sb, $"model_{m.Name}_ea", edgeLists[m.Name].Select(e => e.A));
            Emit.Bytes(sb, $"model_{m.Name}_eb", edgeLists[m.Name].Select(e => e.B));
            var title = (m.Title ?? m.Name).ToUpperInvariant();
            if (title.Length > 20 || title.Any(c => !(c is >= 'A' and <= 'Z' or >= '0' and <= '9' or ' ' or '-')))
                throw new ModelException($"{m.Name}: title '{title}' (at most 20 letters, digits, spaces, -)");
            sb.AppendLine($"model_{m.Name}_title:");
            sb.AppendLine("        .byte   " + string.Join(",", title.Select(c => $"${Font.ScreenCode(c):X2}").Append("$00")));
        }

        sb.AppendLine($"MODEL_COUNT = {entries.Count}");
        string Col(Func<(Model M, string Label, Dictionary<string, (int X, int Y, int Z)> Pos, int Next), string> f) =>
            string.Join(", ", entries.Select(f));
        sb.AppendLine($"model_vcount:   .byte {Col(e => e.M.Order.Count.ToString())}");
        sb.AppendLine($"model_ecount:   .byte {Col(e => edgeLists[e.M.Name].Count.ToString())}");
        foreach (var axis in new[] { "x", "y", "z" })
        {
            sb.AppendLine($"model_{axis}_lo:     .byte {Col(e => $"<model_{e.Label}_{axis}")}");
            sb.AppendLine($"model_{axis}_hi:     .byte {Col(e => $">model_{e.Label}_{axis}")}");
        }
        foreach (var part in new[] { "ea", "eb", "title" })
        {
            sb.AppendLine($"model_{part}_lo:    .byte {Col(e => $"<model_{e.M.Name}_{part}")}");
            sb.AppendLine($"model_{part}_hi:    .byte {Col(e => $">model_{e.M.Name}_{part}")}");
        }
        sb.AppendLine($"model_next:     .byte {Col(e => e.Next.ToString())}");

        // Hidden lines (solid models): per model one block of its hull faces as vertex
        // triples (a, b, c), then for every edge the first and then the second face it
        // lies on (NO_FACE: none). A face is seen when its projected corners turn
        // clockwise on the screen (y down).
        var hulls = new List<string>();
        sb.AppendLine($"NO_FACE = {NoFace}");
        for (var i = 0; i < entries.Count; i++)
        {
            var (m, label, pos, _) = entries[i];
            if (!m.Solid) { hulls.Add("0"); continue; }
            var (faces, ef) = Hull(m.Order.Select(n => pos[n]).ToList(), edgeLists[m.Name], m.Name);
            var block = faces.SelectMany(f => new[] { f.A, f.B, f.C })
                .Concat(ef.Select(p => p.F1)).Concat(ef.Select(p => p.F2));
            Emit.Bytes(sb, $"model_{label}_hl", block);
            hulls.Add(faces.Count.ToString());
        }
        sb.AppendLine($"model_fcount:   .byte {string.Join(", ", hulls)}");
        sb.AppendLine($"model_hl_lo:    .byte {Col(e => e.M.Solid ? $"<model_{e.Label}_hl" : "0")}");
        sb.AppendLine($"model_hl_hi:    .byte {Col(e => e.M.Solid ? $">model_{e.Label}_hl" : "0")}");

        // hl_log[b] = 16 * log2 |b| for the signed byte b (0 for b = 0): the hidden-line
        // pass compares two products by their logarithms.
        Emit.Bytes(sb, "hl_log", Enumerable.Range(0, 256).Select(b =>
        {
            var v = b < 128 ? b : 256 - b;
            return v == 0 ? 0 : (int)Math.Round(16 * Math.Log2(v));
        }));

        // Bounding radius for culling whole objects, over the model and its frames.
        var radius = entries.Select(e => (int)Math.Ceiling(entries.Where(o => o.M == e.M)
            .SelectMany(o => o.Pos.Values).Max(p => Math.Sqrt(p.X * p.X + p.Y * p.Y + p.Z * p.Z)))).ToList();
        sb.AppendLine($"model_radius:   .byte {string.Join(", ", radius)}");

        // The distance at which the model fills most of the viewport height: the radius
        // that holds 80% of its vertices (thin parts like antennae may stick out) at
        // 64 pixels, radius * 32768 / z = 64 * 256.
        var viewZ = entries.Select(e =>
        {
            var radii = e.Pos.Values.Select(p => Math.Sqrt(p.X * p.X + p.Y * p.Y + p.Z * p.Z)).Order().ToList();
            var r = radii[(int)Math.Floor(0.8 * (radii.Count - 1))];
            // ...and never so close that a vertex crosses the near plane (z 128).
            return Math.Max((int)Math.Ceiling(radii[^1]) + 160, (int)Math.Ceiling(r * 32768 / (64 * 256)));
        }).ToList();
        sb.AppendLine($"model_view_z_lo: .byte {string.Join(", ", viewZ.Select(z => $"<{z}"))}");
        sb.AppendLine($"model_view_z_hi: .byte {string.Join(", ", viewZ.Select(z => $">{z}"))}");

        var roster = entries.Select((e, i) => (e, i)).Where(p => p.e.M.Roster && p.e.Label == p.e.M.Name).ToList();
        sb.AppendLine($"ROSTER_COUNT = {roster.Count}");
        sb.AppendLine($"roster_model:   .byte {string.Join(", ", roster.Select(p => p.i))}");
        return sb.ToString();
    }

    public const int NoFace = 31;

    // The convex hull of a model's vertices as faces (three corners each, turning so that
    // (b - a) x (c - a) points outwards), and for every edge the hull faces it lies on.
    // Coplanar corners make one face, so a box has six. Exact integer arithmetic.
    public static (List<(int A, int B, int C)> Faces, List<(int F1, int F2)> EdgeFaces) Hull(
        List<(int X, int Y, int Z)> v, IList<(int A, int B)> edges, string name)
    {
        var planes = new Dictionary<(long, long, long, long), (int A, int B, int C, long Area, long Nx, long Ny, long Nz, long D)>();
        var order = new List<(long, long, long, long)>();
        for (var i = 0; i < v.Count; i++)
            for (var j = i + 1; j < v.Count; j++)
                for (var k = j + 1; k < v.Count; k++)
                {
                    long ux = v[j].X - v[i].X, uy = v[j].Y - v[i].Y, uz = v[j].Z - v[i].Z;
                    long wx = v[k].X - v[i].X, wy = v[k].Y - v[i].Y, wz = v[k].Z - v[i].Z;
                    long nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
                    if (nx == 0 && ny == 0 && nz == 0) continue;
                    var d = nx * v[i].X + ny * v[i].Y + nz * v[i].Z;
                    int pos = 0, neg = 0;
                    foreach (var p in v)
                    {
                        var s = nx * p.X + ny * p.Y + nz * p.Z - d;
                        if (s > 0) pos++; else if (s < 0) neg++;
                    }
                    if (pos > 0 && neg > 0) continue;
                    if (pos == 0 && neg == 0) continue;     // a flat model has no inside
                    int a = i, b = j, c = k;
                    if (pos > 0) { nx = -nx; ny = -ny; nz = -nz; d = -d; (b, c) = (c, b); }
                    var g = Gcd(Gcd(Math.Abs(nx), Math.Abs(ny)), Gcd(Math.Abs(nz), Math.Abs(d)));
                    var key = (nx / g, ny / g, nz / g, d / g);
                    var area = nx * nx + ny * ny + nz * nz;
                    if (!planes.TryGetValue(key, out var have)) order.Add(key);
                    else if (have.Area >= area) continue;
                    planes[key] = (a, b, c, area, nx, ny, nz, d);
                }
        if (order.Count == 0) throw new ModelException($"{name}: solid, but its vertices are flat");
        if (order.Count >= NoFace) throw new ModelException($"{name}: {order.Count} hull faces (at most {NoFace - 1})");
        var faces = order.Select(k => planes[k]).ToList();
        bool On(int f, int p) => faces[f].Nx * v[p].X + faces[f].Ny * v[p].Y + faces[f].Nz * v[p].Z == faces[f].D;
        var ef = new List<(int, int)>();
        foreach (var (ea, eb) in edges)
        {
            var on = Enumerable.Range(0, faces.Count).Where(f => On(f, ea) && On(f, eb)).Take(2).ToList();
            ef.Add((on.Count > 0 ? on[0] : NoFace, on.Count > 1 ? on[1] : on.Count > 0 ? on[0] : NoFace));
        }
        return (faces.Select(f => (f.A, f.B, f.C)).ToList(), ef);
    }

    static long Gcd(long a, long b) { while (b != 0) (a, b) = (b, a % b); return a == 0 ? 1 : a; }

    static ((int, int, int)[], (int, int)[]) Cube(int s)
    {
        var v = new List<(int, int, int)>();
        for (var i = 0; i < 8; i++)
            v.Add(((i & 1) != 0 ? s : -s, (i & 2) != 0 ? s : -s, (i & 4) != 0 ? s : -s));
        var e = new List<(int, int)>();
        for (var a = 0; a < 8; a++)
            for (var bit = 1; bit < 8; bit <<= 1)
                if ((a & bit) == 0) e.Add((a, a | bit));
        return (v.ToArray(), e.ToArray());
    }

    // The regular icosahedron: cyclic permutations of (0, +-a, +-b) with b/a the golden ratio.
    // Edges join the vertices at the shortest distance, 2a.
    static ((int, int, int)[], (int, int)[]) Icosahedron(int a, int b)
    {
        var v = new List<(int X, int Y, int Z)>();
        foreach (var sa in new[] { -1, 1 })
            foreach (var sb in new[] { -1, 1 })
            {
                v.Add((0, sa * a, sb * b));
                v.Add((sa * a, sb * b, 0));
                v.Add((sb * b, 0, sa * a));
            }
        var e = new List<(int, int)>();
        long D2(int i, int j) =>
            (long)(v[i].X - v[j].X) * (v[i].X - v[j].X) + (long)(v[i].Y - v[j].Y) * (v[i].Y - v[j].Y)
            + (long)(v[i].Z - v[j].Z) * (v[i].Z - v[j].Z);
        var edge2 = 4L * a * a;
        for (var i = 0; i < v.Count; i++)
            for (var j = i + 1; j < v.Count; j++)
                if (Math.Abs(D2(i, j) - edge2) < edge2 / 10) e.Add((i, j));
        if (e.Count != 30) throw new ModelException($"icosahedron has {e.Count} edges, expected 30");
        return (v.Select(p => (p.X, p.Y, p.Z)).ToArray(), e.ToArray());
    }

    // Rocks: a box (medium), a five-sided prism (large) or a tetrahedron (small), every
    // corner pushed in or out and sideways by a fixed pseudo-random amount from SEED so the
    // outline is lumpy and no two rocks match.
    static ((int, int, int)[], (int, int)[]) Asteroid(string size, int r, int seed, Func<string> where)
    {
        var rng = new Random(seed);
        double J(double spread) => 1 + spread * (2 * rng.NextDouble() - 1);
        var v = new List<(double X, double Y, double Z)>();
        var e = new List<(int, int)>();
        void Corner(double x, double y, double z)
        {
            var k = J(0.3);
            v.Add((x * k + r * 0.15 * (2 * rng.NextDouble() - 1),
                   y * k + r * 0.15 * (2 * rng.NextDouble() - 1),
                   z * k + r * 0.15 * (2 * rng.NextDouble() - 1)));
        }
        switch (size)
        {
            case "large":
            {
                const int n = 5;
                for (var layer = 0; layer < 2; layer++)
                    for (var i = 0; i < n; i++)
                    {
                        var a = 2 * Math.PI * (i + 0.5 * layer) / n;
                        Corner(r * 0.8 * Math.Cos(a), layer == 0 ? r * 0.55 : -r * 0.55, r * 0.8 * Math.Sin(a));
                    }
                for (var i = 0; i < n; i++)
                {
                    e.Add((i, (i + 1) % n));
                    e.Add((n + i, n + (i + 1) % n));
                    e.Add((i, n + i));
                }
                break;
            }
            case "medium":
            {
                // A box whose corners are pulled well off square, then turned on its edge.
                var s = r * 0.55;
                for (var i = 0; i < 8; i++)
                {
                    double x = (i & 1) != 0 ? s : -s, y = (i & 2) != 0 ? s : -s, z = (i & 4) != 0 ? s : -s;
                    var k = J(0.4);
                    v.Add((x * k * 0.8 + y * 0.5 + r * 0.2 * (2 * rng.NextDouble() - 1),
                           y * k * 0.8 - x * 0.5 + r * 0.2 * (2 * rng.NextDouble() - 1),
                           z * k + r * 0.2 * (2 * rng.NextDouble() - 1)));
                }
                for (var a = 0; a < 8; a++)
                    for (var bit = 1; bit < 8; bit <<= 1)
                        if ((a & bit) == 0) e.Add((a, a | bit));
                break;
            }
            case "small":
            {
                double[][] t = [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]];
                foreach (var p in t) Corner(p[0] * r * 0.6, p[1] * r * 0.6, p[2] * r * 0.6);
                for (var i = 0; i < 4; i++)
                    for (var j = i + 1; j < 4; j++) e.Add((i, j));
                break;
            }
            default: throw new ModelException($"{where()}: asteroid size is large, medium or small");
        }
        return (v.Select(p => ((int)Math.Round(p.X), (int)Math.Round(p.Y), (int)Math.Round(p.Z))).ToArray(), e.ToArray());
    }
}
