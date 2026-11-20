using System.Text;

namespace MacOSX.SDK.Fetch;

internal enum CpioFileType
{
    Regular,
    Directory,
    Symlink,
    Other,
}

internal sealed record CpioEntry(string Name, CpioFileType Type, long Size, string? LinkTarget);

/// <summary>
/// Streaming reader for the old "odc" cpio format (magic 070707) that Apple uses
/// inside CLT packages. The header is 76 ASCII bytes holding octal fields, the
/// name follows immediately (NUL terminated, included in <c>namesize</c>) and the
/// file data follows the name with no alignment padding.
/// </summary>
internal sealed class OdcCpioReader
{
    private const int HeaderLength = 76;
    private const int NameSizeOffset = 59;
    private const int FileSizeOffset = 65;
    private const int ModeOffset = 18;

    private readonly Stream _stream;
    private readonly byte[] _header = new byte[HeaderLength];

    public OdcCpioReader(Stream stream) => _stream = stream;

    /// <summary>
    /// Reads the next entry header. The caller must then either copy or skip the
    /// file data before calling this again.
    /// </summary>
    public bool TryRead(out CpioEntry entry)
    {
        entry = null!;

        int read = _stream.ReadAtLeast(_header, HeaderLength, throwOnEndOfStream: false);
        if (read == 0)
            return false;
        if (read != HeaderLength)
            throw new EndOfStreamException($"truncated cpio header ({read} of {HeaderLength} bytes)");

        string magic = Encoding.ASCII.GetString(_header, 0, 6);
        if (magic != "070707")
            throw new InvalidDataException($"unsupported cpio format (magic '{magic}', expected '070707')");

        int mode = ParseOctalInt(_header.AsSpan(ModeOffset, 6));
        int nameSize = ParseOctalInt(_header.AsSpan(NameSizeOffset, 6));
        long fileSize = ParseOctalLong(_header.AsSpan(FileSizeOffset, 11));

        if (nameSize <= 0 || nameSize > 4096)
            throw new InvalidDataException($"corrupt cpio name length {nameSize}");

        byte[] nameBytes = new byte[nameSize];
        _stream.ReadExactly(nameBytes);

        // The stored name is NUL terminated and the terminator is part of nameSize.
        int nameLength = nameBytes.Length;
        while (nameLength > 0 && nameBytes[nameLength - 1] == 0)
            nameLength--;

        string name = Encoding.UTF8.GetString(nameBytes, 0, nameLength);
        if (name == "TRAILER!!!")
            return false;

        int fileType = mode & 0xF000;
        CpioFileType type = fileType switch
        {
            0x8000 => CpioFileType.Regular,
            0x4000 => CpioFileType.Directory,
            0xA000 => CpioFileType.Symlink,
            _ => CpioFileType.Other,
        };

        string? linkTarget = null;
        if (type == CpioFileType.Symlink && fileSize > 0 && fileSize <= 4096)
        {
            byte[] target = new byte[fileSize];
            _stream.ReadExactly(target);
            linkTarget = Encoding.UTF8.GetString(target);
            entry = new CpioEntry(name, type, 0, linkTarget);
            return true;
        }

        entry = new CpioEntry(name, type, fileSize, null);
        return true;
    }

    public void CopyData(Stream destination, long count)
    {
        byte[] buffer = new byte[1 << 16];
        long left = count;
        while (left > 0)
        {
            int read = _stream.Read(buffer, 0, (int)Math.Min(buffer.Length, left));
            if (read <= 0)
                throw new EndOfStreamException("unexpected end of cpio data");
            destination.Write(buffer, 0, read);
            left -= read;
        }
    }

    public void SkipData(long count)
    {
        byte[] buffer = new byte[1 << 16];
        long left = count;
        while (left > 0)
        {
            int read = _stream.Read(buffer, 0, (int)Math.Min(buffer.Length, left));
            if (read <= 0)
                throw new EndOfStreamException("unexpected end of cpio data");
            left -= read;
        }
    }

    private static int ParseOctalInt(ReadOnlySpan<byte> field)
    {
        int value = 0;
        bool any = false;
        foreach (byte b in field)
        {
            if (b == 0 || b == (byte)' ')
                continue;
            if (b < (byte)'0' || b > (byte)'7')
                throw new InvalidDataException($"invalid octal digit 0x{b:x2} in cpio header");
            value = (value << 3) + (b - '0');
            any = true;
        }
        return any ? value : 0;
    }

    private static long ParseOctalLong(ReadOnlySpan<byte> field)
    {
        long value = 0;
        foreach (byte b in field)
        {
            if (b == 0 || b == (byte)' ')
                continue;
            if (b < (byte)'0' || b > (byte)'7')
                throw new InvalidDataException($"invalid octal digit 0x{b:x2} in cpio header");
            value = (value * 8) + (b - '0');
        }
        return value;
    }
}
