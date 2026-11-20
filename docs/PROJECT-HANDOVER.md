# 项目上手 / 交接文档（PROJECT-HANDOVER）

> 面向"新会话快速熟悉项目"。这里讲**原理、版本/发布模型、踩坑清单**；
> 结构速览与常用命令另见 `AGENTS.md` 与 `.github/copilot-instructions.md`。

---

## 1. 项目定位与仓库结构

`PublishAotCross.Tools` 是一组 MSBuild targets，让 **Native AOT 交叉编译**（在 Windows/Linux 上产出 linux / osx / win 各平台的可执行文件）开箱即用。

```
toolsets/                                 各平台"内容包"（作为 NuGet 被主包引用）
├── ToolsetsVersion.props                 ★ 全仓库版本的单一来源
├── XWin.Store/                           父包 → x64 / arm64 导入库 store
│   ├── XWin.Store.x64 / .arm64           子包（.xwin-store-tmp/ 内容 gitignored）
├── LLD.Link.Toolsets/                    父包 → 5 个平台的 lld-link（无内容）
│   ├── LLD.Link.Toolsets.win-x64 / .win-arm64
│   ├── LLD.Link.Toolsets.linux-x64 / .linux-arm64
│   └── LLD.Link.Toolsets.osx-arm64       子包（tools/lld-link.zip.partNN 随仓库提交（≤25MB 分片，打包时合并））
├── MacOSX.Symbols.Toolsets/                   父包 → 4 个宿主的 LLVM dsymutil
│   ├── win-x64 / win-arm64 / linux-x64 / linux-arm64   子包（tools/ gitignored，脚本生成）
├── MacOSX.SDK                            过滤后的 macOS SDK 子集（osx 交叉用，无子包）
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
- 打印"选了哪条链"的诊断信息（受 `PublishAotCrossDebug` 控制，**默认 `true`**；`/p:PublishAotCrossDebug=false` 可关闭）。

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
<ZigVersion>0.17.1.1</ZigVersion>
<XWinVersion>0.10.0</XWinVersion>
<LLDVersion>23.1.5</LLDVersion>
<MacOSXSDKVersion>26.1</MacOSXSDKVersion>
<Revision>15</Revision>                                  <!-- 全包共享 -->
<PublishAotCrossVersionPrefix>1.0.3</PublishAotCrossVersionPrefix>
<PublishAotCrossVersion>$(PublishAotCrossVersionPrefix).$(Revision)</PublishAotCrossVersion>
```

| 包 | 版本公式 |
| --- | --- |
| `PublishAotCross.Tools` | `$(PublishAotCrossVersionPrefix).$(Revision)` → 如 `1.0.3.14` |
| `XWin.Store`（父）/ `XWin.Store.*` | `$(XWinVersion).$(Revision)` |
| `LLD.Link.Toolsets`（父）/ `LLD.Link.Toolsets.*` | `$(LLDVersion).$(Revision)` |
| `MacOSX.SDK` | `$(MacOSXSDKVersion).$(Revision)` |
| `MacOSX.Symbols.Toolsets`（父）/ `.Symbols.Toolsets.*` | `$(LLDVersion).$(Revision)` |

要点：
- **主包只依赖 4 个父包 + 6 个 Zig 包**（共 11 行）；子包（`.<rid>`）由父包引用。新增平台只改父包一行。
- 父包（`XWin.Store` / `LLD.Link.Toolsets` / `MacOSX.Symbols.Toolsets`）**不含二进制**，CI 可在无内容的情况下直接打包。
- **`Revision` 全包共享**：主包依赖的就是 `…$(Revision)`。改动 `Revision` ⇒ **13 个包都要重发**（toolsets 通常只是"换版本号"）。
- **主包 = 前段 + Revision**：前段（`PublishAotCrossVersionPrefix`）可单独调整。
- **发布顺序：先 3 个父包 + 其余子包/toolset，最后主包**。否则用户还原与 CI 都会 `NU1102`（找不到 `.Revision` 版本）。
- 线上历史：`0.6.0.5 … 0.6.0.12` → `1.0.1.13` → `1.0.2.13`（仅主包变化：只升"前段"，toolset 仍 `.13`）
  → **`1.0.3.14`（2026-11-20 已发布）**：新增 `MacOSX.Symbols.Toolsets*`（父包 + 4 子包）与
  `LLD.Link.Toolsets` / `XWin.Store` 两个父包；主包改为只依赖父包（19 行 → 11 行）；
  macOS 交叉默认 `StripSymbols=true`（生成 `.dSYM` + 剥离）。
  发布脚本 `toolsets/publish-release.ps1`，清单 `docs/RELEASE-CHECKLIST.md`。

