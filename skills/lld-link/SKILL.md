---
name: lld-link
description: Use when linking Windows COFF/PE binaries without MSVC (or when a .NET Native AOT Windows build needs lld-link) — turning .obj/.lib into .exe/.dll with MSVC-style switches like /machine:, /libpath:, /entry.
---

# LLD.Link.Toolsets.*

Ships the LLVM `lld-link` (COFF linker) for the current host and exposes its
location as an MSBuild property. **One binary links every COFF architecture** —
choose the target with `/machine:`.

## What you get

| Item | Path / property |
| --- | --- |
| Linker | `tools/lld-link` (`lld-link.exe` on Windows) |
| Windows shims | `tools/lld-link.cmd`, `tools/lld-link.ps1` (Windows packages only) |
| MSBuild properties | `$(LLDLinkToolsetsWinX64Dir)`<br>`$(LLDLinkToolsetsWinArm64Dir)`<br>`$(LLDLinkToolsetsLinuxX64Dir)`<br>`$(LLDLinkToolsetsLinuxArm64Dir)`<br>`$(LLDLinkToolsetsOsxArm64Dir)` |

Each property points at that package's `tools/` directory.

## Direct invocation

```bash
lld-link /machine:arm64 /subsystem:console /entry:main \
  app.obj /out:app.exe \
  /libpath:<XWinStore>/splat/crt/lib/arm64 \
  /libpath:<XWinStore>/splat/sdk/lib/ucrt/arm64 \
  /libpath:<XWinStore>/splat/sdk/lib/um/arm64
```

From MSBuild:

```xml
<Exec Command="&quot;$(LLDLinkToolsetsWinX64Dir)lld-link.exe&quot; /machine:x64 /subsystem:console @(LldArgs, ' ')" />
```

## Notes

- Import libraries come from the `XWin.Store.*` packages
  (`splat/crt/lib/<arch>` and `splat/sdk/lib/{ucrt,um}/<arch>`); see the
  `xwin-store` skill.
- COFF only. For ELF use `zig cc` / `ld.lld`; for Mach-O use Zig or Apple's linker.
- MSVC-style switches (`/machine`, `/entry`, `/libpath`, `/nodefaultlib`) — it is
  **not** a drop-in GNU `ld`.
- Usable outside .NET: reference the package, read the property, invoke the binary.
