// Spoken warnings: 16-bit mono WAV files (made by tools/speech.sh with a free speech
// synthesizer) to one program file of 4-bit samples for the SID's volume register.
// The file loads at $E000 and the game copies it to the RAM under the I/O chips at
// $D000. Layout: a count, then per phrase its start address (in the $D000 copy) and
// length in bytes, then the samples, two to a byte, the first in the high nibble.

static class Speech
{
    public const int Rate = 5000;           // samples a second (the player's loop)
    const int RunAt = 0xD000, LoadAt = 0xE000, Room = 0x1000;

    public static void WritePrg(string outPath, IEnumerable<string> wavs)
    {
        var phrases = wavs.Select(Convert).ToList();
        var header = 1 + 4 * phrases.Count;
        var data = new List<byte> { (byte)phrases.Count };
        var at = RunAt + header;
        foreach (var p in phrases)
        {
            data.AddRange([(byte)at, (byte)(at >> 8), (byte)p.Length, (byte)(p.Length >> 8)]);
            at += p.Length;
        }
        foreach (var p in phrases) data.AddRange(p);
        if (data.Count > Room) throw new ModelException($"speech: {data.Count} bytes, room for {Room}");
        File.WriteAllBytes(outPath, [LoadAt & 0xFF, LoadAt >> 8, .. data]);
    }

    static byte[] Convert(string path)
    {
        var b = File.ReadAllBytes(path);
        if (b.Length < 44 || System.Text.Encoding.ASCII.GetString(b, 0, 4) != "RIFF")
            throw new ModelException($"{path}: not a WAV file");
        int pos = 12, rate = 0, bits = 0, channels = 0;
        short[]? pcm = null;
        while (pos + 8 <= b.Length)
        {
            var id = System.Text.Encoding.ASCII.GetString(b, pos, 4);
            var len = BitConverter.ToInt32(b, pos + 4);
            if (id == "fmt ")
            {
                channels = BitConverter.ToInt16(b, pos + 10);
                rate = BitConverter.ToInt32(b, pos + 12);
                bits = BitConverter.ToInt16(b, pos + 22);
            }
            else if (id == "data")
            {
                len = Math.Min(len, b.Length - pos - 8);
                pcm = new short[len / 2];
                Buffer.BlockCopy(b, pos + 8, pcm, 0, pcm.Length * 2);
            }
            pos += 8 + len + (len & 1);
        }
        if (pcm is null || bits != 16 || channels != 1) throw new ModelException($"{path}: 16-bit mono expected");

        // Trim the silence at both ends, then resample (averaging each output step).
        const int quiet = 500;
        var first = Array.FindIndex(pcm, v => Math.Abs((int)v) > quiet);
        var last = Array.FindLastIndex(pcm, v => Math.Abs((int)v) > quiet);
        if (first < 0) throw new ModelException($"{path}: silent");
        var n = (int)((long)(last - first + 1) * Rate / rate);
        var outv = new double[n];
        for (var i = 0; i < n; i++)
        {
            int a = first + (int)((long)i * rate / Rate), z = first + (int)((long)(i + 1) * rate / Rate);
            double sum = 0;
            for (var k = a; k < Math.Max(z, a + 1); k++) sum += pcm[Math.Min(k, last)];
            outv[i] = sum / Math.Max(1, z - a);
        }
        var peak = outv.Max(Math.Abs);
        var nib = outv.Select(v => Math.Clamp((int)Math.Round(7.5 + 7.5 * v / peak), 0, 15)).ToList();
        if (nib.Count % 2 == 1) nib.Add(8);
        var packed = new byte[nib.Count / 2];
        for (var i = 0; i < packed.Length; i++) packed[i] = (byte)(nib[2 * i] << 4 | nib[2 * i + 1]);
        return packed;
    }
}
