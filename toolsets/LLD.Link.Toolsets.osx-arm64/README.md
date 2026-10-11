# LLD.Link.Toolsets.osx-arm64

lld-link (LLD COFF linker) for osx-arm64 host platform.
MSVC-compatible linker used for NativeAOT cross-compilation.
Bundled in NuGet package - no manual installation required.

**LLVM version:** 23.1.3

**Source:** https://github.com/DotNet-AGPL/PublishAotCross.Tools/tree/main/toolsets/LLD.Link.Toolsets.osx-arm64

**Contents:**
- `tools/lld-link` — LLVM LLD COFF linker (MSVC-compatible)

**License:** Apache-2.0 (lld-link binary: Apache-2.0 WITH LLVM-exception, see LICENSE)

## MSBuild Integration

This package automatically sets the `LLDLinkToolsetsOsxArm64Dir` MSBuild property
to the path of the extracted `lld-link` binary. It is available to the consuming
project and its transitive dependents via `buildTransitive/` import.
