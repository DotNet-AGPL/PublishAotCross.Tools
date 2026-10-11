PublishAotCross
---

[![License](docs/badge-license.svg)](LICENSE)

Forked from [MichalStrehovsky/PublishAotCross](https://github.com/MichalStrehovsky/PublishAotCross "")

This is a NuGet package with an MSBuild target to aid in crosscompilation with [PublishAot](https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/). It helps resolving following error:

```sh
$ dotnet publish -r linux-x64
Microsoft.NETCore.Native.Publish.targets(59,5): error : Cross-OS native compilation is not supported.
```

This nuget package allows using [Zig](https://ziglang.org/) as the linker/sysroot to allow crosscompiling to linux-x64/linux-arm64/linux-musl-x64/linux-musl-arm64 from a Windows/Linux/macOS machine, and [xwin](https://github.com/Jake-Shadle/xwin "") to windows-x64/windows-arm64 from Windows, Linux or macOS machine.

The xwin implemetation is based on [Windows10CE's project](https://github.com/Windows10CE/PublishAotCrossXWin/tree/master "")

## Usage

### Typical Cross build

#### Zig

By default it relies on Zig provided by the unofficial [Vezel.Zig.Toolsets](https://github.com/vezel-dev/zig-toolsets) NuGet package. You can specify version of this package using the `ZigVersion` property (current default: `0.17.0.1`). Instructions for using your own Zig binaries are near the end of this document.

If you don't want to use Zig from the Vezel.Zig.Toolsets NuGet package, you can specify `/p:UseExternalZig=true`. This will use whatever Zig is on your PATH. [Download](https://ziglang.org/download/) an archive with Zig for your host machine, extract it and place it on your PATH.

1. Optional: [download](https://releases.llvm.org/) LLVM. We only need llvm-objcopy executable so if you care about size, you can delete the rest. The executable needs to be on PATH - you could copy it next to the Zig executable. This step is optional and is required only to strip symbols (make the produced executables smaller). If you don't care about stripping symbols, you can skip it.

2. To your project that is already using Native AOT, add a reference to `PublishAotCross.Tools`.

3. Publish for one of the newly available RIDs:
    * `dotnet publish -r linux-x64`
    * `dotnet publish -r linux-arm64`
    * `dotnet publish -r linux-musl-x64`
    * `dotnet publish -r linux-musl-arm64`
    * `dotnet publish -r osx-arm64`

    If you skipped the second optional step to download llvm-objcopy, you must also pass `/p:StripSymbols=false` to the publish command, or you'll see an error instructing you to do that.

    You can specify a custom glibc version via `/p:GlibcVersion=<version>` (e.g. `2.35`). This appends the version suffix to the target triple (e.g. `x86_64-linux-gnu.2.35`).

This package also supports Windows-to-Windows Native AOT compilation without Visual Studio C++ tools, using xwin SDK store + lld-link + Zig toolchain.

Cross-compiling to `osx-arm64` from Windows/Linux is supported: the `MacOSX.SDK` package (referenced automatically) supplies a filtered macOS SDK subset, and Zig performs the linking. No macOS machine is required.

#### XWin

The package is self-contained. No manual installation of xwin, lld-link, or Windows SDK is required. Add the package reference and build.

1. To your project that is already using Native AOT, add a reference to this NuGet package.

2. Publish for one of the newly available RIDs:
     * `dotnet publish -c Release -r win-x64`
     * `dotnet publish -c Release -r win-arm64`

#### XWin Store

The Windows SDK/CRT import libraries are provided by two internal NuGet dependencies — all files are pre-packaged inside the `.nupkg`, with **no additional download** during user builds:

| Package | Target Architecture |
|---------|-------------------|
| `XWin.Store.x64` | x64 SDK & CRT import libraries |
| `XWin.Store.arm64` | arm64 SDK & CRT import libraries |

When `dotnet restore` resolves these packages, the import libraries (`splat/crt`, `splat/sdk`) are extracted locally and consumed by `lld-link` during Native AOT — no xwin CLI or network access is needed at build time.

For maintainers: the store is generated using the [xwin](https://github.com/Jake-Shadle/xwin) CLI (`xwin.exe` in `toolsets/`) by running `toolsets/download-xwin-store.ps1` (admin required). This script downloads the official Windows SDK store once and filters it into a lightweight set of import libraries that are then packed into the NuGet package.

- Version defined in `toolsets/ToolsetsVersion.props` via `XWinVersion` property (current: `0.10.0`).
- The xwin CLI itself is not bundled into the NuGet package — it is only used for store generation.

### Use Zig as c compiler on same host

This package auto detects if host and target platforms are different to determine if Zig is used or not. Even though on the same platform, Zig can also be used as the dropped in C Compiler with

```
dotnet publish -r linux-x64 /p:PublishAot=true
```

> `AotPreferCustom` defaults to `true` (xwin + lld-link). Set `-p:AotPreferCustom=false` to use Visual Studio C++ tools.

## Tested Variants

|                    |(Host)Windows x64|Linux GNU x64|Linux GNU arm64|Linux MUSL x64|Linux MUSL arm64|
|--------------------|-----------------|-------------|---------------|--------------|----------------|
|(target)Windows x64 |O                |O            |N/A            |N/A           |N/A             |
|(target)Windows arm64|O                |N/A          |N/A            |N/A           |N/A             |
|Linux GNU x64       |O                |O            |O              |N/A           |N/A             |
|Linux GNU arm64     |O                |O            |O              |N/A           |N/A             |
|Linux MUSL x64      |O                |O            |O              |N/A           |N/A             |
|Linux MUSL arm64    |O                |O            |O              |N/A           |N/A             |

Notes: `N/A` means it might work but not tested. macOS host/target are not tested yet.

