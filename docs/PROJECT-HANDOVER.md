# 项目上手 / 交接文档（PROJECT-HANDOVER）

> 面向"新会话快速熟悉项目"。这里讲**原理、版本/发布模型、踩坑清单**；
> 结构速览与常用命令另见 `AGENTS.md` 与 `.github/copilot-instructions.md`。

---

## 1. 项目定位与仓库结构

`PublishAotCross.Tools` 是一组 MSBuild targets，让 **Native AOT 交叉编译**（在 Windows/Linux 上产出 linux / osx / win 各平台的可执行文件）开箱即用。

```
toolsets/                                 各平台"内容包"（作为 NuGet 被主包引用）
├── ToolsetsVersion.props                 ★ 全仓库版本的单一来源
├── XWin.Store.x64 / .arm64               Windows SDK/CRT 导入库 store（内容 gitignored）
├── LLD.Link.Toolsets.{win,linux,osx}-*   lld-link 链接器（各宿主平台一份）
├── MacOSX.SDK                            过滤后的 macOS SDK 子集（osx 交叉用）
├── LLVM-Source/                          维护者用的 LLVM 原始安装包（gitignored）
└── download-*.ps1                        维护者脚本（重新生成上面各包的内容）

src/
├── PublishAotCross.Tools.nuproj          主 NuGet 包
├── download-llvm-objcopy.ps1             维护者脚本（生成内置 llvm-objcopy）
└── build/                                ⚠️ 原样映射为包内 build/ 目录
    ├── PublishAotCross.Tools.props/.targets   自动导入
    ├── Crosscompile.targets             xwin/zig 两条链路的核心逻辑
    ├── clang / clang.cmd / clang.ps1    Zig 编译器包装
    ├── gcc / objcopy                    Zig 包装 / objcopy 兜底 shim（POSIX）
    ├── llvm-objcopy/<host-rid>/         内置多格式 llvm-objcopy（随仓库提交）
    └── Scripts/SetPath.cs               宿主/目标判定、设置 CustomAotToolChain

test/
├── TestPublish/TestNupkg.csproj         交叉编译验证（net8/9/10，多 RID）
├── AvaloniaApp/                         Avalonia + ACadSharp 的 Native AOT 样例
└── ConsoleApp/

.github/workflows/
├── main.yml                             CI（PR / 手动）
└── fetch-objcopy.yml                    手动：拉取内置 llvm-objcopy
```

---

## 2. 工具链架构

`src/build/Crosscompile.targets` + `Scripts/SetPath.cs` 决定用哪条链：

| `CustomAotToolChain` | 适用 | 组成 |
| --- | --- | --- |
| `xwin` | Windows 目标 | xwin SDK store + `lld-link` +（win 宿主时）Zig 作为 clang |
| `zig`  | linux / osx 目标 | Zig 提供的 `cc`/linker，配 `clang`/`gcc` shim |

**`SetPath.cs` 关键动作**
- 按宿主把 Zig 加入 PATH（`UseExternalZig=false` 时）。
- 设置 `MACOSX_SDK`（来自 `MacOSXSDKDir`，即 `MacOSX.SDK` 包提供的路径）。
- **zig 链路**下把包内 `build/` 与 `build/llvm-objcopy/<宿主 RID>` **前置**到 PATH，并对非 Windows 宿主 `chmod -R +x`。

**`clang` shim（POSIX，`zig cc` 包装）**
- 去掉 zig 不支持的参数（`-lz`、`-pie`、`--discard-all` 等）。
- 仅对 **ELF** 注入 `-Wl,-u,__Module`（Mach-O 会失败，故跳过）。
- 当 `MACOSX_SDK` 存在且目标含 `macos/apple` 时，追加 `-isysroot`、`-F System/Library/{,Private}Frameworks`、`-L usr/lib`、`-L usr/lib/swift`
  （Zig **不会**从 `-isysroot` 推导框架/库路径，必须显式给）。

