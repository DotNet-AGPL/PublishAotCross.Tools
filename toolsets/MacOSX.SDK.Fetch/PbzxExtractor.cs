using System.Buffers.Binary;

namespace MacOSX.SDK.Fetch;

internal enum PayloadKind
{
    /// <summary>Chunked XZ streams ("pbzx" container) - the usual CLT SDK payload.</summary>
    Pbzx,

    /// <summary>Plain cpio archive, no compression at all.</summary>
    RawCpio,
}

internal sealed record PayloadInfo(PayloadKind Kind, long UncompressedBytes, int Chunks);

/// <summary>
/// Unpacks the payload of an Apple installer package.
/// <para>
/// A "pbzx" payload is a sequence of independent XZ streams, each preceded by an
/// 8-byte uncompressed and an 8-byte compressed length. Because the XZ format
/// allows concatenated streams, all chunk bodies are written back to back into a
/// single <c>.xz</c> file that any xz/7-Zip decoder can expand in one pass.
/// </para>
/// </summary>
internal static class PbzxExtractor
{
    private const int BufferSize = 1 << 20;

    public static PayloadInfo Extract(Stream package, long payloadOffset, long payloadSize, string xzPath)
    {
        package.Position = payloadOffset;

        Span<byte> probe = stackalloc byte[12];
        int probed = package.ReadAtLeast(probe, 4, throwOnEndOfStream: false);

        if (probed >= 6 && probe[0] == (byte)'0' && probe[1] == (byte)'7' && probe[2] == (byte)'0' && probe[3] == (byte)'7')
        {
            // Uncompressed cpio (never seen for CLT SDK packages, but cheap to support).
            package.Position = payloadOffset;
            using FileStream raw = File.Create(xzPath);
            CopyBytes(package, raw, payloadSize);
            return new PayloadInfo(PayloadKind.RawCpio, payloadSize, 0);
        }

        if (probed < 12 || probe[0] != (byte)'p' || probe[1] != (byte)'b' || probe[2] != (byte)'z' || probe[3] != (byte)'x')
            throw new InvalidDataException(
                $"payload is neither pbzx nor cpio (first bytes: {Convert.ToHexString(probe[..probed])})");

        package.Position = payloadOffset + 12; // "pbzx" + 8-byte flags

        long end = payloadOffset + payloadSize;
        long totalUncompressed = 0;
        int chunks = 0;

        using FileStream xz = File.Create(xzPath);
        byte[] buffer = new byte[BufferSize];
        byte[] chunkHeader = new byte[16];

        while (package.Position < end)
        {
            long remaining = end - package.Position;
            if (remaining < 16)
                break; // trailing padding

            package.ReadExactly(chunkHeader);
            ReadOnlySpan<byte> header = chunkHeader;

            long uncompressed = (long)BinaryPrimitives.ReadUInt64BigEndian(header);
            long compressed = (long)BinaryPrimitives.ReadUInt64BigEndian(header[8..]);

            if (uncompressed == 0 && compressed == 0)
                break;

            if (compressed <= 0 || compressed > remaining - 16)
                throw new InvalidDataException($"corrupt pbzx chunk header (compressed={compressed}, remaining={remaining - 16})");

            totalUncompressed += uncompressed;
            chunks++;

            long left = compressed;
            while (left > 0)
            {
                int want = (int)Math.Min(buffer.Length, left);
                int read = package.Read(buffer, 0, want);
                if (read <= 0)
                    throw new EndOfStreamException("unexpected end of payload while reading an xz chunk");
                xz.Write(buffer, 0, read);
                left -= read;
            }
        }

        xz.Flush();

        if (chunks == 0)
            throw new InvalidDataException("pbzx payload contains no chunks");

        return new PayloadInfo(PayloadKind.Pbzx, totalUncompressed, chunks);
    }

    private static void CopyBytes(Stream source, Stream destination, long count)
    {
        byte[] buffer = new byte[BufferSize];
        long left = count;
        while (left > 0)
        {
            int read = source.Read(buffer, 0, (int)Math.Min(buffer.Length, left));
            if (read <= 0)
                throw new EndOfStreamException("unexpected end of payload");
            destination.Write(buffer, 0, read);
            left -= read;
        }
    }
}
