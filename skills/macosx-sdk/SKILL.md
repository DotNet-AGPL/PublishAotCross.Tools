---
name: macosx-sdk
description: Use when cross-compiling or linking Mach-O for macOS without a Mac (for example Zig or clang targeting osx-arm64 from Windows/Linux), when the linker cannot find Apple frameworks or libSystem, or when you need a filtered macOS SDK sysroot on a non-macOS host.
---

# MacOSX.SDK

A filtered macOS SDK subset (extracted from Apple's Command Line Tools package,
which Apple serves from its public software-update CDN) packaged so you can
**link osx-arm64 binaries on Windows or Linux**.

## Contents

```
tools/.macosx-sdk/
  usr/include/**                       # C/C++ headers
  usr/lib/**/*.tbd                     # libSystem etc. (text-based stubs)
  usr/lib/swift/**/*.tbd               # Swift runtime stubs (libswiftCore, ...)
  System/Library/Frameworks/<Framework>.framework/**.tbd
```

Frameworks included (12):

- Linked explicitly by Native AOT: `CoreFoundation`, `Foundation`, `Security`,
  `Network`, `GSS`, `CryptoKit`.
- Autolinked by the shipped .NET native libraries (e.g. Apple Crypto), which the
  Zig linker does not expand: `CFNetwork`, `Combine`, `CoreServices`,
  `DiskArbitration`, `IOKit`, `LocalAuthentication`.

There is **no** `System/Library/PrivateFrameworks` and no real `.dylib` —
`.tbd` stubs are sufficient for linking.

## MSBuild property

`$(MacOSXSDKDir)` → the SDK root (set automatically by this package).

## Using it with Zig / clang

Zig does **not** derive framework or library search paths from `-isysroot`, so
pass them explicitly:

```
-isysroot <sdk>
-F <sdk>/System/Library/Frameworks
-F <sdk>/System/Library/PrivateFrameworks
-L <sdk>/usr/lib
-L <sdk>/usr/lib/swift
```

## Notes

- Content is subject to Apple's Xcode license (see `NOTICE`); the package
  requires license acceptance. Do not redistribute the SDK itself.
- Warnings such as `unable to open library directory "/usr/lib/swift"` or a
  missing `PrivateFrameworks` directory are expected — those paths come from the
  host, not from this SDK.
- The stubs cover only the frameworks listed above. A dependency that needs a
  different Apple framework means extending the SDK subset.
- Linking only: you cannot run the produced Mach-O binaries on this host.