**`OverwriteTargetTriple`（`Crosscompile.targets`）**
- zig 链路：写入 `--target=<arch>-linux-gnu[.glibc] / -linux-musl / -macos`。
- xwin 链路：把 ILCompiler 的 `LinkerArg` 改写成 `/vctoolsdir:`、`/winsdkdir:`、`/LIBPATH:` 等。

---

## 3. 版本与发布模型 ★

单一来源：`toolsets/ToolsetsVersion.props`

```xml
<ZigVersion>0.17.0.1</ZigVersion>
<XWinVersion>0.10.0</XWinVersion>
<LLDVersion>23.1.3</LLDVersion>
<MacOSXSDKVersion>26.1</MacOSXSDKVersion>
<Revision>13</Revision>                                  <!-- 全包共享 -->
<PublishAotCrossVersionPrefix>1.0.1</PublishAotCrossVersionPrefix>
<PublishAotCrossVersion>$(PublishAotCrossVersionPrefix).$(Revision)</PublishAotCrossVersion>
```

| 包 | 版本公式 |
| --- | --- |
| `PublishAotCross.Tools` | `$(PublishAotCrossVersionPrefix).$(Revision)` → 如 `1.0.1.13` |
| `XWin.Store.*` | `$(XWinVersion).$(Revision)` |
| `LLD.Link.Toolsets.*` | `$(LLDVersion).$(Revision)` |
| `MacOSX.SDK` | `$(MacOSXSDKVersion).$(Revision)` |

要点：
- **`Revision` 全包共享**：主包依赖的就是 `…$(Revision)`。改动 `Revision` ⇒ **9 个包都要重发**（toolsets 通常只是"换版本号"）。
- **主包 = 前段 + Revision**：前段（`PublishAotCrossVersionPrefix`）可单独调整。
- **发布顺序：先 8 个 toolset/store/SDK，再主包**。否则用户还原与 CI 都会 `NU1102`（找不到 `.Revision` 版本）。
- 线上历史：`0.6.0.5 … 0.6.0.12` →（本次）`1.0.1.13`。

---

## 4. macOS 交叉（非 macOS 宿主 → osx-arm64）

- `MacOSX.SDK` 包（过滤后的 SDK 子集，约 14.7MB）自动 `PackageReference` ；其 `buildTransitive/MacOSX.SDK.props` 给出 `MacOSXSDKDir`。
- 无需 Mac：Zig 链接 + 注入的 SDK 搜索路径即可产出 Mach-O。
- **`StripSymbols` 例外**：`RuntimeIdentifier.StartsWith('osx') && !HostRuntimeIdentifier.StartsWith('osx')` ⇒ 默认 `false`
  （ILCompiler 对 Apple 目标会调用 macOS 专属的 `dsymutil`/`strip`，宿主没有）。
- 已知**无害**告警：`unable to open library directory "/usr/lib/swift"`、以及 SDK 内 `PrivateFrameworks` 目录不存在（过滤子集未含）。由 `-L`/`-F` 实际路径兜住。

---

## 5. 符号剥离（llvm-objcopy 与 objcopy shim）★

**ILCompiler 的默认**（`microsoft.dotnet.ilcompiler`）：
- 非 Windows 目标 `StripSymbols` 默认 `true`。
- 链接器为 clang 时，`ObjCopyName` 优先 `llvm-objcopy`，回退 `objcopy`（`Microsoft.NETCore.Native.Unix.targets`）。
- 宿主的 binutils `objcopy` 是**单格式**的：x64 上的它**无法剥离 aarch64 ELF** → 必须用多格式的 `llvm-objcopy`。

