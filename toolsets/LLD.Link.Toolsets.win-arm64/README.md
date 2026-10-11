# LLD.Link.Toolsets.win-arm64

lld-link (LLD COFF linker) for win-arm64 host platform.
MSVC-compatible linker used for NativeAOT cross-compilation.
Bundled in NuGet package - no manual installation required.

**LLVM version:** 23.1.3

**Source:** https://github.com/DotNet-AGPL/PublishAotCross.Tools/tree/main/toolsets/LLD.Link.Toolsets.win-arm64

**Contents:**
- `tools/lld-link.exe` — LLVM LLD COFF linker (MSVC-compatible)

**License:** Apache-2.0 (lld-link binary: Apache-2.0 WITH LLVM-exception, see LICENSE)

## MSBuild Integration

This package automatically sets the `LLDLinkToolsetsWinArm64Dir` MSBuild property
to the path of the extracted `lld-link` binary. It is available to the consuming
project and its transitive dependents via `buildTransitive/` import.

## Disclaimer

This package redistributes the `lld-link` binary from the LLVM project
(LLVM 23.1.3). By using this package, you agree to comply with the
Apache License, Version 2.0 WITH LLVM-exception.

## Origin

The `lld-link` binary in this package was extracted from the official
LLVM 23.1.3 release (`clang+llvm-23.1.3-aarch64-pc-windows-msvc.tar.xz`).
Source: https://github.com/llvm/llvm-project
