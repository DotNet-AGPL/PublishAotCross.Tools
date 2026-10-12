# AGENTS.md

## 仓库结构

```
toolsets/
├── XWin.Store.x64/                     ← x64 SDK 导入库 NuGet 包
│   ├── XWin.Store.x64.nuproj
│   └── .xwin-store-tmp/                 ← 过滤后的 SDK store（gitignored）
├── XWin.Store.arm64/                   ← arm64 SDK 导入库 NuGet 包
│   ├── XWin.Store.arm64.nuproj
│   └── .xwin-store-tmp/                 ← 过滤后的 SDK store（gitignored）
├── LLD.Link.Toolsets.win-x64/          ← lld-link NuGet 包（Windows x64）
│   ├── LLD.Link.Toolsets.win-x64.nuproj
│   └── tools/lld-link.zip
├── LLD.Link.Toolsets.win-arm64/        ← lld-link NuGet 包（Windows ARM64）
│   ├── LLD.Link.Toolsets.win-arm64.nuproj
│   └── tools/lld-link.zip
├── LLD.Link.Toolsets.linux-x64/        ← lld-link NuGet 包（Linux x64）
│   ├── LLD.Link.Toolsets.linux-x64.nuproj
│   └── tools/lld-link.zip
├── LLD.Link.Toolsets.linux-arm64/      ← lld-link NuGet 包（Linux ARM64）
│   ├── LLD.Link.Toolsets.linux-arm64.nuproj
│   └── tools/lld-link.zip
├── LLD.Link.Toolsets.osx-arm64/        ← lld-link NuGet 包（macOS ARM64）
│   ├── LLD.Link.Toolsets.osx-arm64.nuproj
│   └── tools/lld-link.zip
├── MacOSX.SDK/                          ← 过滤后的 macOS SDK NuGet 包（交叉到 osx-arm64）
│   ├── MacOSX.SDK.nuproj
│   └── .macosx-sdk-tmp/                 ← 过滤后的 SDK 子集（gitignored）
├── LLVM-Source/                        ← 各平台 LLVM 二进制包（提取 lld-link 的来源）
├── ToolsetsVersion.props                ← XWinVersion=0.10.0, LLDVersion=23.1.3, MacOSXSDKVersion=26.1, Revision=9
├── xwin.exe                             ← xwin CLI v$(XWinVersion)（仅供维护者更新 store，不打包进 NuGet）
├── download-xwin-store.ps1              ← 下载 xwin SDK store（x64 + arm64 过滤打包到各自平台包）
├── download-lld-link.ps1                ← 从 LLVM 安装包提取各平台 lld-link
└── download-macosx-sdk.ps1              ← 下载 + 过滤 macOS SDK（osx-arm64 交叉用）

src/
├── PublishAotCross.Tools.nuproj    ← 主 NuGet 包
├── download-llvm-objcopy.ps1            ← 维护者用（不打包）
└── build/                               ← 内容镜像包内 build/
    ├── PublishAotCross.Tools.props      ← 自动导入（NuGet convention）
    ├── PublishAotCross.Tools.targets    ← 自动导入
    ├── Crosscompile.targets             ← xwin/zig 链路核心
    ├── clang / clang.cmd / clang.ps1    ← Zig 编译器包装
    ├── gcc / objcopy                     ← Zig 包装 / objcopy 兜底 shim
    ├── llvm-objcopy/<host-rid>/          ← 内置多格式 llvm-objcopy（随仓库提交）
    └── Scripts/SetPath.cs               ← 工具链选择逻辑

test/
├── AvaloniaApp/                         ← Avalonia + Native AOT 验证 (ACadSharp DWG 文本提取)
├── ConsoleApp/
└── TestPublish/
    └── TestNupkg.csproj                 ← Native AOT 交叉编译验证
```

## 关键文件