**本项目的做法**
- 随包内置各宿主 `llvm-objcopy`（LLVM 23.1.3）：`src/build/llvm-objcopy/{linux-x64,linux-arm64,osx-arm64}/llvm-objcopy` + `win-x64/llvm-objcopy.exe`，**随仓库提交**。
  - `SetPath.cs` 按宿主把对应目录前置到 PATH ⇒ ILC 优先命中它 ⇒ 跨架构剥离正常。
  - `win-arm64` 宿主复用 `win-x64`（x64 二进制在 arm64 上以模拟方式运行）。
- `src/build/objcopy` 是**兜底 shim**（当没有 `llvm-objcopy` 时才会走到）：
  - 绝不 `exec` 自己（原实现会自递归卡死整条流水线）；
  - 找到真实 `llvm-objcopy` → 直接用；
  - 只有 binutils `objcopy` → 执行，失败则**告警并保留符号**（`exit 0`，不中断构建）。

**重新生成内置二进制**
- 首选：跑一次 `.github/workflows/fetch-objcopy.yml`（CI 下载 3 个官方 `.tar.zst`，抽出 `bin/llvm-objcopy`，产物作 artifact 传回后提交）。
- 本地：`src/download-llvm-objcopy.ps1`。
- ⚠️ 解压 `.tar.zst` 需大窗口：GNU tar 的 `--zstd` 会报 `window size larger than maximum`，改用
  `zstd -dc --long=30 <file> | tar -xf - --wildcards '*/bin/llvm-objcopy'`。
- LLVM 官方包很大（1.5–1.9GB/平台）；本机走代理被限速（~0.3MB/s），所以用 CI 下载。

---

## 6. CI

`.github/workflows/main.yml`（触发：`pull_request` + `workflow_dispatch`）
- `sdk`：下载并过滤 macOS SDK → 打 `MacOSX.SDK` 包 → 上传 artifact。
- `build`（矩阵 Windows/Linux/macOS）：把 `MacOSX.SDK` 放入本地 `artifacts` feed，**本地打主包**（合成版本 `0.0.0-ci`），再交叉编译 `TestNupkg`。
- `cross_osx_arm64`（Windows 宿主）+ `run_osx_arm64`（macOS runner 运行）+ `validate`（跑 linux-x64）。
- CI **不推送** NuGet；`XWin.Store.*` / `LLD.*` 内容 gitignored，CI 只能从 feed **还原**它们。
  ⇒ **改 `Revision` 后必须先发布这些包，CI 才能跑通。**

`.github/workflows/fetch-objcopy.yml`：手动工具，获取/更新内置 `llvm-objcopy`。

**启停 / 触发（GitHub API）**
```bash
# 停用 / 启用
curl -X PUT  -H "Authorization: token $KEY" .../actions/workflows/main.yml/disable
curl -X PUT  -H "Authorization: token $KEY" .../actions/workflows/main.yml/enable
# 触发并看 run
curl -X POST -H "Authorization: token $KEY" .../actions/workflows/main.yml/dispatches -d '{"ref":"main"}'
```
> 本机有本地 GitHub 代理，`curl` 一律加 `--ssl-no-revoke`；`nuget.org` 不受影响（很快）。

---

## 7. 维护者脚本

| 脚本 | 作用 | 备注 |
| --- | --- | --- |
| `toolsets/download-xwin-store.ps1` | 重新生成 xwin SDK store | 需管理员 + 网络 |
| `toolsets/download-lld-link.ps1` | 从 LLVM 安装包提取各平台 `lld-link` | 需 7-Zip |
| `toolsets/download-macosx-sdk.ps1` | 下载 + 过滤 macOS SDK | 需接受 Apple 许可 |
| `src/download-llvm-objcopy.ps1` | 生成内置 `llvm-objcopy` | 须支持 zstd 的 tar |
| `.github/workflows/fetch-objcopy.yml` | 同上（CI 版，推荐） | 手动触发 |

---

## 8. 本地开发与验证

