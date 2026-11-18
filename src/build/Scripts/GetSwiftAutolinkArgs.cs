// Replays Swift autolink entries (Mach-O LC_LINKER_OPTION) found in the native
// static libraries NativeAOT links. Zig's Mach-O linker does not process these
// load commands, so Swift runtime libraries (libswiftCore, libswiftFoundation,
// ...) never get pulled in and __swift_FORCE_LOAD_$_swift* stays undefined for
// any library that goes through TLS/X509 (Apple Crypto).
//
// Rather than hard-coding a module list (which drifts with SDK/.NET versions and
// misses modules referenced only by some code paths), we scan the actual link
// inputs and replay what Apple's ld64 would have expanded. Entries are filtered
// to libraries/frameworks that exist in the macOS SDK so we never emit a
// reference the linker cannot resolve. Combined with -dead_strip_dylibs, any
// replayed entry that is not actually used is dropped from the final binary.

var results = new List<string>();
var seen = new HashSet<string>(StringComparer.Ordinal);
bool sdkProvided = !string.IsNullOrEmpty(MacOSXSDKDir);

void AddArg(string a)
{
    if (!string.IsNullOrEmpty(a) && seen.Add(a))
        results.Add(a);
}

bool SwiftLibExists(string name)
{
    if (!sdkProvided)
        return true;

    string swiftDir = Path.Combine(MacOSXSDKDir, "usr", "lib", "swift");
    string libDir = Path.Combine(MacOSXSDKDir, "usr", "lib");
    string tbd = "lib" + name + ".tbd";
    string dylib = "lib" + name + ".dylib";

    return File.Exists(Path.Combine(swiftDir, tbd))
        || File.Exists(Path.Combine(swiftDir, dylib))
        || File.Exists(Path.Combine(libDir, tbd))
        || File.Exists(Path.Combine(libDir, dylib));
}

bool FrameworkExists(string name)
{
    if (!sdkProvided)
        return false;

    foreach (string rel in new[] { "System/Library/Frameworks", "System/Library/PrivateFrameworks" })
    {
        string fw = Path.Combine(
            MacOSXSDKDir,
            rel.Replace('/', Path.DirectorySeparatorChar),
            name + ".framework");

        if (File.Exists(Path.Combine(fw, name + ".tbd")) || File.Exists(Path.Combine(fw, name)))
            return true;
    }

    return false;
}

uint U32(byte[] b, long o)
{
    return (uint)(b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24));
}

