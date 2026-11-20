# MacOSX.SDK

Filtered macOS SDK subset for cross-compiling Native AOT to **osx-arm64** from
non-macOS hosts (Windows/Linux).

The content is extracted from Apple's **Command Line Tools** package, which Apple
serves from its public software-update CDN (`swcdn.apple.com`) — no Apple ID, no
Mac and no Xcode required. Only the parts Native AOT linking needs are kept:

- `usr/include/**`
- `usr/lib/**/*.tbd` (libSystem, libobjc, libicucore, ...)
- `usr/lib/swift/**/*.tbd` (libswiftCore, libswiftFoundation, ...)
- `System/Library/Frameworks/{CoreFoundation,Foundation,Security,Network,GSS,CryptoKit,CFNetwork,Combine,CoreServices,DiskArbitration,IOKit,LocalAuthentication}.framework/**/*.tbd`

Framework stubs are stored as symbolic links inside the SDK
(`Foo.framework/Foo.tbd -> Versions/Current/Foo.tbd`); the extractor materializes
them as regular files because the linker probes the top-level path and Windows
cannot create symlinks reliably.

## Usage

This package is automatically referenced by `PublishAotCross.Tools` and sets the
`MacOSXSDKDir` MSBuild property (via `buildTransitive/`). No manual action is
required.

To use a complete macOS SDK instead (e.g. to get more frameworks), set
`MacOSXSDKDir` (or the `MACOSX_SDK` environment variable) to a full SDK root.

## Regenerating the content

```
pwsh toolsets/download-macosx-sdk.ps1 -AcceptLicense
dotnet pack toolsets/MacOSX.SDK/MacOSX.SDK.nuproj -o artifacts --force
```

The script pins the CLT package URL and SHA256, keeps a copy under
`toolsets/.pkg-cache/` and delegates the container parsing to
`toolsets/MacOSX.SDK.Fetch` (xar → pbzx → cpio). Pass `-PackagePath` to work
fully offline from a previously downloaded `.pkg`.

## License

The SDK content itself is subject to Apple's Xcode license terms:
https://www.apple.com/legal/sla/docs/xcode.pdf

This NuGet packaging metadata is Apache-2.0.
