# 发布校验清单（nuget.org）

> 目标：一次发布 = 8 个新包（3 父包 / 4 个 `MacOSX.Symbols.Toolsets.*` 子包 / 主包）。
> 其余 8 个包（`XWin.Store.x64|arm64`、`LLD.Link.Toolsets.*` ×5、`MacOSX.SDK`）在 `.14` 已上线，**不重发**。

## 0. 前置条件（缺一不可）

- [ ] `main` 上最后一次 CI **全绿**（8~9 个 job 全 success）
- [ ] 工作区干净、与远端一致（`git status`、`git log --oneline -1`）
- [ ] `toolsets/ToolsetsVersion.props` 的 `Revision` / `PublishAotCrossVersionPrefix` 就是本次要发的版本
- [ ] `artifacts/` 里的 8 个包是**最近一次构建**的产物（不是上轮残留）

## 1. 版本与包清单

| # | 包 ID | 版本 | 大小 | 说明 |
|---|---|---|---|---|
| 1 | `MacOSX.Symbols.Toolsets.win-x64` | `23.1.3.14` | ~19 MB | 子包 |
| 2 | `MacOSX.Symbols.Toolsets.win-arm64` | `23.1.3.14` | ~18 MB | 子包 |
| 3 | `MacOSX.Symbols.Toolsets.linux-x64` | `23.1.3.14` | ~30 MB | 子包 |
| 4 | `MacOSX.Symbols.Toolsets.linux-arm64` | `23.1.3.14` | ~29 MB | 子包 |
| 5 | `MacOSX.Symbols.Toolsets` | `23.1.3.14` | 4 KB | 父包（metapackage） |
| 6 | `LLD.Link.Toolsets` | `23.1.3.14` | 4 KB | 父包 |
| 7 | `XWin.Store` | `0.10.0.14` | 4 KB | 父包 |
| 8 | `PublishAotCross.Tools` | `1.0.3.14` | ~10 MB | 主包 |

**推送顺序**：1–4（子包）→ 5–7（父包）→ 8（主包）。脚本已内置该顺序。

## 2. 自动校验（不推送）

```powershell
pwsh toolsets/publish-release.ps1 -Check
```

会做三件事，任一失败即 `exit 1`：

1. **内容**：8 个文件齐全；nuspec 的 `id`/`version` 与预期一致；打印大小 + SHA256（发布记录用）。
2. **依赖闭包**：每个依赖要么在本批（前面已推），要么已在 nuget.org；缺任何一个都会报红。
3. **远端状态**：每个包是 `new` 还是 `already published`（后者默认跳过）。

把输出里的 **SHA256 表**贴到发布记录里，作为"推的就是这个文件"的凭证。

## 3. 推送

API key 放 `.env` 的 `nugetkey=`（脚本自动读取），或显式传参：

```powershell
pwsh toolsets/publish-release.ps1 -Push
# 或
pwsh toolsets/publish-release.ps1 -Push -ApiKey <key>
```

- 已存在的版本默认**跳过**（幂等，失败可重跑）；确需覆盖同一版本号时才用 `-Force`。
- 中途失败会立刻停下并返回非 0，**从头重跑即可**（已推的会被跳过）。

## 4. 推送后验证

脚本最后一步会轮询 `https://api.nuget.org/v3-flatcontainer/<id>/index.json` 确认版本存在（索引可能延迟 1 分钟，可手动重跑 `-Check` 复核）。

### 4.1 冷启动还原（真·用户视角）

```bash
mkdir /tmp/pact-smoke && cd /tmp/pact-smoke
dotnet new console -f net10.0
dotnet add package PublishAotCross.Tools --version 1.0.3.14
# csproj 里补：<PublishAot>true</PublishAot>  <RuntimeIdentifiers>osx-arm64</RuntimeIdentifiers>
dotnet publish -r osx-arm64 -c Release
```

期望：

- 产物含 `TestNupkg.dSYM`（默认 `StripSymbols=true`）与剥离后的二进制；
- `-p:StripSymbols=false` 时无 dSYM、二进制明显更大。

### 4.2 dSYM 有效性（可选，macOS runner 或 WSL lldb）

```bash
target create ./TestNupkg
target symbols add ./TestNupkg.dSYM/Contents/Resources/DWARF/TestNupkg
image lookup -a <托管方法地址>     # 期望得到 Program.cs:行号
```

### 4.3 四个目标冒烟（推荐）

```bash
dotnet publish -r win-x64    -c Release
dotnet publish -r linux-x64  -c Release
dotnet publish -r osx-arm64  -c Release
dotnet publish -r osx-arm64  -c Release -p:StripSymbols=false   # 旧行为
```

## 5. 出问题怎么办

| 情况 | 处理 |
|---|---|
| 某个包推错/内容不对 | nuget.org **不允许删除已发布版本**，只能在页面上 **Unlist**；修好后 **bump 版本**（`Revision` 或主包前缀）重发 |
| 父包先于子包推 | 用户还原会 `NU1102`；补齐子包即可，无需回滚 |
| 主包依赖漏了父包 | 同上；重发主包（bump 前缀） |
| 索引未生效 | 等 1–2 分钟，`-Check` 复核；不影响还原（nuget.org 会先接受再索引） |

## 6. 发布后收尾

- [ ] 更新 `docs/PROJECT-HANDOVER.md` §3 的"线上历史"
- [ ] 如 `Revision` 变更：确认 13 个包都已重发（父包 3 + 子包 9 + 主包 1）
- [ ] 记录 SHA256 与发布时间（本清单第 2 步的输出）
