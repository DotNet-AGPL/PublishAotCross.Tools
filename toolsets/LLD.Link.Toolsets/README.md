# LLD.Link.Toolsets

**Meta package. It ships no binary itself** — it only references the per-host packages:

| Package | Host | Size (nupkg) |
| --- | --- | --- |
| `LLD.Link.Toolsets.win-x64` | win-x64 | ~28 MB |
| `LLD.Link.Toolsets.win-arm64` | win-arm64 | ~27 MB |
| `LLD.Link.Toolsets.linux-x64` | linux-x64 | ~59 MB |
| `LLD.Link.Toolsets.linux-arm64` | linux-arm64 | ~57 MB |
| `LLD.Link.Toolsets.osx-arm64` | osx-arm64 | ~45 MB |

**LLVM version:** 23.1.5

**Source:** https://github.com/DotNet-AGPL/PublishAotCross.Tools/tree/main/toolsets/LLD.Link.Toolsets

## When to use it

- `PublishAotCross.Tools` depends on this metapackage, because a cross-compilation
  package must contain a linker for every host it supports.
- **A single-platform consumer should reference the matching child instead**
  (`LLD.Link.Toolsets.<host-rid>`). Installing this package pulls ~216 MB of
  linkers for hosts you will never build on.

Nothing is added to `PATH`: `PublishAotCross.Tools` selects the linker by host and
passes `$(CppLinker)` to ILCompiler explicitly.

## License

Apache-2.0. The binutils `lld-link` builds are from the LLVM project and are
licensed under the Apache License, Version 2.0 with LLVM Exceptions — see
https://llvm.org/foundation/relicensing/ for details.
