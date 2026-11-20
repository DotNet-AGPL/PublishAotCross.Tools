using System.Diagnostics;
using System.Security.Cryptography;

namespace MacOSX.SDK.Fetch;

internal static class Program
{
    private const string DefaultPackageUrl =
        "https://swcdn.apple.com/content/downloads/53/49/142-50405-A_WOBLDDXP4W/wk3d2yw94ir1jieuddcu9b9tffxrb09bq8/CLTools_macOSNMOS_SDK.pkg";

    private static int Main(string[] args)
    {
        Options? options = Options.Parse(args);
        if (options is null)
        {
            Options.PrintUsage();
            return 2;
        }

        if (!options.AcceptLicense)
        {
            Console.Error.WriteLine("The macOS SDK is subject to Apple's Xcode license terms:");
            Console.Error.WriteLine("  https://www.apple.com/legal/sla/docs/xcode.pdf");
            Console.Error.WriteLine("Re-run with --accept-license to confirm you accept them.");
            return 1;
        }

        var total = Stopwatch.StartNew();

        try
        {
            (string packagePath, bool temporary) = EnsurePackage(options);
            Console.WriteLine($"package   : {packagePath} ({new FileInfo(packagePath).Length / (1024 * 1024)} MB)");

            try
            {
                Extract(packagePath, options);
            }
            finally
            {
                if (temporary && File.Exists(packagePath))
                    File.Delete(packagePath);
            }

            Console.WriteLine($"done      : {total.Elapsed.TotalSeconds:F1}s");
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"error: {exception.Message}");
            if (options.Verbose)
                Console.Error.WriteLine(exception);
            return 1;
        }
    }

    private static (string Path, bool Temporary) EnsurePackage(Options options)
    {
        string source = options.Package ?? DefaultPackageUrl;

        if (!source.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
            !source.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            if (!File.Exists(source))
                throw new FileNotFoundException($"package not found: {source}");

            if (options.Sha256 is not null)
                VerifySha256(source, options.Sha256);

            return (Path.GetFullPath(source), false);
        }

        bool temporary = options.KeepPackage is null;
        string target = options.KeepPackage
            ?? Path.Combine(Path.GetTempPath(), $"macosx-sdk-{options.SdkVersion}-{Guid.NewGuid():N}.pkg");

        if (!temporary && File.Exists(target) && options.Sha256 is not null)
        {
            if (string.Equals(ComputeSha256(target), options.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine($"download  : cached ({Path.GetFileName(target)})");
                return (target, false);
            }

            File.Delete(target);
        }

        var download = Stopwatch.StartNew();
        Download(source, target);
        Console.WriteLine($"download  : {download.Elapsed.TotalSeconds:F1}s");

        if (options.Sha256 is not null)
            VerifySha256(target, options.Sha256);

        return (target, temporary);
    }

    private static void Download(string url, string destination)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PublishAotCross.MacOSXSDK.Fetch/1.0");

        using HttpResponseMessage response = client.Send(
            new HttpRequestMessage(HttpMethod.Get, url), HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        long? total = response.Content.Headers.ContentLength;
        long copied = 0;
        long nextReport = 0;

        using Stream source = response.Content.ReadAsStream();
        using FileStream file = File.Create(destination);

        byte[] buffer = new byte[1 << 20];
        int read;
        while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
        {
            file.Write(buffer, 0, read);
            copied += read;

            if (copied >= nextReport)
            {
                string progress = total is null
                    ? $"{copied / (1024 * 1024)} MB"
                    : $"{copied * 100 / total.Value}% ({copied / (1024 * 1024)}/{total.Value / (1024 * 1024)} MB)";
                Console.WriteLine($"  {progress}");
                nextReport = copied + 16L * 1024 * 1024;
            }
        }
    }

    private static void VerifySha256(string path, string expected)
    {
        string actual = ComputeSha256(path);
        if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException(
                $"SHA256 mismatch for {path}:{Environment.NewLine}  expected {expected}{Environment.NewLine}  actual   {actual}");
    }

    private static string ComputeSha256(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static void Extract(string packagePath, Options options)
    {
        string payloadFile = Path.Combine(Path.GetTempPath(), $"macosx-sdk-payload-{Guid.NewGuid():N}.xz");

        try
        {
            using FileStream package = File.OpenRead(packagePath);
            XarArchive archive = XarArchive.Open(package);
            (long offset, long size) = archive.FindFile("Payload");
            long absoluteOffset = archive.HeapOffset + offset;
            Console.WriteLine($"xar       : payload at {absoluteOffset} ({size / (1024 * 1024)} MB)");

            var payloadTimer = Stopwatch.StartNew();
            PayloadInfo payload = PbzxExtractor.Extract(package, absoluteOffset, size, payloadFile);
            Console.WriteLine(
                $"pbzx      : {payload.Chunks} chunk(s), {payload.UncompressedBytes / (1024 * 1024)} MB uncompressed ({payloadTimer.Elapsed.TotalSeconds:F1}s)");

            PrepareOutput(options.Output);

            var builder = new SdkSubsetBuilder(options.Output, options.Trace);
            var extractTimer = Stopwatch.StartNew();
            long consumed;

            if (payload.Kind == PayloadKind.RawCpio)
            {
                using FileStream raw = File.OpenRead(payloadFile);
                using var counter = new CountingStream(raw);
                Walk(counter, builder);
                consumed = counter.BytesRead;
            }
            else
            {
                string decoder = XzDecoder.Locate(options.Decoder);
                Console.WriteLine($"decoder   : {decoder}");

                using XzDecoder process = XzDecoder.Start(decoder, payloadFile);
                using var counter = new CountingStream(process.Stdout);
                Walk(counter, builder);
                consumed = counter.BytesRead;

                if (payload.UncompressedBytes > 0 && consumed != payload.UncompressedBytes)
                    throw new InvalidDataException(
                        $"decompressed {consumed} bytes but the payload header declared {payload.UncompressedBytes}");
            }

            builder.Finish();

            Console.WriteLine($"cpio      : {consumed / (1024 * 1024)} MB parsed ({extractTimer.Elapsed.TotalSeconds:F1}s)");
            Console.WriteLine(
                $"sdk       : MacOSX{options.SdkVersion}.sdk -> {builder.FileCount} files, {builder.ByteCount / (1024 * 1024)} MB");

            if (builder.SkippedSymlinks > 0)
            {
                Console.WriteLine($"note      : {builder.SkippedSymlinks} unresolved symlink(s) ignored");

                if (options.Verbose)
                {
                    foreach ((string path, string target) in builder.Unresolved.Take(20))
                        Console.WriteLine($"            {path} -> {target}");
                }
            }

            string libSystem = Path.Combine(options.Output, "usr", "lib", "libSystem.tbd");
            if (!File.Exists(libSystem))
                throw new InvalidDataException($"extraction looks incomplete: {libSystem} is missing");
        }
        finally
        {
            if (File.Exists(payloadFile))
                File.Delete(payloadFile);
        }
    }

    private static void Walk(Stream cpio, SdkSubsetBuilder builder)
    {
        var reader = new OdcCpioReader(cpio);
        while (reader.TryRead(out CpioEntry entry))
            builder.Add(entry, reader);
    }

    private static void PrepareOutput(string output)
    {
        if (Directory.Exists(output))
        {
            Console.WriteLine($"clean     : {output}");
            Directory.Delete(output, recursive: true);
        }

        Directory.CreateDirectory(output);
    }

    private sealed class CountingStream : Stream
    {
        private readonly Stream _inner;

        public CountingStream(Stream inner) => _inner = inner;

        public long BytesRead { get; private set; }

        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => BytesRead;
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            int read = _inner.Read(buffer, offset, count);
            BytesRead += read;
            return read;
        }

        public override int Read(Span<byte> buffer)
        {
            int read = _inner.Read(buffer);
            BytesRead += read;
            return read;
        }

        public override void Flush() { }

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                _inner.Dispose();
            base.Dispose(disposing);
        }
    }

    private sealed class Options
    {
        public string? Package { get; private set; }

        public string Output { get; private set; } = string.Empty;

        public string SdkVersion { get; private set; } = "27.2";

        public string? Sha256 { get; private set; }

        public string? Decoder { get; private set; }

        public string? KeepPackage { get; private set; }

        public bool AcceptLicense { get; private set; }

        public bool Verbose { get; private set; }

        public string? Trace { get; private set; }

        public static Options? Parse(string[] args)
        {
            var options = new Options();

            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--package" when i + 1 < args.Length: options.Package = args[++i]; break;
                    case "--out" when i + 1 < args.Length: options.Output = args[++i]; break;
                    case "--version" when i + 1 < args.Length: options.SdkVersion = args[++i]; break;
                    case "--sha256" when i + 1 < args.Length: options.Sha256 = args[++i].ToLowerInvariant(); break;
                    case "--decoder" when i + 1 < args.Length: options.Decoder = args[++i]; break;
                    case "--keep-package" when i + 1 < args.Length: options.KeepPackage = args[++i]; break;
                    case "--accept-license": options.AcceptLicense = true; break;
                    case "--verbose": options.Verbose = true; break;
                    case "--trace" when i + 1 < args.Length: options.Trace = args[++i]; break;
                    case "--help" or "-h": return null;
                    default:
                        Console.Error.WriteLine($"unknown argument: {args[i]}");
                        return null;
                }
            }

            if (string.IsNullOrEmpty(options.Output))
            {
                Console.Error.WriteLine("--out is required");
                return null;
            }

            return options;
        }

        public static void PrintUsage()
        {
            Console.WriteLine("""
                MacOSX.SDK.Fetch - extract the macOS SDK subset from Apple's Command Line Tools package.

                Usage:
                  MacOSX.SDK.Fetch --out <dir> [options]

                Options:
                  --package <path|url>   .pkg to read (default: the pinned CLT 27.2 SDK package)
                  --out <dir>            destination directory (recreated)
                  --version <x.y>        SDK version, used for messages and validation (default: 27.2)
                  --sha256 <hex>         verify the package hash before extracting
                  --decoder <path>       xz / 7zzs / 7zz / 7za binary (default: probe PATH)
                  --keep-package <path>  keep the downloaded .pkg at this path
                  --accept-license       confirm the Apple Xcode license
                  --verbose              print exception details
                """);
        }
    }
}
