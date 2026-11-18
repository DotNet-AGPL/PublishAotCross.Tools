---
name: xwin-store
description: Use when you need MSVC-compatible Windows CRT/SDK headers or import libraries on a machine without Visual Studio (or on Linux/macOS), or when wiring /vctoolsdir, /winsdkdir and /LIBPATH for clang-cl or lld-link.
---

# XWin.Store.*

A pre-splatted Windows CRT + SDK store (produced with `xwin splat`) packaged so
Windows builds work without installing Visual Studio.

> **Architecture-specific.** `XWin.Store.x64` contains **only x64** import
> libraries; `XWin.Store.arm64` contains **only arm64**. Reference the package
> that matches the **target** architecture.

## Layout

```
tools/.xwin-store/
  splat/crt/include            # MSVC CRT headers
  splat/crt/lib/<arch>/        # libcmt.lib, vcruntime.lib, ...
  splat/sdk/include            # Windows SDK headers (windows.h, ...)
  splat/sdk/lib/ucrt/<arch>/   # ucrt.lib, ...
  splat/sdk/lib/um/<arch>/     # kernel32.lib, user32.lib, ...
```

## MSBuild property

| Package | Property |
| --- | --- |
| `XWin.Store.x64` | `$(XWinStoreX64Dir)` |
| `XWin.Store.arm64` | `$(XWinStoreArm64Dir)` |

## Wiring it into a link

clang-cl and lld-link accept the store directly:

```
/vctoolsdir:<store>/splat/crt
/winsdkdir:<store>/splat/sdk
/LIBPATH:<store>/splat/sdk/lib/ucrt/<arch>/
/LIBPATH:<store>/splat/sdk/lib/um/<arch>/
/LIBPATH:<store>/splat/crt/lib/<arch>/
```

## Notes

- The content is Microsoft's Windows SDK / VC++ Redistributable import
  libraries, used under Microsoft's terms (see `NOTICE`). Build-time linking only.
- No Visual Studio, no administrator rights, no system-wide installation.
- Because the store is per-architecture, a project that targets both x64 and
  arm64 needs both packages.
