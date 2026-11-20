# MacOSX.Symbols.Toolsets

**LLVM `dsymutil` for non-macOS hosts. It is a tool package, not a symbols package: it
ships no debug information.**

When Native AOT is cross-compiled to macOS on a Windows or Linux host, the linked
Mach-O contains *no* DWARF at all — the linker only records an `N_OSO` debug map, so
even a non-stripped binary has no file names or line numbers. Turning that debug map
back into a `.dSYM` bundle is exactly what `dsymutil` does, and there is no alternative
tool for it (verified: linking the same object with `-g` still yields zero compile
units in the executable).

Apple's `dsymutil` lives in Xcode and cannot be redistributed, so these packages bundle
the LLVM upstream build for every supported host.

**LLVM version:** 23.1.5

**Source:** https://github.com/DotNet-AGPL/PublishAotCross.Tools/tree/main/toolsets/MacOSX.Symbols.Toolsets

## Packages

| Package | Host | Binary | Size (nupkg) |
| --- | --- | --- | --- |
| `MacOSX.Symbols.Toolsets` | meta package | references all four below | ~100 MB total |
| `MacOSX.Symbols.Toolsets.win-x64` | win-x64 | `tools/dsymutil.exe` | ~19 MB |
| `MacOSX.Symbols.Toolsets.win-arm64` | win-arm64 | `tools/dsymutil.exe` | ~19 MB |
| `MacOSX.Symbols.Toolsets.linux-x64` | linux-x64 | `tools/dsymutil` (stripped) | ~30 MB |
| `MacOSX.Symbols.Toolsets.linux-arm64` | linux-arm64 | `tools/dsymutil` (stripped) | ~30 MB |

macOS hosts are not covered on purpose: Xcode already provides `dsymutil` and `strip`.

## MSBuild integration

Each per-host package sets a property with the directory containing the binary:

```xml
<MacOSXSymbolsToolsetsWinX64Dir>…/tools/</MacOSXSymbolsToolsetsWinX64Dir>
<MacOSXSymbolsToolsetsWinArm64Dir>…/tools/</MacOSXSymbolsToolsetsWinArm64Dir>
<MacOSXSymbolsToolsetsLinuxX64Dir>…/tools/</MacOSXSymbolsToolsetsLinuxX64Dir>
<MacOSXSymbolsToolsetsLinuxArm64Dir>…/tools/</MacOSXSymbolsToolsetsLinuxArm64Dir>
```

`PublishAotCross.Tools` picks the one matching the host and, for macOS targets on a
non-macOS host, runs the equivalent of ILCompiler's native Apple step
(`dsymutil … && strip -no_code_signature_warning -x …`). This is **on by default**
(`StripSymbols` defaults to `true`, like a native macOS build); `/p:StripSymbols=false`
turns it off:

1. `dsymutil --quiet <binary>` → `<binary>.dSYM` next to the executable;
2. `llvm-objcopy -x <binary>` → drop local symbols (`-x` = Apple `strip -x`, which keeps
   every external symbol), 2.0 MB → 1.1 MB on a hello-world app.

Nothing is added to `PATH`, so the system `strip` is never shadowed.

## Usage

`PublishAotCross.Tools` already depends on the per-host packages, so no manual reference
is needed. Only when you use this package standalone:

```xml
<PackageReference Include="MacOSX.Symbols.Toolsets.win-x64" Version="23.1.5.*" PrivateAssets="all" />
```

## Known limitations

- **Runtime C++ frames have no source lines.** `dsymutil` cannot re-read the runtime's
  `libRuntime.WorkstationGC.a(member)` / `libbootstrapper.o` objects through the debug
  map path format written by the linker (92 warnings, suppressed by
  `IgnoreStandardErrorWarningFormat`). Managed code — your application — is complete:
  3,782 subprograms / 19,427 line-table rows for a hello-world app.
- **Line tables carry absolute build-machine paths** (`E:\…\Program.cs`). Add
  `settings set target.source-map <build-path> <local-path>` on macOS if sources are
  elsewhere, and do not treat a `.dSYM` as a publishable artifact.
- After `llvm-objcopy -x`, `image lookup -n <managed method>` no longer resolves (name
  lookup uses the symbol table). Address lookups, source breakpoints and backtraces work
  from DWARF.
- lldb outside macOS does not auto-load the bundle: use
  `target symbols add <bin>.dSYM/Contents/Resources/DWARF/<bin>`. macOS finds it by UUID.

## License

Apache-2.0. The bundled `dsymutil` binaries are from the LLVM project and are licensed
under the Apache License, Version 2.0 with LLVM Exceptions — see `LICENSE` and
https://llvm.org/foundation/relicensing/ for details.

## Origin

Produced by `toolsets/download-macosx-symbols.ps1`, which extracts `bin/dsymutil` from
the official LLVM 23.1.5 release archives and strips the Linux builds with the bundled
`llvm-objcopy`.