| 文件                               | 职责                                                                                |
| ---------------------------------- | ----------------------------------------------------------------------------------- |
| `src/build/Crosscompile.targets` | `CustomAotToolChain=xwin` → xwin 链路；`=zig` → zig 链路                      |
| `src/build/Scripts/SetPath.cs`   | 判断宿主/目标平台，设置`CustomAotToolChain`                                       |
| `toolsets/ToolsetsVersion.props` | `XWinVersion=0.10.0`、`LLDVersion=23.1.3`、`Revision=9` |
| `win-x64`                        | `dotnet publish -c Release -r win-x64`                                            |
| `win-arm64`                      | `dotnet publish -c Release -r win-arm64`                                          |
| `linux-x64`                      | `dotnet publish -c Release -r linux-x64`                                          |

## XWin.Store.*

```bash
# 场景 1：xwin CLI 版本升级（0.9.0 → 0.10.0）
#   1. 下载新版 xwin.exe 覆盖 toolsets/xwin.exe
#      https://github.com/Jake-Shadle/xwin/releases
#   2. toolsets/ToolsetsVersion.props → XWinVersion=0.10.0
#   3. 管理员运行 toolsets\download-xwin-store.ps1
#   4. dotnet pack toolsets\XWin.Store.x64.nuproj -o artifacts --force
#      dotnet pack toolsets\XWin.Store.arm64.nuproj -o artifacts --force
#   5. dotnet nuget push ...

# 场景 2：仅重新打包（版本未变）
#   dotnet pack toolsets\XWin.Store.x64.nuproj -o artifacts --force
#   dotnet pack toolsets\XWin.Store.arm64.nuproj -o artifacts --force

# 场景 3：SDK store 刷新（Windows SDK 版本升级）
#   1. Remove-Item toolsets/XWin.Store.x64/.xwin-store-tmp -Recurse
#      Remove-Item toolsets/XWin.Store.arm64/.xwin-store-tmp -Recurse
#   2. 修改 toolsets/download-xwin-store.ps1 中 --sdk-version
#   3. 管理员运行 toolsets/download-xwin-store.ps1
#   4. 打包推送

# 注意：xwin.exe 仅用于维护者更新 store，不打包进 NuGet
#       XWinVersion 在 ToolsetsVersion.props 中定义，与 xwin --version 一致
```

## LLD.Link.Toolsets.win-x64

```bash
# 场景：LLVM 版本升级（22.1.8 → 23.0.0）
#   1. 下载新版 LLVM installer 到 toolsets/LLVM-Source/LLVM-<version>-win64.exe
#      https://github.com/llvm/llvm-project/releases
#   2. toolsets\download-lld-link.ps1 -Version 23.0.0（需 7-Zip）
#   3. toolsets/ToolsetsVersion.props → LLDVersion=23.0.0
#   4. dotnet pack toolsets\LLD.Link.Toolsets.win-x64 -o artifacts --force
#   5. dotnet nuget push ...

# 注意：lld-link.exe 约 71 MB，直接从 LLVM installer 提取
#       版本号与 LLVM 版本一一对应
```

## 主包 PublishAotCross.Tools

```bash
# 1. 修改版本号 src/PublishAotCross.Tools.nuproj → Version
# 2. 打包（默认版本 0.6.0.8，或通过 -p:Version 指定）
dotnet pack src\PublishAotCross.Tools.nuproj -o artifacts --force
# 3. 推送
dotnet nuget push artifacts\PublishAotCross.Tools.0.6.0.8.nupkg --api-key <key> --source https://api.nuget.org/v3/index.json
```

## 测试

### TestNupkg（交叉编译验证）

```bash
# win-x64
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -r win-x64

# win-arm64（ARM64 交叉编译）
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -r win-arm64

# linux-x64（跨平台 zig）
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -r linux-x64
```

### AvaloniaApp（Avalonia + ACadSharp + Native AOT）

```bash
# win-x64
dotnet publish test/AvaloniaApp/AvaloniaApp.csproj -c Release -r win-x64
```

## 新增平台

以 `linux-x64` 为例：

1. 创建 `toolsets/XWin.Store.linux-x64/` — 同 x64 结构，包含 linux 目标导入库
2. 创建 `toolsets/LLD.Link.Toolsets.linux-x64/` — lld-link 为 linux 二进制
3. 主 nuproj 添加 `PackageReference` 引用新平台包
