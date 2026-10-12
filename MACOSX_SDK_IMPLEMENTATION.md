# macOS SDK 交叉编译（osx-arm64）

> **状态：已实现并经 CI 端到端验证（2026-10）**
> 在 Windows/Linux 上直接交叉编译出**可在 Apple Silicon 运行**的 `osx-arm64` 产物，构建全程**不需要 Mac**。
> 范围：**仅 `osx-arm64`**（不含 osx-x64）。

## 目标与原理

.NET Native AOT 到 macOS 需要：C 编译器 `clang`（由 zig 提供）+ 链接需要的 macOS 系统库/框架。
zig **不自带** Apple 的 libSystem / 框架，因此必须提供 **macOS SDK**。

本实现参照 `XWin.Store.*` 模式：把 macOS SDK 的**必需子集**打包为 NuGet 包 `MacOSX.SDK`，
主包自动引用它 → 用户装上即用（自动得到 `MacOSXSDKDir`），无需手动配置。

## 实测得出的关键结论（重要）

1. **zig 不会从 `-isysroot` 推导 framework/lib 搜索路径**（会报 `searched paths: none`）。
   必须显式传：
   - `-F <sdk>/System/Library/Frameworks`
   - `-F <sdk>/System/Library/PrivateFrameworks`
   - `-L <sdk>/usr/lib`
   - `-L <sdk>/usr/lib/swift`（**Swift 运行时 `.tbd` 在这里**，不是 `usr/lib/swift/macosx`）
2. **`-Wl,-adhoc_codesign` 不被 zig 链接器支持**；但**实测无需**——zig 产出的 Mach-O 可直接在 Apple Silicon 运行。
3. **`-Wl,-u,__Module` 是 ELF 专用 workaround**；在 Mach-O 上会报 `undefined symbol: __Module`，macOS 目标必须**跳过**。
4. **编译阶段不需要 macOS 头文件**（AOT 生成的 C++ 只用运行时自带头）；真正需要 SDK 的是**链接阶段**。
   为稳妥，过滤集仍保留 `usr/include`。

## SDK 来源与过滤

