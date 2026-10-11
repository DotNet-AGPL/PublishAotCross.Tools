# macOS SDK Cross-Compilation 实施方案

## 背景

当前 `CustomAotToolChain=zig` 路径对 osx target 只设置了 `--target=$(TargetTriple)`，没有注入 macOS SDK 路径。
在非 macOS 主机上编译 osx target 时，zig 缺少 macOS 系统库（libSystem、CoreFoundation 等），导致链接失败。

本方案参照 `XWin.Store.*` 模式，将 macOS SDK 打包为 NuGet 包，在非 macOS → osx 交叉编译时自动注入 `-isysroot`。

---

## SDK 来源

| 来源 | stars | 最新 SDK | 下载 |
|---|---|---|---|
| [joseluisq/macosx-sdks](https://github.com/joseluisq/macosx-sdks) | 226 | **26.1 (Tahoe)** | [Release 26.1](https://github.com/joseluisq/macosx-sdks/releases/tag/26.1) |

SDK 信息（来自 [macosx_sdks.json](https://raw.githubusercontent.com/joseluisq/macosx-sdks/master/macosx_sdks.json)）：

| 版本 | 日期 | SHA256 | 体积 |
|---|---|---|---|
| **26.1** | 2025-11-03 | `beee7212d265a6d2867d0236cc069314b38d5fb3486a6515734e76fa210c784c` | 83.5 MB (tar.xz) |

macOS SDK 是 **Universal**（x86_64 + arm64 合一），不区分架构包。

> ⚠️ **许可**：macOS SDK 受 Apple Xcode 许可协议保护。下载脚本需显示许可提示并要求用户确认。

---

## 实施步骤

### 步骤 1：更新 `.gitignore`

在 `toolsets/.gitignore` 或项目根 `.gitignore` 添加：

```gitignore
# macOS SDK tmp
toolsets/MacOSX.SDK/.macosx-sdk-tmp/
```

### 步骤 2：`toolsets/MacOSX.SDK/build/MacOSX.SDK.props`

```xml
<Project>
  <PropertyGroup>
    <MacOSXSDKDir>$([MSBuild]::NormalizePath('$(MSBuildThisFileDirectory)../tools/.macosx-sdk'))</MacOSXSDKDir>
  </PropertyGroup>
</Project>
```

### 步骤 3：`toolsets/MacOSX.SDK/MacOSX.SDK.nuproj`

```xml
<Project Sdk="Microsoft.Build.NoTargets">
  <Import Project="../ToolsetsVersion.props" />

  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <NoWarn>$(NoWarn);NU5128</NoWarn>
    <PackageId>MacOSX.SDK</PackageId>
    <Version>$(MacOSXSDKVersion).$(Revision)</Version>
    <Description>macOS SDK $(MacOSXSDKVersion) (from joseluisq/macosx-sdks) for cross-compiling NativeAOT to macOS from non-macOS hosts</Description>
    <PackageProjectUrl>https://github.com/DotNet-AGPL/PublishAotCross.Tools/tree/main/toolsets/MacOSX.SDK</PackageProjectUrl>
    <PackageLicenseExpression>Apache-2.0</PackageLicenseExpression>
    <PackageReadmeFile>README.md</PackageReadmeFile>
  </PropertyGroup>

  <ItemGroup>
    <None Include=".macosx-sdk-tmp/**/*" Pack="true" PackagePath="tools/.macosx-sdk" />
    <None Include="build/MacOSX.SDK.props" Pack="true" PackagePath="buildTransitive" />
    <None Include="README.md" Pack="true" PackagePath="/" />
  </ItemGroup>
</Project>
```

> 关键：`.macosx-sdk-tmp/**/*` 打包为 `tools/.macosx-sdk`。SDK 内容直接在此目录下（`usr/`, `System/` 等）。

### 步骤 4：`toolsets/download-macosx-sdk.ps1`

```powershell
param(
  [switch]$AcceptLicense,
  [string]$Version = "26.1",
  [string]$StoreTmp = "$PSScriptRoot/MacOSX.SDK/.macosx-sdk-tmp"
)

if (-not $AcceptLicense) {
  Write-Host "=== Apple Xcode License Notice ==="
  Write-Host "This script downloads the macOS SDK from joseluisq/macosx-sdks."
  Write-Host "The macOS SDK is subject to Apple's Xcode license terms:"
  Write-Host "  https://www.apple.com/legal/sla/docs/xcode.pdf"
  Write-Host "By downloading and using this SDK, you agree to those terms."
  Write-Host ""
  $confirm = Read-Host "Do you accept the license terms? (y/N)"
  if ($confirm -ne "y" -and $confirm -ne "Y") { Write-Error "License not accepted"; exit 1 }
}

$url = "https://github.com/joseluisq/macosx-sdks/releases/download/$Version/MacOSX$Version.sdk.tar.xz"

# SHA256 from macosx_sdks.json
$sha256 = switch ($Version) {
  "26.1" { "beee7212d265a6d2867d0236cc069314b38d5fb3486a6515734e76fa210c784c" }
  "26.0" { "07ccaa2891454713c3a230dd87283f76124193309d9a7617ebee45354c9302d2" }
  "15.5" { "c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd" }
  default { throw "Unknown version $Version. Add SHA256 from https://raw.githubusercontent.com/joseluisq/macosx-sdks/master/macosx_sdks.json" }
}

$archive = "$env:TEMP\MacOSX$Version.sdk.tar.xz"

Write-Host "Downloading $url ..."
curl.exe -sL $url -o $archive
if (-not $?) { Write-Error "Download failed"; exit 1 }

$actual = (Get-FileHash -Path $archive -Algorithm SHA256).Hash
if ($actual -ne $sha256) { Write-Error "SHA256 mismatch:`n  Expected: $sha256`n  Actual:   $actual"; exit 1 }
Write-Host "SHA256 verified."

Remove-Item -Recurse -Force $StoreTmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $StoreTmp -Force | Out-Null
tar -xf $archive -C $StoreTmp
if (-not $?) { Write-Error "Extraction failed"; exit 1 }

$sz = (Get-ChildItem $StoreTmp -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host "Done. SDK extracted to $StoreTmp"
Write-Host "  Size: $([math]::Round($sz/1MB, 0)) MB"
Write-Host ""
Write-Host "Next step: dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force"
```

### 步骤 5：更新 `toolsets/ToolsetsVersion.props`

添加 `MacOSXSDKVersion`：

```xml
<Project>
  <PropertyGroup>
    <ZigVersion Condition="'$(ZigVersion)' == ''">0.17.0.1</ZigVersion>
    <XWinVersion Condition="'$(XWinVersion)' == ''">0.10.0</XWinVersion>
    <LLDVersion Condition="'$(LLDVersion)' == ''">23.1.3</LLDVersion>
    <MacOSXSDKVersion Condition="'$(MacOSXSDKVersion)' == ''">26.1</MacOSXSDKVersion>
    <Revision Condition="'$(Revision)' == ''">6</Revision>
  </PropertyGroup>
</Project>
```

### 步骤 6：修改 `src/build/Crosscompile.targets` — 注入 `-isysroot`

在 `OverwriteTargetTriple` target 的 zig 部分追加两个修改：

**在 zig PropertyGroup 内追加**（在 `</PropertyGroup>` 之前）：

```xml
<PropertyGroup Condition=" '$(CustomAotToolChain)' == 'zig' ">
  <!-- ... 现有代码 CrossCompileRid, CrossCompileArch, TargetTriple ... -->

  <!-- 新增：从非 macOS host 编译 osx 时加载 SDK 路径 -->
  <_MacOSXSDKDir Condition="$(RuntimeIdentifier.StartsWith('osx')) and !$(HostRuntimeIdentifier.StartsWith('osx'))">$(MacOSXSDKDir)</_MacOSXSDKDir>
</PropertyGroup>
```

**在 zig ItemGroup 内追加**（在 `--target=$(TargetTriple)` 之后）：

```xml
<ItemGroup Condition=" '$(CustomAotToolChain)' == 'zig' ">
  <LinkerArg Include="--target=$(TargetTriple)" />
  <!-- 新增：非 macOS host 编译 osx 时注入 SDK sysroot -->
  <LinkerArg Condition="'$(_MacOSXSDKDir)' != ''" Include="-isysroot $(MacOSXSDKDir)" />
</ItemGroup>
```

**条件逻辑**：
| Host | Target | `_MacOSXSDKDir` | 是否注入 `-isysroot` |
|---|---|---|---|
| win/linux | osx | 有值 | ✅ 注入 |
| osx | osx | 空 | ❌ 不注入（zig 用本地 SDK） |
| win/linux | linux | 空 | ❌ 不注入 |
| osx | linux | 空 | ❌ 不注入 |

### 步骤 7：更新 `src/PublishAotCross.Tools.nuproj`

在 `XWin.Store.*` 引用块附近添加：

```xml
<PackageReference Include="MacOSX.SDK" Version="$(MacOSXSDKVersion).$(Revision)" />
```

完整的引用块现在：

```xml
<ItemGroup>
  <!-- Zig toolchain packages -->
  <PackageReference Include="Vezel.Zig.Toolsets.win-x64" Version="$(ZigVersion)" GeneratePathProperty="true" />
  <PackageReference Include="Vezel.Zig.Toolsets.win-arm64" Version="$(ZigVersion)" GeneratePathProperty="true" />
  <PackageReference Include="Vezel.Zig.Toolsets.linux-x64" Version="$(ZigVersion)" GeneratePathProperty="true" />
  <PackageReference Include="Vezel.Zig.Toolsets.linux-arm64" Version="$(ZigVersion)" GeneratePathProperty="true" />
  <PackageReference Include="Vezel.Zig.Toolsets.osx-x64" Version="$(ZigVersion)" GeneratePathProperty="true" />
  <PackageReference Include="Vezel.Zig.Toolsets.osx-arm64" Version="$(ZigVersion)" GeneratePathProperty="true" />

  <!-- XWin SDK store packages -->
  <PackageReference Include="XWin.Store.x64" Version="$(XWinVersion).$(Revision)" />
  <PackageReference Include="XWin.Store.arm64" Version="$(XWinVersion).$(Revision)" />

  <!-- macOS SDK package (for win/linux → osx cross-compile) -->
  <PackageReference Include="MacOSX.SDK" Version="$(MacOSXSDKVersion).$(Revision)" />

  <!-- LLD linker packages -->
  <PackageReference Include="LLD.Link.Toolsets.win-x64" Version="$(LLDVersion).$(Revision)" />
  <PackageReference Include="LLD.Link.Toolsets.linux-x64" Version="$(LLDVersion).$(Revision)" />
  <PackageReference Include="LLD.Link.Toolsets.win-arm64" Version="$(LLDVersion).$(Revision)" />
  <PackageReference Include="LLD.Link.Toolsets.linux-arm64" Version="$(LLDVersion).$(Revision)" />
  <PackageReference Include="LLD.Link.Toolsets.osx-arm64" Version="$(LLDVersion).$(Revision)" />
</ItemGroup>
```

### 步骤 8：创建 `toolsets/MacOSX.SDK/README.md`

```markdown
# MacOSX.SDK

macOS SDK for cross-compiling NativeAOT to macOS from non-macOS hosts.

Packaged from [joseluisq/macosx-sdks](https://github.com/joseluisq/macosx-sdks), which packages
the SDK from Apple Xcode.

## Usage

This package is automatically referenced by `PublishAotCross.Tools`.
No manual action needed after initial SDK download.

## License

The SDK content itself is subject to Apple's Xcode license terms:
https://www.apple.com/legal/sla/docs/xcode.pdf

This NuGet packaging metadata is MIT.
```

---

## 执行顺序

```bash
# 1. 下载 SDK（首次需要接受 Apple 许可证）
.\toolsets\download-macosx-sdk.ps1 -AcceptLicense

# 2. 打包 MacOSX.SDK NuGet
dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force

# 3. 打包主包
dotnet pack src\PublishAotCross.Tools.nuproj -o artifacts --force

# 4. 测试：win → osx-arm64
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -r osx-arm64
```

---

## SDK 版本升级流程

```bash
# 场景：macOS 发布新版本（如 26.1 → 27.0）
# 1. 在 joseluisq/macosx-sdks 找到新版本 SHA256
# 2. 更新 toolsets/download-macosx-sdk.ps1 中的 SHA256 map
# 3. toolsets/ToolsetsVersion.props → MacOSXSDKVersion=27.0
# 4. 重新下载打包
.\toolsets\download-macosx-sdk.ps1 -AcceptLicense -Version 27.0
dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force
dotnet pack src\PublishAotCross.Tools.nuproj -o artifacts --force
```

---

## 设计决策

| 决策 | 选项 | 选择理由 |
|---|---|---|
| SDK 来源 | joseluisq/macosx-sdks | 226 stars，活跃更新到 26.1 |
| 分 arch？ | 不分 | macOS SDK 是 universal（单文件含多架构） |
| 注入方式 | `-isysroot` | zig cc 的 Clang driver 原生支持 |
| 注入时机 | 只在 `HostRuntimeIdentifier` 非 osx 时 | macOS host 上 zig 自动用本地 SDK |
| 合规处理 | 下载脚本显示许可证提示，用户显式确认 | 与 xwin `--accept-license` 同理 |
| 包版号 | `$(MacOSXSDKVersion).$(Revision)` = `26.1.6` | 与 XWin.Store 和 LLD.Link.Toolsets 格式一致 |

---

## 验证清单

- [ ] `.\toolsets\download-macosx-sdk.ps1 -AcceptLicense` 下载并解压成功
- [ ] SHA256 校验通过
- [ ] `dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj` 打包成功
- [ ] `dotnet pack src\PublishAotCross.Tools.nuproj` 打包成功
- [ ] `dotnet publish -r osx-arm64` 在 Windows 上成功编译
- [ ] 产物 `file` 命令输出 `Mach-O 64-bit executable arm64`
- [ ] 产物在 macOS 上能运行（需实际 macOS 环境验证）
- [ ] macOS host 上发布 osx 不受影响（不注入 `-isysroot`）
