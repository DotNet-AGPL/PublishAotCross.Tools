---
name: publishaotcross-tools
description: Use when cross-compiling a .NET Native AOT app to another OS/architecture (e.g. `dotnet publish -r linux-arm64` or `-r osx-arm64` on Windows), when `dotnet publish` fails with "Cross-OS native compilation is not supported", or when one build machine must produce Windows, Linux (glibc/musl) and macOS artifacts without Visual Studio or a Mac.
---

# PublishAotCross.Tools

Supplies the native toolchain for Native AOT cross-compilation so that
`dotnet publish -r <rid>` works from any mainstream host:

- **Windows targets** → xwin SDK store + `lld-link` (no Visual Studio needed).
- **Linux / macOS targets** → Zig (delivered via NuGet) + compiler/linker shims.

## Do this

1. Add the package to a project that already sets `PublishAot=true`:

   ```bash
   dotnet add package PublishAotCross.Tools
   ```

2. List the target RIDs in the project:

   ```xml
   <RuntimeIdentifiers>win-x64;win-arm64;linux-x64;linux-arm64;linux-musl-x64;linux-musl-arm64;osx-arm64</RuntimeIdentifiers>
   ```

3. Publish per RID — nothing else to install or configure:

   ```bash
   dotnet publish -c Release -r linux-x64
   dotnet publish -c Release -r linux-arm64
   dotnet publish -c Release -r linux-musl-x64
   dotnet publish -c Release -r linux-musl-arm64
   dotnet publish -c Release -r osx-arm64
   dotnet publish -c Release -r win-x64
   dotnet publish -c Release -r win-arm64
   ```

## Supported targets

| Target | Output |
| --- | --- |
| `win-x64`, `win-arm64` | PE (via xwin + lld-link) |
| `linux-x64`, `linux-arm64` | ELF, glibc, dynamically linked |
| `linux-musl-x64`, `linux-musl-arm64` | ELF, musl, statically linked |
| `osx-arm64` | Mach-O arm64 |

Hosts: Windows x64/arm64, Linux x64/arm64, macOS arm64. Intel macOS works for
non-Windows targets. **`osx-x64` and 32-bit targets (`win-arm`, arm32) are not supported.**

## Properties

| Property | Purpose |
| --- | --- |
| `/p:GlibcVersion=2.35` | Lower the glibc floor of the Linux output |
| `/p:StripSymbols=false` | Keep symbols inside the executable (also the default for `osx-*` when cross-compiling) |
| `/p:StripSymbols=true` | Strip + `<binary>.dSYM` on macOS targets (a bundled LLVM `dsymutil` + `llvm-objcopy -x` replace Xcode's tools) |
| `/p:AotPreferCustom=false` | Use the system native toolchain instead of the bundled one |
| `/p:PublishAotCrossDebug=false` | Silence the "which toolchain was picked" build message (on by default) |

## Do NOT

- Do **not** set `StripSymbols=false` "to make it work". Stripping already works
  (a bundled multi-format `llvm-objcopy` is used); a `.dbg` file next to the
  executable on Linux is the expected, normal output.
- Do **not** assume a cross-built macOS binary without `StripSymbols=true` is
  debuggable: the linker never writes DWARF into Mach-O, so line info exists only
  inside the `.dSYM`.
- Do **not** install Visual Studio C++ tools or Xcode for cross builds. Xcode is
  only needed when building macOS **natively on macOS**.
- Do **not** try `win-arm` (arm32) — Native AOT does not support it (`NETSDK1203`).

## Pitfalls

- **Visual Studio publish**: set the publish profile's *Target Runtime* to the
  target RID. Left at the host RID, you silently get a host build.
- The first restore pulls roughly 0.9 GB of toolchain packages (Windows SDK
  store, lld-link, Zig, macOS SDK, `dsymutil`). That is expected.
- `linux-musl-*` binaries are static; `linux-*` binaries need a glibc at least
  as new as the configured floor.
- Outputs are unsigned. macOS runs cross-built binaries locally without extra
  signing; Windows may warn about unsigned executables.
- **`StripSymbols` per target** — `win-*`: no-op (PE has no symbol table, ILC skips
  Windows); `linux-*`: stripped via the bundled `llvm-objcopy`, plus `App.dbg` +
  gnu-debuglink when `DebugType != none`; `osx-*` cross: `.dSYM` + `strip -x`
  equivalent; `osx-*` on macOS: Xcode `dsymutil`/`strip` (ILC's native branch).
  Measured on hello-world with `DebugType=portable`: linux 6,283 KB → 1,168 KB +
  4,996 KB `.dbg`; osx cross 1,999 KB → 1,069 KB + 1,537 KB dSYM; win-x64 unchanged.
- **Toggling `StripSymbols` needs a clean build**: when the linked binary is
  up to date, `LinkNative` is skipped and the strip/.dSYM step does not re-run
  (same behaviour as upstream ILC). `rm -rf bin obj` or `-t:Rebuild`.
- **dSYM specifics** (macOS target with `StripSymbols=true`): managed code gets
  full file/line info, but Native AOT *runtime* C++ frames only have symbol names
  (`dsymutil` cannot re-read the runtime `.a` members, 92 expected warnings are
  suppressed). `llvm-objcopy -x` equals Apple `strip -x`: local symbols go away,
  so `image lookup -n <managed method>` stops working; addresses, source
  breakpoints and backtraces still resolve. Line tables embed the build machine's
  absolute paths — remap with `settings set target.source-map` when debugging
  elsewhere, and treat `.dSYM` files as private artifacts. lldb outside macOS does
  not auto-load the bundle, so add it explicitly:
  `target symbols add <binary>.dSYM/Contents/Resources/DWARF/<binary>`.
