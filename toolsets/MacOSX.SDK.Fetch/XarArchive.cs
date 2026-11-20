using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using System.Xml.Linq;

namespace MacOSX.SDK.Fetch;

/// <summary>
/// Minimal reader for the xar container used by Apple's installer packages.
/// Layout: 28-byte big-endian header, zlib-compressed XML table of contents, then
/// the heap. Offsets inside the TOC are relative to the start of the heap, which
/// itself starts right after the TOC (the checksum and signature live at the very
/// beginning of the heap and are already accounted for in those offsets).
/// </summary>
internal sealed class XarArchive
{
    private const int HeaderSize = 28;

    private XarArchive(long tocCompressedLength, XDocument toc)
    {
        TocCompressedLength = tocCompressedLength;
        Toc = toc;
    }

    public long TocCompressedLength { get; }

    public XDocument Toc { get; }

    /// <summary>Absolute offset of the heap inside the file.</summary>
    public long HeapOffset => HeaderSize + TocCompressedLength;

    public static XarArchive Open(Stream stream)
    {
        Span<byte> header = stackalloc byte[HeaderSize];
        stream.ReadExactly(header);

        if (header[0] != (byte)'x' || header[1] != (byte)'a' || header[2] != (byte)'r' || header[3] != (byte)'!')
            throw new InvalidDataException("not a xar archive (bad magic)");

        ushort declaredHeaderSize = BinaryPrimitives.ReadUInt16BigEndian(header[4..]);
        if (declaredHeaderSize < HeaderSize)
            throw new InvalidDataException($"unexpected xar header size {declaredHeaderSize}");

        long tocCompressedLength = (long)BinaryPrimitives.ReadUInt64BigEndian(header[8..]);
        long tocUncompressedLength = (long)BinaryPrimitives.ReadUInt64BigEndian(header[16..]);

        if (tocCompressedLength <= 0 || tocCompressedLength > 64L * 1024 * 1024)
            throw new InvalidDataException($"unexpected xar TOC length {tocCompressedLength}");

        byte[] compressed = new byte[tocCompressedLength];
        stream.ReadExactly(compressed);

        using var compressedStream = new MemoryStream(compressed, writable: false);
        using var zlib = new ZLibStream(compressedStream, CompressionMode.Decompress);
        using var reader = new StreamReader(zlib, Encoding.UTF8);

        string xml = reader.ReadToEnd();
        if (tocUncompressedLength > 0 && xml.Length != tocUncompressedLength)
            throw new InvalidDataException($"xar TOC length mismatch: expected {tocUncompressedLength}, got {xml.Length}");

        return new XarArchive(tocCompressedLength, XDocument.Parse(xml));
    }

    /// <summary>Returns the heap-relative offset and length of a TOC file entry.</summary>
    public (long Offset, long Size) FindFile(string name)
    {
        XElement? file = Toc.Root?
            .Elements("toc")
            .Elements("file")
            .FirstOrDefault(e => string.Equals((string?)e.Element("name"), name, StringComparison.Ordinal));

        if (file is null)
            throw new InvalidDataException($"xar archive has no '{name}' entry");

        XElement? data = file.Element("data");
        if (data is null)
            throw new InvalidDataException($"xar '{name}' entry has no data element");

        long offset = (long?)data.Element("offset") ?? throw new InvalidDataException($"xar '{name}' entry has no offset");
        long size = (long?)data.Element("size") ?? throw new InvalidDataException($"xar '{name}' entry has no size");

        return (offset, size);
    }
}
