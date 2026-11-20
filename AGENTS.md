# AGENTS.md

## 仓库结构

```
toolsets/
├── XWin.Store/                         ← 父包（metapackage，依赖 x64/arm64，无内容）
├── XWin.Store.x64/                     ← x64 SDK 导入库 NuGet 包
│   ├── XWin.Store.x64.nuproj
│   └── .xwin-store-tmp/                 ← 过滤后的 SDK store（gitignored）
├── XWin.Store.arm64/                   ← arm64 SDK 导入库 NuGet 包
│   ├── XWin.Store.arm64.nuproj
│   └── .xwin-store-tmp/                 ← 过滤后的 SDK store（gitignored）
├── LLD.Link.Toolsets/                  ← 父包（metapackage，依赖 5 个子包，无内容）
├── LLD.Link.Toolsets.win-x64/          ← lld-link NuGet 包（Windows x64）
│   ├── LLD.Link.Toolsets.win-x64.nuproj
│   └── tools/lld-link.zip.partNN
├── LLD.Link.Toolsets.win-arm64/        ← lld-link NuGet 包（Windows ARM64）
│   ├── LLD.Link.Toolsets.win-arm64.nuproj
│   └── tools/lld-link.zip.partNN
├── LLD.Link.Toolsets.linux-x64/        ← lld-link NuGet 包（Linux x64）
│   ├── LLD.Link.Toolsets.linux-x64.nuproj
│   └── tools/lld-link.zip.partNN
├── LLD.Link.Toolsets.linux-arm64/      ← lld-link NuGet 包（Linux ARM64）
│   ├── LLD.Link.Toolsets.linux-arm64.nuproj
│   └── tools/lld-link.zip.partNN
├── LLD.Link.Toolsets.osx-arm64/        ← lld-link NuGet 包（macOS ARM64）
│   ├── LLD.Link.Toolsets.osx-arm64.nuproj
│   └── tools/lld-link.zip.partNN
├── MacOSX.SDK/                          ← 过滤后的 macOS SDK NuGet 包（交叉到 osx-arm64）
│   ├── MacOSX.SDK.nuproj
│   └── .macosx-sdk-tmp/                 ← 过滤后的 SDK 子集（gitignored）
├── MacOSX.SDK.Fetch/                    ← 维护者工具：Apple CLT .pkg → xar → pbzx → cpio → 过滤子集
├── MacOSX.Symbols.Toolsets/                  ← LLVM dsymutil（osx 交叉生成 .dSYM）
│   ├── MacOSX.Symbols.Toolsets.nuproj        ← 父包（metapackage，依赖 4 个子包）
│   ├── win-x64/ win-arm64/ linux-x64/ linux-arm64/
│   │   ├── MacOSX.Symbols.Toolsets.<rid>.nuproj
│   │   ├── build/MacOSX.Symbols.Toolsets.<rid>.props
│   │   └── tools/dsymutil[.exe]         ← gitignored，由脚本生成
│   ├── README.md / LICENSE
├── LLVM-Source/                         ← 各平台 LLVM 二进制包（提取 lld-link / dsymutil 的来源）
├── ToolsetsVersion.props                ← XWinVersion=0.10.0, LLDVersion=23.1.5, MacOSXSDKVersion=27.2, Revision=15, PublishAotCrossVersionPrefix=1.0.3
├── xwin.exe                             ← xwin CLI v$(XWinVersion)（仅供维护者更新 store，不打包进 NuGet）
├── download-xwin-store.ps1              ← 下载 xwin SDK store（x64 + arm64 过滤打包到各自平台包）
├── download-lld-link.ps1                ← 从 LLVM 安装包提取各平台 lld-link
├── download-macosx-symbols.ps1          ← 从 LLVM 安装包提取各平台 dsymutil（linux 版自动 strip）
└── download-macosx-sdk.ps1              ← 下载 Apple CLT .pkg + 调 MacOSX.SDK.Fetch 过滤（osx-arm64 交叉用）

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
| `src/build/Crosscompile.targets` | `CustomAotToolChain=xwin` → xwin 链路；`=zig` → zig 链路；`PublishAotCrossMacOSStrip` → osx 交叉的 dSYM + 剥离 |
| `src/build/Scripts/SetPath.cs`   | 判断宿主/目标平台，设置`CustomAotToolChain`                                       |
| `toolsets/download-macosx-symbols.ps1` | 提取各宿主 `dsymutil` 到 `MacOSX.Symbols.Toolsets/<rid>/tools/`（linux 版 strip） |
| `toolsets/MacOSX.SDK.Fetch` | Apple CLT `.pkg` 解析（xar → pbzx → odc cpio）+ SDK 子集过滤 |
| `toolsets/ToolsetsVersion.props` | `XWinVersion=0.10.0`、`LLDVersion=23.1.5`、`MacOSXSDKVersion=27.2`、`Revision=15`、`PublishAotCrossVersionPrefix=1.0.3` |
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
#       仓库里存的是 ≤25MB 的分片 tools/lld-link.zip.partNN（GitHub REST blob API 单次
#       上限约 38MB base64，而本机只能走 API 推送）；打包时由
#       toolsets/LLD.Link.Toolsets.common.targets 合并回 lld-link.zip（该文件 gitignored）。
```

