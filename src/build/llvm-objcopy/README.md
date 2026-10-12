# Bundled `llvm-objcopy`

Multi-format `objcopy` used by the Native AOT symbol-strip step when building
with the bundled Zig toolchain.

`<host-rid>/llvm-objcopy[.exe]` is prepended to `PATH` by `Scripts/SetPath.cs`,
so ILCompiler's probe in `Microsoft.NETCore.Native.Unix.targets` finds
`llvm-objcopy` (which it prefers over the host's binutils `objcopy`). The host's
`objcopy` is single-format and fails on binaries built for another architecture
(e.g. an aarch64 ELF on an x64 host), while `llvm-objcopy` handles every format.

When no `llvm-objcopy` is available (unsupported host, or the binary is missing)
the `../objcopy` shim takes over: it strips on a best-effort basis and never
fails the build.

## Directories

| Directory     | Host                 | Notes                                             |
| ------------- | -------------------- | ------------------------------------------------- |
| `win-x64/`    | Windows x64          |                                                   |
| `win-arm64/`  | Windows arm64        | x64 build; runs via emulation (see `SetPath.cs`)  |
| `linux-x64/`  | Linux x64            |                                                   |
| `linux-arm64/`| Linux arm64          |                                                   |
| `osx-arm64/`  | macOS arm64          |                                                   |

These binaries are **committed on purpose** so that CI and `dotnet pack` need no
GB-sized downloads. Regenerate them with `src/download-llvm-objcopy.ps1`, which
extracts a single file (`bin/llvm-objcopy`) from the official LLVM release
assets (version in `../../toolsets/ToolsetsVersion.props` → `LLDVersion`).
