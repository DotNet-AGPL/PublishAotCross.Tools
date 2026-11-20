# XWin.Store

**Meta package. It ships no binary itself** — it only references the per-architecture
packages:

| Package | Architecture | Size (nupkg) |
| --- | --- | --- |
| `XWin.Store.x64` | x64 | ~100 MB |
| `XWin.Store.arm64` | arm64 | ~152 MB |

**xwin version:** 0.10.0 (Windows SDK store, produced by `toolsets/download-xwin-store.ps1`)

**Source:** https://github.com/DotNet-AGPL/PublishAotCross.Tools/tree/main/toolsets/XWin.Store

## When to use it

- `PublishAotCross.Tools` depends on this metapackage: it contains the import
  libraries for both Windows architectures it can target.
- A consumer that only ever targets one architecture can reference
  `XWin.Store.x64` or `XWin.Store.arm64` directly and skip ~150 MB.

Each child package sets `XWinStoreX64Dir` / `XWinStoreArm64Dir` via
`buildTransitive`; `PublishAotCross.Tools` picks the store that matches the target RID.

## License

Apache-2.0 for this packaging. The bundled Windows SDK/CRT import libraries are
Microsoft redistributables — see `NOTICE` and the Windows SDK license terms.
