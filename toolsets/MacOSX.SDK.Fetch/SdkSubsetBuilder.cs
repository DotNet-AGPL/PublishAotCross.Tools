namespace MacOSX.SDK.Fetch;

/// <summary>
/// Streams the SDK tree out of an <c>odc</c> cpio archive, keeping only the files
/// Native AOT needs to link an osx-arm64 binary and materializing the framework
/// stubs that the SDK stores as symbolic links.
/// </summary>
internal sealed class SdkSubsetBuilder
{
    /// <summary>
    /// Frameworks the ILCompiler macOS link step and the shipped native libraries
    /// reference (the latter through LC_LINKER_OPTION entries that Zig's linker does
    /// not expand). CoreServices re-exports CFNetwork, so both must be present.
    /// </summary>
    public static readonly string[] Frameworks =
    {
        "CoreFoundation", "Foundation", "Security", "Network", "GSS", "CryptoKit",
        "CFNetwork", "Combine", "CoreServices", "DiskArbitration", "IOKit", "LocalAuthentication",
    };

    private const string IncludePrefix = "usr/include/";
    private const string LibraryPrefix = "usr/lib/";
    private const string FrameworksPrefix = "System/Library/Frameworks/";

    private readonly string _root;
    private readonly string? _trace;
    private readonly List<(string Path, string Target)> _symlinks = new();
    private readonly HashSet<string> _written = new(StringComparer.Ordinal);

    public SdkSubsetBuilder(string root, string? trace = null)
    {
        _root = root;
        _trace = trace;
    }

    public int FileCount { get; private set; }

    public long ByteCount { get; private set; }

    public int SkippedSymlinks { get; private set; }

    /// <summary>Symbolic links whose target was not part of the extracted subset.</summary>
    public IReadOnlyList<(string Path, string Target)> Unresolved => _symlinks;

    public void Add(CpioEntry entry, OdcCpioReader reader)
    {
        string? relative = ToSdkRelativePath(entry.Name);
        if (relative is null)
        {
            reader.SkipData(entry.Size);
            return;
        }

        switch (entry.Type)
        {
            case CpioFileType.Symlink:
                // Only stub links matter: headers and directory links (Versions/Current,
                // Headers, Modules, the whole System/Cryptexes mirror, ...) are not needed
                // to link, and materializing them would duplicate the tree.
                if (IsWanted(relative))
                {
                    _symlinks.Add((relative, entry.LinkTarget ?? string.Empty));
                    if (_trace is not null && relative.Contains(_trace, StringComparison.Ordinal))
                        Console.WriteLine($"trace     : symlink  {relative} -> {entry.LinkTarget}");
                }
                reader.SkipData(entry.Size);
                return;

            case CpioFileType.Regular when IsWanted(relative):
                if (_trace is not null && relative.Contains(_trace, StringComparison.Ordinal))
                    Console.WriteLine($"trace     : regular  {relative} ({entry.Size} bytes)");
                WriteFile(relative, entry.Size, reader);
                return;

            default:
                if (_trace is not null && relative.Contains(_trace, StringComparison.Ordinal))
                    Console.WriteLine($"trace     : {entry.Type,-9} {relative}");
                reader.SkipData(entry.Size);
                return;
        }
    }

    /// <summary>
    /// Materializes symbolic links and makes sure every framework exposes its stub at
    /// the top level (<c>Foo.framework/Foo.tbd</c>), which is the path the linker
    /// probes. Apple stores that entry as a link to <c>Versions/Current/...</c>.
    /// </summary>
    public void Finish()
    {
        ResolveSymlinks();
        NormalizeFrameworks();
    }

    private void WriteFile(string relative, long size, OdcCpioReader reader)
    {
        if (!_written.Add(relative))
        {
            reader.SkipData(size);
            return;
        }

        string destination = Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);

        using (FileStream file = File.Create(destination))
            reader.CopyData(file, size);