uint U32BE(byte[] b, long o)
{
    return (uint)((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);
}

void HandleTokens(List<string> toks)
{
    for (int ti = 0; ti < toks.Count; ti++)
    {
        string t = toks[ti];

        if (t == "-framework")
        {
            if (ti + 1 < toks.Count)
            {
                string name = toks[++ti];
                if (FrameworkExists(name))
                    AddArg("-framework " + name);
                else
                    Log.LogMessage(MessageImportance.Low, "PublishAotCross: skipping autolink framework not present in SDK: " + name);
            }
        }
        else if (t.StartsWith("-l") && t.Length > 2)
        {
            string lib = t.Substring(2);
            if (SwiftLibExists(lib))
                AddArg(t);
            else
                Log.LogMessage(MessageImportance.Low, "PublishAotCross: skipping autolink library not present in SDK: " + lib);
        }
    }
}

void ParseMachO(byte[] b, long off, long limit)
{
    if (off + 4 > limit)
        return;

    uint magic = U32(b, off);
    bool is64 = magic == 0xfeedfacf;
    if (!is64 && magic != 0xfeedface)
        return;

    if (off + 24 > limit)
        return;

    uint ncmds = U32(b, off + 16);
    long p = off + (is64 ? 32 : 28);

    for (uint i = 0; i < ncmds; i++)
    {
        if (p + 8 > limit)
            break;

        uint cmd = U32(b, p);
        uint cmdsize = U32(b, p + 4);
        if (cmdsize < 8 || p + cmdsize > limit)
            break;

        if (cmd == 0x2D) // LC_LINKER_OPTION
        {
            uint count = U32(b, p + 8);
            long q = p + 12;
            var toks = new List<string>();

            for (uint k = 0; k < count && q < p + cmdsize; k++)
            {
                long s = q, e = q;
                while (e < p + cmdsize && b[e] != 0)
                    e++;
                if (e > s)
                    toks.Add(Encoding.ASCII.GetString(b, (int)s, (int)(e - s)));
                q = e + 1;
            }

            HandleTokens(toks);
        }

        p += cmdsize;
    }
}

void ParseMember(byte[] b, long off, long size)
{
    if (size < 4 || off < 0 || off + size > b.Length)
        return;

    long limit = off + size;
    uint m = U32(b, off);

    if (m == 0xfeedfacf || m == 0xfeedface)
    {
        ParseMachO(b, off, limit);
        return;
    }

    if (U32BE(b, off) == 0xcafebabe)
    {
        uint n = U32BE(b, off + 4);
        for (uint i = 0; i < n; i++)
        {
            long a = off + 8 + (long)i * 20;
            if (a + 20 > limit)
                break;

            uint o = U32BE(b, a + 8);
            uint s = U32BE(b, a + 12);
            ParseMember(b, off + o, s);
        }
    }
}

void ParseFile(string path)
{
    byte[] b;
    try
    {
        b = File.ReadAllBytes(path);
    }
    catch (Exception ex)
    {
        Log.LogMessage(MessageImportance.Low, "PublishAotCross: cannot read " + path + ": " + ex.Message);
        return;
    }

    // Cheap filter: only archives that mention Swift can carry Swift autolink.
    bool maybeSwift = false;
    for (int i = 0; i + 5 <= b.Length; i++)
    {
        if (b[i] == (byte)'s' && b[i + 1] == (byte)'w' && b[i + 2] == (byte)'i' && b[i + 3] == (byte)'f' && b[i + 4] == (byte)'t')
        {
            maybeSwift = true;
            break;
        }
    }

    if (!maybeSwift)
        return;

    if (b.Length >= 8 && b[0] == (byte)'!' && b[1] == (byte)'<' && b[2] == (byte)'a')
    {
        // Unix ar archive.
        long pos = 8;
        while (pos + 60 <= b.Length)
        {
            string name = Encoding.ASCII.GetString(b, (int)pos, 16).Trim();
            string szs = Encoding.ASCII.GetString(b, (int)(pos + 48), 10).Trim();

            long size;
            if (!long.TryParse(szs, out size) || size < 0)
                break;

            long data = pos + 60;
            long dataSize = size;

            // BSD-style extended name: "#1/<len>" preceding the real name.
            if (name.StartsWith("#1/"))
            {
                int nlen;
                if (int.TryParse(name.Substring(3), out nlen) && nlen <= dataSize)
                {
                    data += nlen;
                    dataSize -= nlen;
                }
            }

            ParseMember(b, data, dataSize);

            pos = data + dataSize;
            if ((size & 1) == 1)
                pos++;
        }
    }
    else
    {
        ParseMember(b, 0, b.Length);
    }
}

if (NativeLibraries != null)
{
    foreach (var item in NativeLibraries)
    {
        string path = item.ItemSpec;
        if (path == null)
            continue;

        path = path.Trim();
        if (path.Length >= 2 && path[0] == '"' && path[path.Length - 1] == '"')
            path = path.Substring(1, path.Length - 2);

        if (!File.Exists(path))
            continue;

        ParseFile(path);
    }
}

var outItems = new ITaskItem[results.Count];
for (int i = 0; i < results.Count; i++)
    outItems[i] = new TaskItem(results[i]);

LinkerArgs = outItems;

if (PublishAotCrossDebug)
    Log.LogMessage(MessageImportance.High, "PublishAotCross: replayed Swift autolink args: " + string.Join(" ", results.ToArray()));
