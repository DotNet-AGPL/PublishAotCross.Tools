# MacOSX.SDK

Filtered macOS SDK subset for cross-compiling Native AOT to **osx-arm64** from
non-macOS hosts (Windows/Linux).

Packaged from [joseluisq/macosx-sdks](https://github.com/joseluisq/macosx-sdks),
which packages the SDK from Apple Xcode. Only the parts Native AOT linking needs
are included:

- `usr/include/**`
- `usr/lib/**/*.tbd` (libSystem, libobjc, libicucore, ...)
- `usr/lib/swift/**/*.tbd` (libswiftCore, libswiftFoundation, ...)
- `System/Library/Frameworks/{CoreFoundation,Foundation,Security,Network,GSS,CryptoKit}.framework/**/*.tbd`

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

## License

The SDK content itself is subject to Apple's Xcode license terms:
https://www.apple.com/legal/sla/docs/xcode.pdf

This NuGet packaging metadata is Apache-2.0.
