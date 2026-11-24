// A 1541 disk image writer (.d64): 35 tracks, the BAM in track 18 sector 0, the directory
// from track 18 sector 1. Files are written as PRG files, their blocks spread with the
// 1541's usual interleave of 10 so a real drive reads them at a good speed.
//
//   GaTool d64 OUT.d64 "DISK NAME" ID NAME=FILE [NAME=FILE ...]

using System.Text;

static class D64
{
    static int SectorsOn(int track) => track switch
    {
        <= 17 => 21,
        <= 24 => 19,
        <= 30 => 18,
        _ => 17,
    };

    static int Offset(int track, int sector)
    {
        var o = 0;
        for (var t = 1; t < track; t++) o += SectorsOn(t) * 256;
        return o + sector * 256;
    }

    public static void Write(string outPath, string diskName, string id, IEnumerable<(string Name, byte[] Data)> files)
    {
        var img = new byte[Offset(36, 0)];
        var used = new HashSet<(int, int)> { (18, 0), (18, 1) };
        var dir = new List<byte[]>();
        int track = 17, sector = 0;

        (int, int) Next()
        {
            // Fill from track 17 down to 1, then 19 up to 35, interleave 10 within a track.
            for (var tries = 0; tries < 800; tries++)
            {
                if (!used.Contains((track, sector)))
                {
                    used.Add((track, sector));
                    return (track, sector);
                }
                sector = (sector + 10) % SectorsOn(track);
                if (Enumerable.Range(0, SectorsOn(track)).All(s => used.Contains((track, s))))
                {
                    track = track == 1 ? 19 : track < 18 ? track - 1 : track + 1;
                    if (track > 35) throw new ModelException("d64: disk full");
                    sector = 0;
                }
            }
            throw new ModelException("d64: no free sector found");
        }

        foreach (var (name, data) in files)
        {
            var blocks = Math.Max(1, (data.Length + 253) / 254);
            var chain = Enumerable.Range(0, blocks).Select(_ => Next()).ToList();
            for (var b = 0; b < blocks; b++)
            {
                var (t, s) = chain[b];
                var o = Offset(t, s);
                var part = data.Skip(b * 254).Take(254).ToArray();
                if (b + 1 < blocks)
                {
                    img[o] = (byte)chain[b + 1].Item1;
                    img[o + 1] = (byte)chain[b + 1].Item2;
                }
                else
                {
                    img[o] = 0;
                    img[o + 1] = (byte)(part.Length + 1);   // index of the last byte used
                }
                Array.Copy(part, 0, img, o + 2, part.Length);
            }
            var entry = new byte[32];
            entry[2] = 0x82;                                // PRG, closed
            entry[3] = (byte)chain[0].Item1;
            entry[4] = (byte)chain[0].Item2;
            Pad(name).CopyTo(entry, 5);
            entry[30] = (byte)(blocks & 0xFF);
            entry[31] = (byte)(blocks >> 8);
            dir.Add(entry);
        }
        if (dir.Count > 8) throw new ModelException("d64: more than 8 files (one directory sector)");

        var d = Offset(18, 1);                              // the directory: one sector
        img[d] = 0;
        img[d + 1] = 0xFF;
        for (var i = 0; i < dir.Count; i++)
            for (var k = 2; k < 32; k++) img[d + i * 32 + k] = dir[i][k];

        var bam = Offset(18, 0);
        img[bam] = 18;
        img[bam + 1] = 1;
        img[bam + 2] = 0x41;                                // DOS version 'A'
        for (var t = 1; t <= 35; t++)
        {
            var n = SectorsOn(t);
            var free = 0;
            var bits = 0;
            for (var s = 0; s < n; s++)
                if (!used.Contains((t, s))) { free++; bits |= 1 << s; }
            img[bam + 4 * t] = (byte)free;
            img[bam + 4 * t + 1] = (byte)(bits & 0xFF);
            img[bam + 4 * t + 2] = (byte)((bits >> 8) & 0xFF);
            img[bam + 4 * t + 3] = (byte)((bits >> 16) & 0xFF);
        }
        Pad(diskName).CopyTo(img, bam + 0x90);
        img[bam + 0xA0] = 0xA0;
        img[bam + 0xA1] = 0xA0;
        var idb = Encoding.ASCII.GetBytes(id.PadRight(2)[..2]);
        img[bam + 0xA2] = idb[0];
        img[bam + 0xA3] = idb[1];
        img[bam + 0xA4] = 0xA0;
        img[bam + 0xA5] = (byte)'2';
        img[bam + 0xA6] = (byte)'A';
        for (var k = 0xA7; k <= 0xAA; k++) img[bam + k] = 0xA0;
        File.WriteAllBytes(outPath, img);
    }

    // A file or disk name: up to 16 characters, uppercase ASCII as PETSCII, padded with $A0.
    static byte[] Pad(string name)
    {
        var b = Enumerable.Repeat((byte)0xA0, 16).ToArray();
        var up = name.ToUpperInvariant();
        if (up.Length > 16) throw new ModelException($"d64: name '{name}' longer than 16");
        for (var i = 0; i < up.Length; i++) b[i] = (byte)up[i];
        return b;
    }
}