---

## 4. macOS 交叉（非 macOS 宿主 → osx-arm64）

- `MacOSX.SDK` 包（过滤后的 SDK 子集，约 14.7MB）自动 `PackageReference` ；其 `buildTransitive/MacOSX.SDK.props` 给出 `MacOSXSDKDir`。
- 无需 Mac：Zig 链接 + 注入的 SDK 搜索路径即可产出 Mach-O。
- **`StripSymbols` 语义**：`RuntimeIdentifier.StartsWith('osx') && !HostRuntimeIdentifier.StartsWith('osx')`
  ⇒ 默认 **`true`**（与 ILC 对非 Windows 目标的默认一致，也和 macOS 原生构建一致）：
  由本包用 `MacOSX.Symbols.Toolsets` 的 LLVM `dsymutil` + `llvm-objcopy -x` 复刻
  `dsymutil && strip -no_code_signature_warning -x`；`/p:StripSymbols=false` 可关闭。
  产物目录会多出 `<App>.dSYM`（与原生相同），发布时记得排除。
- **Mach-O 里没有 DWARF**：链接器（ld64 / zig 内置的 ld64.lld）只写 **N_OSO debug map**，
  不写 `__DWARF` 段。实测：未剥离的 Mach-O（即使 `-g` 链接）用 `llvm-dwarfdump` 查 CU = 0
  ⇒ **没有 `.dSYM` 就完全没有文件名/行号**（"不剥离"并不等于"可调试"）。
- 已知**无害**告警：`unable to open library directory "/usr/lib/swift"`、以及 SDK 内 `PrivateFrameworks` 目录不存在（过滤子集未含）。由 `-L`/`-F` 实际路径兜住。

---

## 5. 符号剥离（llvm-objcopy 与 objcopy shim）★

**ILCompiler 的默认**（`microsoft.dotnet.ilcompiler`）：
- 非 Windows 目标 `StripSymbols` 默认 `true`。
- 链接器为 clang 时，`ObjCopyName` 优先 `llvm-objcopy`，回退 `objcopy`（`Microsoft.NETCore.Native.Unix.targets`）。
- 宿主的 binutils `objcopy` 是**单格式**的：x64 上的它**无法剥离 aarch64 ELF** → 必须用多格式的 `llvm-objcopy`。

**本项目的做法**
- 随包内置各宿主 `llvm-objcopy`（LLVM 23.1.5）：`src/build/llvm-objcopy/{linux-x64,linux-arm64,osx-arm64}/llvm-objcopy` + `win-x64/llvm-objcopy.exe`，**随仓库提交**。
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

### 5.1 macOS 交叉的 dSYM（MacOSX.Symbols.Toolsets）★

**为什么必须单独打包 `dsymutil`**
- Xcode 的 `dsymutil`/`strip` 不可再分发；LLVM 上游的 `dsymutil` 是唯一替代（Apache-2.0 WITH LLVM-exception）。
- 它静态链了 LLVM，体积大：win 52.2MB/宿主；linux 未 strip 136MB（我们 strip 到 94.6MB，WSL 实测仍可运行）。

**包结构**（`toolsets/MacOSX.Symbols.Toolsets/`）
- 父包 `MacOSX.Symbols.Toolsets`（metapackage）→ 依赖 4 个子包
- 子包 `MacOSX.Symbols.Toolsets.<rid>`（win-x64 / win-arm64 / linux-x64 / linux-arm64），各自 `tools/dsymutil[.exe]` + `buildTransitive/*.props`
- 4 个子包**分别**设置 `MacOSXSymbolsToolsets<Host>Dir`（不能共用同一个属性，否则导入顺序决定胜者 → 取错宿主）；主 targets 按 `HostRuntimeIdentifier` 选。
- 二进制不入库（gitignored），由 `toolsets/download-macosx-symbols.ps1` 生成；nuproj 缺文件直接 `Error` 提示。
  - 该脚本对 `.tar.xz` 依次尝试：原生 bsdtar → PATH 上的 `xz`（Git for Windows/MSYS2）→ WSL → 完整 7-Zip（`7zr` 不支持 xz）。

