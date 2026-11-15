using System.IO.Compression;

namespace FluentDeck.DevHost;

/// <summary>Tiny PNG encoder so the simulators can serve real artwork and icons without System.Drawing.</summary>
internal static class Png
{
    public static byte[] Gradient(int size, (byte r, byte g, byte b) a, (byte r, byte g, byte b) b, bool rounded = false)
    {
        var raw = new byte[size * (size * 4 + 1)];
        var i = 0;
        var radius = size * 0.22;
        for (var y = 0; y < size; y++)
        {
            raw[i++] = 0; // filter: none
            for (var x = 0; x < size; x++)
            {
                var t = (x + y) / (2.0 * (size - 1));
                raw[i++] = Lerp(a.r, b.r, t);
                raw[i++] = Lerp(a.g, b.g, t);
                raw[i++] = Lerp(a.b, b.b, t);
                raw[i++] = rounded && OutsideRoundedRect(x, y, size, radius) ? (byte)0 : (byte)255;
            }
        }
        return Encode(size, size, raw);
    }

    private static bool OutsideRoundedRect(int x, int y, int size, double r)
    {
        double cx = x < r ? r : x > size - 1 - r ? size - 1 - r : x;
        double cy = y < r ? r : y > size - 1 - r ? size - 1 - r : y;
        var dx = x - cx; var dy = y - cy;
        return dx * dx + dy * dy > r * r;
    }

    private static byte Lerp(byte a, byte b, double t) => (byte)Math.Round(a + (b - a) * t);

    private static byte[] Encode(int width, int height, byte[] raw)
    {
        using var ms = new MemoryStream();
        ms.Write([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        var ihdr = new byte[13];
        WriteBE(ihdr, 0, width); WriteBE(ihdr, 4, height);
        ihdr[8] = 8; ihdr[9] = 6; // 8-bit RGBA
        Chunk(ms, "IHDR", ihdr);
        using (var z = new MemoryStream())
        {
            using (var zs = new ZLibStream(z, CompressionLevel.Optimal, leaveOpen: true)) zs.Write(raw);
            Chunk(ms, "IDAT", z.ToArray());
        }
        Chunk(ms, "IEND", []);
        return ms.ToArray();
    }

    private static void Chunk(Stream s, string type, byte[] data)
    {
        var len = new byte[4]; WriteBE(len, 0, data.Length); s.Write(len);
        var typeBytes = System.Text.Encoding.ASCII.GetBytes(type);
        s.Write(typeBytes); s.Write(data);
        var crc = new byte[4]; WriteBE(crc, 0, (int)Crc32(typeBytes, data)); s.Write(crc);
    }

    private static void WriteBE(byte[] b, int o, int v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }

    private static uint Crc32(byte[] a, byte[] b)
    {
        var c = 0xFFFFFFFFu;
        foreach (var arr in new[] { a, b })
            foreach (var x in arr)
            {
                c ^= x;
                for (var k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
            }
        return c ^ 0xFFFFFFFFu;
    }
}