## MacOSX.Symbols.Toolsets

```bash
# 作用：非 macOS 宿主交叉到 osx 时，ld64 永不把 DWARF 写进 Mach-O（只有 N_OSO debug map），
#       要靠 dsymutil 生成 .dSYM；Xcode 的 dsymutil 不可再分发 → 打包 LLVM 上游版本。
#       仅收工具，不收符号数据；macOS 宿主不需要（Xcode 自带）。

# 场景：LLVM 版本升级（23.1.5 → 23.2.0）
#   1. 确认 toolsets/LLVM-Source/ 下有对应 LLVM-<ver>-{Linux-X64,Linux-ARM64}.tar.xz
#      和 clang+llvm-<ver>-{x86_64,aarch64}-pc-windows-msvc.tar.xz
#   2. toolsets\download-macosx-symbols.ps1 -Version 23.2.0 -Platform all
#      （linux 版自动用 src/build/llvm-objcopy/win-x64/llvm-objcopy.exe strip，136MB→95MB）
#   3. toolsets/ToolsetsVersion.props → LLDVersion=23.2.0（MacOSX.Symbols.Toolsets 复用该版本号）
#   4. dotnet pack toolsets\MacOSX.Symbols.Toolsets\win-x64 -o artifacts --force   # 4 个子包
#      dotnet pack toolsets\MacOSX.Symbols.Toolsets -o artifacts --force           # 父包（需子包已在 feed）
#   5. dotnet nuget push ...（先子包后父包）

# 体积：win 52.2MB/宿主（nupkg ≈19MB）、linux 136MB→95MB（nupkg ≈30MB），4 宿主合计 ≈100MB nupkg
# 注意：tools/dsymutil* 为 gitignored，不入库；nuproj 缺文件时会 Error 提示先跑脚本

# 消费方（PublishAotCross.Tools 的 Crosscompile.targets 目标 PublishAotCrossMacOSStrip）：
#   osx 目标 + 非 macOS 宿主（StripSymbols 默认 true，-p:StripSymbols=false 可关）
#   → PublishAotCrossMacOSStripGuard（BeforeTargets=SetupOSSpecificProps）执行期把 StripSymbols 置 false，
#     屏蔽 ILC 的 Xcode 分支（全局 -p:StripSymbols=true 在评估期无法覆盖，只能在目标里改）
#   → dsymutil --quiet <bin>（生成 <bin>.dSYM）
#   → llvm-objcopy -x <bin>（等价 Apple strip -x，保留外部符号）
#   → 写 <bin>.stripped 标记（Inputs/Outputs）保证增量构建不重复剥离
#   顺序不可反：-x 会删掉 debug map。92 条 runtime .a 的 warning 必须
#   IgnoreStandardErrorWarningFormat="true"（否则成 MSBuild warning），噪音用 StandardErrorImportance="Low" 压。

# ⚠️ 重打「同版本号」包后必须：dotnet build-server shutdown + 删 .nuget/packages/publishaotcross.tools/<ver>
#    否则 MSBuild 服务器复用旧评估，会看到「新 target 报 MSB4057 不存在」这类假象。
```

## 主包 PublishAotCross.Tools

```bash
# 依赖结构（11 个 PackageReference，全部是"父包 + Zig"）：
#   XWin.Store、MacOSX.SDK、MacOSX.Symbols.Toolsets、LLD.Link.Toolsets + 6 个 Vezel.Zig.Toolsets
#   ⇒ 子包（.<rid>）只由父包引用，主包不再逐个列平台；新增平台只改父包一行。

# 1. 修改版本号：toolsets/ToolsetsVersion.props → PublishAotCrossVersionPrefix（前段）
#    主包版本 = $(PublishAotCrossVersionPrefix).$(Revision)，Revision 与 toolsets 共享
# 2. 打包
dotnet pack src\PublishAotCross.Tools.nuproj -o artifacts --force
# 3. 推送（示例版本 1.0.3.14）
dotnet nuget push artifacts\PublishAotCross.Tools.1.0.3.14.nupkg --api-key <key> --source https://api.nuget.org/v3/index.json
# 注意推送顺序：父包（LLD.Link.Toolsets / XWin.Store / MacOSX.Symbols.Toolsets）必须在主包之前
# 推荐用脚本（自动排序 + 内容/依赖闭包校验 + 幂等）：
#   pwsh toolsets\publish-release.ps1 -Check   # 只校验
#   pwsh toolsets\publish-release.ps1 -Push    # 按 子包→父包→主包 顺序推送
# 完整清单见 docs/RELEASE-CHECKLIST.md
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
3. 在**父包**里加一行 `PackageReference`：`XWin.Store` / `LLD.Link.Toolsets`（主包不用动）

## 新会话快速上手

架构原理、版本/发布模型、符号剥离（`llvm-objcopy`）与踩坑清单见 **`docs/PROJECT-HANDOVER.md`**。