**主包侧**（`src/build/Crosscompile.targets`）
- 属性：`_PublishAotCrossMacOSStrip`（`osx` 目标 + 非 macOS 宿主 + `StripSymbols=true`，**默认为 true**）。
- **必须先"关掉 ILC 的 Apple 分支"**：ILC 的 `Microsoft.NETCore.Native.targets:413` 只要 `StripSymbols=true` 就会跑
  `dsymutil … && strip -no_code_signature_warning -x …`。而 `dotnet publish -p:StripSymbols=true` 是**全局属性**，
  评估期赋值**无法覆盖**（`src/build/Crosscompile.targets` 里那句 `<StripSymbols Condition=…>false</StripSymbols>` 只对 csproj 内设置有效）。
  因此用目标 `PublishAotCrossMacOSStripGuard`（`BeforeTargets="SetupOSSpecificProps"`）在**执行期**赋 `StripSymbols=false`
  —— 目标执行期的赋值可以覆盖全局属性（已实测）。
  不要用"改 PATH 放 no-op shim"的办法：MSBuild 多节点/服务器下进程环境变量不可靠（已踩）。
- 目标 `PublishAotCrossMacOSStrip`（`AfterTargets="LinkNative"`）：
  1. `dsymutil --quiet <bin>` ⇒ `<bin>.dSYM`（与二进制同目录、同 UUID）
  2. `llvm-objcopy -x <bin>` ⇒ 等价 Apple `strip -x`（2.05MB→1.09MB，外部符号 95 个全保留）
  3. `<bin>.stripped` 标记文件（`Inputs`/`Outputs`）保证增量构建不重复剥离——否则第二次会对已剥离的二进制跑
     dsymutil，把真实 dSYM 覆盖成 24KB 的空壳。
- **顺序不可反**：`-x` 会删掉 dsymutil 需要的 debug map。
- 两个 `Exec` 需 `IgnoreStandardErrorWarningFormat="true"`：dsymutil 固定输出 92 条
  `unable to open object file: invalid argument`（91 个 `libRuntime.WorkstationGC.a(member)` + `libbootstrapper.o`），
  `--quiet` 压不掉；不忽略会被当成 MSBuild warning（`TreatWarningsAsErrors` 会炸）。
- 想压掉这 92 行噪音用 `StandardErrorImportance="Low"`（注意：MSBuild `Exec` 会**丢弃命令行里的 `2>file` 重定向**，实测无效）。

**实测结论（WSL lldb 19 加载 Mach-O）**
- dSYM 有效：`image lookup -a 0x100002ed0` → `Interop.IOErrors.cs:16`；`Program.cs:3` 命中；
  `breakpoint set --file Program.cs --line 3` 可解析。
- 托管代码完整（hello-world：3,782 subprogram / 19,427 行号表行）；runtime C++ 只有符号名（上述 92 条 warning）。
- 剥离后：`image lookup -n <托管方法>` 失效（名字查找走 symtab），地址/源码断点/回溯正常。
- 行号表内是构建机绝对路径（`E:\…`）⇒ macOS 上通常要 `target.source-map`；`.dSYM` 不宜公开分发。
- 非 macOS 的 lldb 不自动加载 dSYM：`target symbols add <bin>.dSYM/Contents/Resources/DWARF/<bin>`
  （传 `.dSYM` 目录会报 `invalid module path`）。

**打包/验证（1.0.3.14 + MacOSX.Symbols.Toolsets 23.1.5.14 实测）**
- 4 个子包：win-x64 19.3MB、win-arm64 18.2MB、linux-x64 30.5MB、linux-arm64 29.4MB（共 ≈97MB）；父包 4KB（仅依赖）。
- 主包依赖 4 个子包（nuspec 已核对），`StripSymbols=true` 端到端：exit=0、`<bin>.dSYM` 1.5MB、二进制 1.04MB、**0 条 warning**，
  lldb 解析出 `Program.cs:3`。
