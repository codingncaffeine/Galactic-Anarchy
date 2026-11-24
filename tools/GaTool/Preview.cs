// Model preview: one row per model (and animation frame) with four views drawn as lines:
// from the top (x right, z up the page), from the front (looking along -z), from the
// right side (z to the right) and in perspective from above and to the front left.
// Written as a grayscale PNG with the model's title in the game's font.

using System.IO.Compression;

static class Preview
{
    const int Cell = 150;
    const int Label = 12;

    public static void Write(string modelsDir, string outPath)
    {
        var models = Models.Load(modelsDir);
        var width = Cell * 4;
        var height = models.Count * (Cell + Label);
        var px = new byte[width * height];

        for (var row = 0; row < models.Count; row++)
        {
            var (label, title, v, e, solid) = models[row];
            var hull = solid ? Models.Hull(v.ToList(), e, label) : default;
            var top = row * (Cell + Label);
            Text(px, width, 2, top + 2, $"{title} {label.ToUpperInvariant().Replace('_', ' ')} {e.Length}");
            var views = new Func<(int X, int Y, int Z), (double, double)>[]
            {
                p => (p.X, -p.Z),
                p => (p.X, -p.Y),
                p => (p.Z, -p.Y),
                p => Perspective(p),
            };
            for (var c = 0; c < 4; c++)
            {
                var pts = v.Select(views[c]).ToArray();
                var scale = (Cell / 2 - 8) / Math.Max(1, pts.Max(p => Math.Max(Math.Abs(p.Item1), Math.Abs(p.Item2))));
                var ox = c * Cell + Cell / 2;
                var oy = top + Label + Cell / 2;
                Box(px, width, c * Cell, top + Label, Cell, Cell, 60);
                // The perspective view of a solid model shows hidden edges dim, by the
                // game's rule: a face is seen unless its corners turn anticlockwise.
                var seen = new bool[Models.NoFace + 1];
                seen[Models.NoFace] = true;
                if (solid && c == 3)
                    for (var f = 0; f < hull.Faces.Count; f++)
                    {
                        var (fa, fb, fc) = hull.Faces[f];
                        var cross = (pts[fb].Item1 - pts[fa].Item1) * (pts[fc].Item2 - pts[fa].Item2)
                                  - (pts[fb].Item2 - pts[fa].Item2) * (pts[fc].Item1 - pts[fa].Item1);
                        seen[f] = cross >= 0;
                    }
                for (var i = 0; i < e.Length; i++)
                {
                    var (a, b) = e[i];
                    var shown = !(solid && c == 3) || seen[hull.EdgeFaces[i].F1] || seen[hull.EdgeFaces[i].F2];
                    Line(px, width, ox + pts[a].Item1 * scale, oy + pts[a].Item2 * scale,
                         ox + pts[b].Item1 * scale, oy + pts[b].Item2 * scale, shown ? (byte)255 : (byte)50);
                }
            }
        }
        Png(outPath, width, height, px);
    }

    static (double, double) Perspective((int X, int Y, int Z) p)
    {
        double yaw = -35 * Math.PI / 180, pitch = 25 * Math.PI / 180;
        var x = p.X * Math.Cos(yaw) + p.Z * Math.Sin(yaw);
        var z = -p.X * Math.Sin(yaw) + p.Z * Math.Cos(yaw);
        var y = p.Y * Math.Cos(pitch) - z * Math.Sin(pitch);
        z = p.Y * Math.Sin(pitch) + z * Math.Cos(pitch);
        var d = 400 / (400 + z);
        return (x * d, -y * d);
    }

    static void Line(byte[] px, int w, double x0, double y0, double x1, double y1, byte value)
    {
        var steps = (int)Math.Ceiling(Math.Max(Math.Abs(x1 - x0), Math.Abs(y1 - y0))) + 1;
        for (var i = 0; i <= steps; i++)
        {
            var x = (int)Math.Round(x0 + (x1 - x0) * i / steps);
            var y = (int)Math.Round(y0 + (y1 - y0) * i / steps);
            if (x >= 0 && x < w && y >= 0 && y < px.Length / w) px[y * w + x] = value;
        }
    }

    static void Box(byte[] px, int w, int x, int y, int bw, int bh, byte value)
    {
        Line(px, w, x, y, x + bw - 1, y, value);
        Line(px, w, x, y + bh - 1, x + bw - 1, y + bh - 1, value);
        Line(px, w, x, y, x, y + bh - 1, value);
        Line(px, w, x + bw - 1, y, x + bw - 1, y + bh - 1, value);
    }

    static void Text(byte[] px, int w, int x, int y, string text)
    {
        foreach (var ch in text)
        {
            if (Font.Glyphs.TryGetValue(ch, out var rows))
                for (var r = 0; r < 7; r++)
                    for (var c = 0; c < 5; c++)
                        if (rows[r][c] == '#' && x + c < w) px[(y + r) * w + x + c] = 200;
            x += 6;
        }
    }

    static void Png(string path, int w, int h, byte[] gray)
    {
        using var f = File.Create(path);
        f.Write([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        var ihdr = new byte[13];
        BE(ihdr, 0, w); BE(ihdr, 4, h);
        ihdr[8] = 8; ihdr[9] = 0;   // 8-bit grayscale
        Chunk(f, "IHDR", ihdr);
        using var raw = new MemoryStream();
        using (var z = new ZLibStream(raw, CompressionLevel.Optimal, true))
            for (var y = 0; y < h; y++)
            {
                z.WriteByte(0);
                z.Write(gray, y * w, w);
            }
        Chunk(f, "IDAT", raw.ToArray());
        Chunk(f, "IEND", []);
    }

    static void BE(byte[] b, int at, int v)
    {
        b[at] = (byte)(v >> 24); b[at + 1] = (byte)(v >> 16); b[at + 2] = (byte)(v >> 8); b[at + 3] = (byte)v;
    }

    static void Chunk(Stream f, string type, byte[] data)
    {
        var len = new byte[4];
        BE(len, 0, data.Length);
        f.Write(len);
        var td = System.Text.Encoding.ASCII.GetBytes(type).Concat(data).ToArray();
        f.Write(td);
        var crc = new byte[4];
        BE(crc, 0, (int)Crc32(td));
        f.Write(crc);
    }

    static uint Crc32(byte[] data)
    {
        var c = 0xFFFFFFFFu;
        foreach (var b in data)
        {
            c ^= b;
            for (var k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        }
        return c ^ 0xFFFFFFFFu;
    }
}