        FileCount++;
        ByteCount += size;
    }

    private void ResolveSymlinks()
    {
        // One level of indirection is enough for the SDK stubs; repeat a few times so
        // chains (a -> b -> c) still resolve regardless of archive order.
        for (int pass = 0; pass < 4 && _symlinks.Count > 0; pass++)
        {
            bool progress = false;
            for (int i = _symlinks.Count - 1; i >= 0; i--)
            {
                (string path, string target) = _symlinks[i];
                string? resolved = Resolve(path, target);
                if (resolved is null)
                    continue;

                string destination = Path.Combine(_root, path.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                File.Copy(Path.Combine(_root, resolved.Replace('/', Path.DirectorySeparatorChar)), destination, overwrite: true);
                _symlinks.RemoveAt(i);
                progress = true;
            }

            if (!progress)
                break;
        }

        SkippedSymlinks = _symlinks.Count;
    }

    private string? Resolve(string linkPath, string target)
    {
        if (target.Length == 0)
            return null;

        string combined = target.StartsWith('/')
            ? target.TrimStart('/')
            : CombineRelative(linkPath, target);

        combined = Collapse(combined);

        return File.Exists(Path.Combine(_root, combined.Replace('/', Path.DirectorySeparatorChar))) ? combined : null;
    }

    private void NormalizeFrameworks()
    {
        foreach (string framework in Frameworks)
        {
            string directory = Path.Combine(_root, FrameworksPrefix.Replace('/', Path.DirectorySeparatorChar), framework + ".framework");
            if (!Directory.Exists(directory))
                continue;

            foreach (string stub in Directory.EnumerateFiles(directory, "*.tbd", SearchOption.AllDirectories))
            {
                string topLevel = Path.Combine(directory, Path.GetFileName(stub));
                if (File.Exists(topLevel))
                    continue;

                File.Copy(stub, topLevel);
                FileCount++;
                ByteCount += new FileInfo(topLevel).Length;
            }
        }
    }

    private static string CombineRelative(string linkPath, string target)
    {
        int slash = linkPath.LastIndexOf('/');
        string directory = slash < 0 ? string.Empty : linkPath[..slash];
        return directory.Length == 0 ? target : directory + "/" + target;
    }

    private static string Collapse(string path)
    {
        var parts = new List<string>();
        foreach (string part in path.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            if (part == ".")
                continue;
            if (part == "..")
            {
                if (parts.Count > 0)
                    parts.RemoveAt(parts.Count - 1);
                continue;
            }
            parts.Add(part);
        }
        return string.Join('/', parts);
    }

    /// <summary>
    /// Turns <c>./Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/...</c>
    /// into <c>usr/lib/...</c>; returns null for anything outside the SDK tree.
    /// </summary>
    internal static string? ToSdkRelativePath(string name)
    {
        string path = name.Replace('\\', '/');
        while (path.StartsWith("./", StringComparison.Ordinal))
            path = path[2..];

        int sdks = path.IndexOf("/SDKs/", StringComparison.Ordinal);
        if (sdks < 0)
            return null;

        int start = sdks + "/SDKs/".Length;
        int slash = path.IndexOf('/', start);
        if (slash < 0)
            return null;

        string sdkDirectory = path[start..slash];
        if (!sdkDirectory.StartsWith("MacOSX", StringComparison.Ordinal))
            return null;

        return path[(slash + 1)..];
    }

    internal static bool IsWanted(string relative)
    {
        if (relative.Length == 0)
            return false;

        if (relative.StartsWith(IncludePrefix, StringComparison.Ordinal))
            return true;

        if (relative.StartsWith(LibraryPrefix, StringComparison.Ordinal))
            return relative.EndsWith(".tbd", StringComparison.Ordinal);

        if (relative.StartsWith(FrameworksPrefix, StringComparison.Ordinal))
        {
            if (!relative.EndsWith(".tbd", StringComparison.Ordinal))
                return false;

            string rest = relative[FrameworksPrefix.Length..];
            int slash = rest.IndexOf('/');
            if (slash <= 0)
                return false;

            string directory = rest[..slash];
            if (!directory.EndsWith(".framework", StringComparison.Ordinal))
                return false;

            string framework = directory[..^".framework".Length];
            return Frameworks.Contains(framework, StringComparer.Ordinal);
        }

        return false;
    }
}