- ⚠️ **重打同版本号后必须 `dotnet build-server shutdown` + 清 `.nuget/packages/publishaotcross.tools/<ver>`**，
  否则 MSBuild 服务器会复用旧评估：现象是"新加的 target 报 MSB4057 不存在 / 改动像没生效"（本项目已踩）。
- ⚠️ 切换 `DebugType` 后建议先 `-t:Rebuild` 或清 `obj/bin`：ILC 的增量判定不含 `-g` 参数，可能复用没有 DWARF 的 `.o`，
  导致生成的 dSYM 只有 24KB 空壳。

---

## 6. CI

`.github/workflows/main.yml`（触发：`pull_request` + `workflow_dispatch`）
- `sdk`：下载并过滤 macOS SDK → 打 `MacOSX.SDK` 包 → 上传 artifact。
- `symbols`：抽出 4 个宿主的 `dsymutil`（`tools/*/tools` 走 actions/cache，命中就跳过 ~5GB 的 LLVM 归档下载）→
  打 `MacOSX.Symbols.Toolsets` 父包 + 4 子包 → 上传 artifact。
- `metapkgs`：重建 `XWin.Store`（xwin splat，1.4 GB store 走 actions/cache）+ 从随仓库提交的 `tools/lld-link.zip.partNN`（打包时合并）
  打出 5 个 LLD 子包 + 2 个 XWin 子包 + 3 个父包 → 上传 artifact。
- `build`（矩阵 Windows/Linux/macOS）：把 `MacOSX.SDK` + `MacOSX.Symbols.Toolsets*` 放入本地 `artifacts` feed，
  **本地打主包**（合成版本 `0.0.0-ci`），再交叉编译 `TestNupkg`。
- `cross_osx_arm64`（Windows 宿主）：**默认产物**（必须带 `.dSYM`）+ `-p:DebugType=portable -p:StripSymbols=false`（对照基准）
  + `-p:DebugType=portable -p:StripSymbols=true`（断言 dSYM ≥100KB 且比基准小）；每次切换前清 `bin/obj`
  （ILC 增量判定不含 `-g`）。
- `run_osx_arm64`（macOS runner）：分别运行普通产物与**剥离后**的产物 ⇒ 证明 `llvm-objcopy -x` 后仍可执行。
- `validate`：跑 linux-x64。
- CI **不推送** NuGet；`XWin.Store.*` / `LLD.*` 内容 gitignored，CI 只能从 feed **还原**它们。
  ⇒ **改 `Revision` 后必须先发布这些包，CI 才能跑通。**
  `MacOSX.SDK` / `MacOSX.Symbols.Toolsets*` 例外：它们由 CI 自己从源码/归档构建。

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

1. 完成依赖升级并发布 `.12` 系列（`0.6.0.12` / `0.10.0.12` / `23.1.5.12` / `26.1.12`）。
2. CI 的 Linux job 卡死 → 定位为 **包内 `objcopy` shim 在 Linux 上 `exec` 自身**。
3. 修复 shim（消除自递归）→ 暴露"binutils 无法剥离 aarch64"→ 改为**尽力而为、不中断构建**。
4. 方案 A：**内置各宿主多格式 `llvm-objcopy`**（新增 `fetch-objcopy.yml` 在 CI 生成），`SetPath.cs` 前置；`objcopy` shim 保留为兜底。
5. 版本模型定型：`Revision` 全包共享；主包 = `前缀 + Revision`（如 `1.0.2.13`）；`NOTICE` 补 `llvm-objcopy` 归属。
6. 发布 **`.13`**：主包 `1.0.1.13` + 8 个 toolset/store/SDK `.13`；本地端到端验证通过；CI 全绿。
7. 诊断便利化：`SetPath.cs` 的调试开关由环境变量改为 **MSBuild 属性 `PublishAotCrossDebug`**（默认 `true`），并打印"选了哪条链"；剔除原误导性横幅。仅主包变化 → 发布 **`1.0.2.13`**（只升前段，toolset 不动）。

---

## 附：常用直达

- 版本单一来源：`toolsets/ToolsetsVersion.props`
- 链路核心：`src/build/Crosscompile.targets`、`src/build/Scripts/SetPath.cs`
- 剥离相关：`src/build/objcopy`、`src/build/llvm-objcopy/`
- CI：`.github/workflows/main.yml`、`.github/workflows/fetch-objcopy.yml`
