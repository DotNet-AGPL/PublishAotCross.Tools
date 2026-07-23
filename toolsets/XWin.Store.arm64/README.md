# XWin.Store.arm64

Windows arm64 SDK store for NativeAOT cross-compilation.
Bundles pre-downloaded CRT, UCRT, and Win32 API import libraries.
Used by `Fallenwood.PublishAotCross.Extensions`. No manual download required.

**xwin version:** 0.9.0 (Windows SDK 10.0.22621)

**Source:** https://github.com/DotNet-AGPL/Fallenwood.PublishAotCross.Extensions/tree/main/toolsets/XWin.Store.arm64

**License:** MIT

## Disclaimer

This package redistributes necessary Windows SDK & CRT import libraries
(arm64 arch) sourced from Microsoft's official distributions. By using this
package, you agree to comply with Microsoft's respective SDK and Visual C++
Redistributable Licenses. This package is provided for build-time linking
convenience only; it does not grant additional redistribution rights.

In CI/CD environments, this package is consumed via standard NuGet restore
without modification. The libraries are used solely for build-time linking
and are not extracted or redistributed as part of the build output beyond
what is necessary for NativeAOT compilation.

## Origin

The SDK store in this package was downloaded from Microsoft's official
Windows SDK (version 10.0.22621) using [xwin](https://github.com/Jake-Shadle/xwin)
v0.9.0, then filtered for NativeAOT cross-compilation use.

xwin is an open-source tool that downloads and manages Windows SDK/CRT
files. Its source code and license are available at:
https://github.com/Jake-Shadle/xwin
