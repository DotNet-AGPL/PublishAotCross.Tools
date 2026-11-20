using System.Diagnostics;

namespace MacOSX.SDK.Fetch;

/// <summary>
/// Streams the decompressed contents of a <c>.xz</c> file to the caller's stdout pipe.
/// Supports both the official <c>xz</c> tool and 7-Zip's console binaries
/// (<c>7za</c>/<c>7zz</c>/<c>7zzs</c>), which are used as the bundled fallback on
/// hosts without xz (Windows, minimal Linux images).
/// </summary>
internal sealed class XzDecoder : IDisposable
{
    private readonly Process _process;
    private readonly string _commandLine;
    private readonly Task<string> _stderr;

    private XzDecoder(Process process, Stream stdout, string commandLine)
    {
        _process = process;
        Stdout = stdout;
        _commandLine = commandLine;
        _stderr = process.StandardError.ReadToEndAsync();
    }

    public Stream Stdout { get; }

    /// <summary>Locates a decoder: explicit path first, then <c>xz</c>, <c>7zzs</c>, <c>7zz</c>, <c>7za</c>, <c>7z</c>.</summary>
    public static string Locate(string? explicitPath)
    {
        if (!string.IsNullOrEmpty(explicitPath))
        {
            if (File.Exists(explicitPath))
                return Path.GetFullPath(explicitPath);
            throw new FileNotFoundException($"decoder not found: {explicitPath}");
        }

        foreach (string candidate in new[] { "xz", "7zzs", "7zz", "7za", "7z" })
        {
            string? resolved = ResolveOnPath(candidate);
            if (resolved is not null)
                return resolved;
        }

        throw new FileNotFoundException(
            "no xz/7-Zip decoder found on PATH; pass --decoder <path to xz, 7zzs, 7zz or 7za>");
    }

    public static XzDecoder Start(string decoderPath, string xzFile)
    {
        bool isSevenZip = IsSevenZip(decoderPath);

        var startInfo = new ProcessStartInfo(decoderPath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        // 7-Zip needs "x <file> -so" to stream a single-stream archive to stdout;
        // xz has the equivalent "-dc <file>".
        if (isSevenZip)
        {
            startInfo.ArgumentList.Add("x");
            startInfo.ArgumentList.Add(xzFile);
            startInfo.ArgumentList.Add("-so");
            startInfo.ArgumentList.Add("-bd"); // no progress output
        }
        else
        {
            startInfo.ArgumentList.Add("-dc");
            startInfo.ArgumentList.Add(xzFile);
        }

        string commandLine = $"{decoderPath} {string.Join(' ', startInfo.ArgumentList)}";

        var process = new Process { StartInfo = startInfo };
        if (!process.Start())
            throw new InvalidOperationException($"failed to start decoder '{decoderPath}'");

        return new XzDecoder(process, process.StandardOutput.BaseStream, commandLine);
    }

    private static bool IsSevenZip(string path)
    {
        string name = Path.GetFileNameWithoutExtension(path);
        return name.StartsWith("7z", StringComparison.OrdinalIgnoreCase);
    }

    private static string? ResolveOnPath(string name)
    {
        string? pathVariable = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathVariable))
            return null;

        string[] extensions = OperatingSystem.IsWindows() ? new[] { ".exe", ".cmd", ".bat" } : new[] { "" };

        foreach (string directory in pathVariable.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (string extension in extensions)
            {
                string candidate = Path.Combine(directory.Trim('"'), name + extension);
                if (File.Exists(candidate))
                    return candidate;
            }
        }

        return null;
    }

    public void Dispose()
    {
        try
        {
            Stdout.Dispose();
        }
        catch (IOException)
        {
            // ignored: the pipe may already be closed
        }

        if (!_process.WaitForExit(30_000))
        {
            try { _process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            _process.Dispose();
            throw new TimeoutException($"decoder did not exit: {_commandLine}");
        }

        int exitCode = _process.ExitCode;
        string stderr = _stderr.GetAwaiter().GetResult();
        _process.Dispose();

        if (exitCode != 0)
            throw new InvalidOperationException(
                $"decoder failed with exit code {exitCode}: {_commandLine}{Environment.NewLine}{stderr}");
    }
}
