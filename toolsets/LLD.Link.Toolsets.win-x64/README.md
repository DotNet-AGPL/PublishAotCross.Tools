# LLD.Link.Toolsets.win-x64

lld-link (LLD COFF linker) for win-x64 host platform.
MSVC-compatible linker used for NativeAOT cross-compilation.
Bundled in NuGet package - no manual installation required.

**LLVM version:** 22.1.8

**Source:** https://github.com/DotNet-AGPL/Fallenwood.PublishAotCross.Extensions/tree/main/toolsets/LLD.Link.Toolsets.win-x64

**Contents:**
- `tools/lld-link.exe` — LLVM LLD COFF linker (MSVC-compatible)

**License:** MIT (lld-link binary is Apache-2.0 WITH LLVM-exception, see LICENSE)

## Disclaimer

This package redistributes the `lld-link` binary from the LLVM project
(LLVM 22.1.8). By using this package, you agree to comply with the
Apache License, Version 2.0 WITH LLVM-exception.

## Origin

The `lld-link` binary in this package was extracted from the official
LLVM 22.1.8 release (`LLVM-22.1.8-win64.exe`).
Source: https://github.com/llvm/llvm-project