```bash
# 打主包（artifacts 同时是本地 NuGet feed；NuGet.Config 已声明）
dotnet pack src/PublishAotCross.Tools.nuproj -o artifacts --force

# 打某个 toolset
dotnet pack toolsets/LLD.Link.Toolsets.win-x64/LLD.Link.Toolsets.win-x64.nuproj -o artifacts --force

# 交叉编译验证（TestNupkg 多目标，必须 -f）
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -f net10.0 -r linux-arm64 -o out/linux-arm64
dotnet publish test/TestPublish/TestNupkg.csproj -c Release -f net10.0 -r osx-arm64  -o out/osx-arm64
```

**换同号内容时要清缓存**：`TestNupkg` 通过 `$(PublishAotCrossVersion)` 引用主包；若用**同一个版本号**重打包，
务必删除 `.nuget/packages/publishaotcross.tools/<version>`，否则 NuGet 用旧内容。

---

## 9. 踩坑清单

- **toolsets 内容 gitignored**（`.xwin-store-tmp/`、`.macosx-sdk-tmp/`、`lld-link*`、`*.exe`）⇒ 只有维护者能重打包 ⇒ 这也是"发布顺序"必须 toolsets 先行、且 CI 无法自建它们的原因。
- **`NOTICE` / `LICENSE` 被所有包共享**（各 nuproj `Include="../../NOTICE"`）⇒ 改一次即改变**所有**包的内容。
- **`llvm-objcopy` 自递归**：包内 `objcopy` shim 与 PATH 前置曾导致 `exec` 自身、CI 卡死 —— 已修；若再动 shim，切记别再解析到自身。
- **binutils `objcopy` 单格式** ⇒ 跨架构剥离必须 `llvm-objcopy`（已内置）。
- **"同号不同内容"隐患**：本地 `artifacts/` 里的包可能被同名重打包过，和线上不一致；发布前务必确认。
- **`XWin.Store.*`（100/150MB）在 nuget.org 索引很慢**（可达 ~45 分钟）；主包/LLD 通常几分钟。
- **Windows 自带 bsdtar 无 xz/zstd**：解压 LLVM 包用 WSL（有 `xz`，`zstd` 可 `apt-get install`）。
- **本机 GitHub 下载被代理限速**（~0.3MB/s）：大文件尽量在 CI 拉，或走 `nuget.org`。
- **`AGENTS.md` / 本文件中的版本号会过期**：以 `toolsets/ToolsetsVersion.props` 为准。
- 密钥在 gitignored 的 `.env`（`nugetapikey` / `githubkey`）。

---

## 10. 本次会话要点（简版时间线）

1. 完成依赖升级并发布 `.12` 系列（`0.6.0.12` / `0.10.0.12` / `23.1.3.12` / `26.1.12`）。
2. CI 的 Linux job 卡死 → 定位为 **包内 `objcopy` shim 在 Linux 上 `exec` 自身**。
3. 修复 shim（消除自递归）→ 暴露"binutils 无法剥离 aarch64"→ 改为**尽力而为、不中断构建**。
4. 方案 A：**内置各宿主多格式 `llvm-objcopy`**（新增 `fetch-objcopy.yml` 在 CI 生成），`SetPath.cs` 前置；`objcopy` shim 保留为兜底。
5. 版本模型定型：`Revision` 全包共享；主包 = `前缀(1.0.1) + Revision`；`NOTICE` 补 `llvm-objcopy` 归属。
6. 发布 **`.13`**：主包 `1.0.1.13` + 8 个 toolset/store/SDK `.13`；本地端到端验证通过；CI 全绿。

---

## 附：常用直达

- 版本单一来源：`toolsets/ToolsetsVersion.props`
- 链路核心：`src/build/Crosscompile.targets`、`src/build/Scripts/SetPath.cs`
- 剥离相关：`src/build/objcopy`、`src/build/llvm-objcopy/`
- CI：`.github/workflows/main.yml`、`.github/workflows/fetch-objcopy.yml`