[doseluisq/macosx-sdks](https://github.com/joseluisq/macosx-sdks) 打包了来自 Apple Xcode 的 SDK。

| 版本 | SHA256 | 归档 |
|---|---|---|
| **26.1** | `beee7212d265a6d2867d0236cc069314b38d5fb3486a6515734e76fa210c784c` | 83.5 MB `tar.xz` |
| 26.0 | `07ccaa2891454713c3a230dd87283f76124193309d9a7617ebee45354c9302d2` | |
| 15.5 | `c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd` | |

完整 SDK 解压 **1883 MB**（nuget.org 单包上限 ~250MB，**不能整包**）。
只取 NativeAOT 需要的一小部分（未压缩 ~108MB → **nupkg ~15MB**）：

```
usr/include/**                                             # 头文件
usr/lib/**/*.tbd                                           # libSystem/libobjc/libicucore…
usr/lib/swift/**/*.tbd                                     # libswiftCore/libswiftFoundation…
System/Library/Frameworks/{CoreFoundation,Foundation,Security,Network,GSS,CryptoKit}.framework/**/*.tbd
```

框架白名单起步 6 个；若链接报缺其它框架，扩充 `download-macosx-sdk.ps1` 里的 `$frameworks` 列表。
用户如需完整 SDK，可用 `MacOSXSDKDir`（或 `MACOSX_SDK` 环境变量）覆盖。

> ⚠️ **许可**：SDK 内容受 Apple Xcode 许可约束。包设 `PackageRequireLicenseAcceptance=true`，
> 下载脚本 `download-macosx-sdk.ps1` 也要求显式 `-AcceptLicense`。

## 实现概览

### 1. `toolsets/MacOSX.SDK/`（NuGet 包）
- `MacOSX.SDK.nuproj`：把 `.macosx-sdk-tmp/**` 打包为 `tools/.macosx-sdk`；`PackageRequireLicenseAcceptance=true`；版本 `$(MacOSXSDKVersion).$(Revision)`（= `26.1.9`）。
- `build/MacOSX.SDK.props`（`buildTransitive`）：
  ```xml
  <MacOSXSDKDir>$([MSBuild]::NormalizePath('$(MSBuildThisFileDirectory)../tools/.macosx-sdk'))</MacOSXSDKDir>
  ```
- `README.md`：用法与 Apple 许可说明。

### 2. `toolsets/download-macosx-sdk.ps1`
下载（SHA256 校验）→ 解压（7-Zip 解 `.tar.xz`，bsdtar 解 `.tar`）→ **按上述规则裁剪**到 `.macosx-sdk-tmp/`。

### 3. `toolsets/ToolsetsVersion.props`
新增 `MacOSXSDKVersion=26.1`（连同 `Revision=9`、`PublishAotCrossVersion`）。

### 4. 主包 `src/PublishAotCross.Tools.nuproj`
```xml
<PackageReference Include="MacOSX.SDK" Version="$(MacOSXSDKVersion).$(Revision)" />
```

### 4b. `StripSymbols` 条件默认（`Crosscompile.targets`）
交叉到 macOS（非 macOS 宿主）时，ILCompiler 会调用 macOS 专属的 `dsymutil`/`strip` → 自动默认关闭符号剥离：
```xml
<_IsCrossCompilingToMacOS Condition="$(RuntimeIdentifier.StartsWith('osx')) and !$(HostRuntimeIdentifier.StartsWith('osx'))">true</_IsCrossCompilingToMacOS>
<StripSymbols Condition="'$(StripSymbols)' == '' and '$(_IsCrossCompilingToMacOS)' == 'true'">false</StripSymbols>
```
其它场景（win→linux 等）保持 SDK 原生默认；剥离所需的 `llvm-objcopy` 已按宿主随包内置（`src/build/llvm-objcopy/<host-rid>/`）。

### 5. `src/build/Crosscompile.targets`
```xml
<!-- 顶部：SDK 目录（属性优先，回退到 MACOSX_SDK 环境变量） -->
<MacOSXSDKDir Condition="'$(MacOSXSDKDir)' == ''">$(MACOSX_SDK)</MacOSXSDKDir>
...
<!-- zig 段：给 osx 目标注入 -isysroot -->
<LinkerArg Condition="'$(_MacOSXSDKDir)' != '' and $(RuntimeIdentifier.StartsWith('osx'))" Include="-isysroot $(_MacOSXSDKDir)" />
```

### 6. `src/build/Scripts/SetPath.cs`
把 `MacOSXSDKDir` 写入 `MACOSX_SDK` 环境变量，供 clang wrapper 使用：
```csharp
if (!string.IsNullOrEmpty(MacOSXSDKDir)) {
  Environment.SetEnvironmentVariable("MACOSX_SDK", MacOSXSDKDir);
}
```

### 7. `src/build/clang` 与 `clang.ps1`（Zig 包装）
当目标为 macOS 且设了 `MACOSX_SDK` 时注入 `-isysroot` + `-F` + `-L`；并跳过 `-Wl,-u,__Module`。

### 8. `src/build/Scripts/SetPath.cs` — 原生 macOS 例外
宿主=目标=osx 时**不走 zig**（用 Apple 原生工具链），因为 zig 在本机也找不到 macOS SDK。

## 执行顺序（维护者）

```bash
# 1. 下载并过滤 SDK（首次需接受 Apple 许可）
.\toolsets\download-macosx-sdk.ps1 -AcceptLicense

# 2. 打包 MacOSX.SDK
dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force

# 3. 打包主包（会自动引用 MacOSX.SDK）
dotnet pack src\PublishAotCross.Tools.nuproj -o artifacts --force

# 4. 验证：win → osx-arm64（无需手动设 SDK 路径）
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -f net10.0 -r osx-arm64
```

## SDK 版本升级流程

```bash
# 1. 在 joseluisq/macosx-sdks 找到新版本 SHA256
# 2. 更新 toolsets/download-macosx-sdk.ps1 中的 SHA256 map
# 3. toolsets/ToolsetsVersion.props → MacOSXSDKVersion=27.0
# 4. 重新下载打包
.\toolsets\download-macosx-sdk.ps1 -AcceptLicense -Version 27.0
dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force
```

## CI

`.github/workflows/main.yml`：
- `sdk` job（windows-latest）：下载 + 过滤 + 打包 `MacOSX.SDK`，上传为 artifact。
- `cross_osx_arm64` job（windows-latest）：下载该 `MacOSX.SDK` 包到本地 feed → 打主包 → `dotnet publish -r osx-arm64` → 校验 Mach-O → 上传。
- `run_osx_arm64` job（macos-latest）：下载该产物并**运行**（验证可在 arm64 运行）。
- 全程**不推送 NuGet**。

## 设计决策

| 决策 | 选择 | 理由 |
|---|---|---|
| SDK 来源 | joseluisq/macosx-sdks | 打包了 Apple Xcode SDK，活跃更新 |
| 交付方式 | **过滤子集打进 NuGet** | 完整 1.9GB 超 nuget.org 上限；子集仅 ~15MB，用户装上即用 |
| 链接器 | zig 内置 Mach-O 链接器 | 不必引入 `ld64.lld`；实测可产出可运行产物 |
| sysroot 注入 | `-isysroot` + 显式 `-F`/`-L` | zig 不自动推导框架/库路径 |
| 签名 | 不做 | zig 产物可直接在 arm64 运行（实测） |
| 原生 macOS | 不走 zig，用 Apple 工具链 | zig 在本机也找不到 SDK |
| 合规 | `PackageRequireLicenseAcceptance` + 脚本 `-AcceptLicense` | 用户显式同意 |
| 包版号 | `$(MacOSXSDKVersion).$(Revision)` = `26.1.9` | 与 XWin.Store/LLD 一致 |

## 许可说明（`PackageRequireLicenseAcceptance`）

- **Visual Studio / `nuget.exe install`**：安装时弹出「I Accept」对话框。
- **`dotnet restore` / CI**：默认不弹窗（视为「使用即接受」）。
- Apple 条款文本见包内 `README.md` 与 `NOTICE`；`PackageRequireLicenseAcceptance` 弹窗展示的是包自身许可（Apache-2.0）。

## 验证清单

- [x] `download-macosx-sdk.ps1` 下载 + SHA256 + 过滤成功（108 MB）
- [x] `MacOSX.SDK.26.1.9.nupkg` 打包成功（**14.7 MB**，< 250MB 上限）
- [x] 主包打包成功，且 nuspec 含 `MacOSX.SDK 26.1.9` 依赖
- [x] `dotnet publish -r osx-arm64` 在 Windows 上成功编译出 Mach-O（magic `cffaedfe`）
- [x] 产物在 macOS(arm64) runner 上运行成功（CI `run_osx_arm64`）——**无需签名**
- [x] macOS host 发布 osx-arm64（原生，走 Apple 工具链，不入 zig）——CI 通过
- [x] CI 端到端全绿（`sdk` → 主包 → 交叉编译 → 运行）

## 未做 / 边界

- **osx-x64**：不支持（按决定仅 osx-arm64）。
- **`MacOSX.SDK` 发布**：按约定**未推送 NuGet**（如需发布，先推 `MacOSX.SDK.26.1.9` 再推主包新版本）。
- **框架白名单**：目前 6 个；GUI/复杂应用可能需扩充。
