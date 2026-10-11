# .NET Native AOT 跨平台编译指南：从一台机器到全平台构建

## 一、一个 CI 场景的痛点

假设你正在用 Windows 开发一个 .NET 服务，开启了 Native AOT 编译以获得最佳性能和单文件部署。需求来了：要同时发布 Windows x64、Windows arm64、Linux x64、Linux arm64、Alpine Linux (MUSL)，甚至 macOS（Apple Silicon）的二进制。

于是你在 CI 里写下：

```
dotnet publish -c Release -r linux-x64
```

然后看到这行红字：

```
error : Cross-OS native compilation is not supported.
```

Native AOT 的优势再大，跨平台这道坎过不去也是白搭。你要么为每个平台准备独立的构建机，要么花时间折腾交叉编译工具链。如果你也遇到过这个问题，这篇文章就是为你准备的。

## 二、Native AOT 的甜蜜与陷阱

.NET Native AOT（Ahead-of-Time Compilation）是 .NET 生态近年最重要的能力之一。它把 IL 代码提前编译成本地机器码，带来几个硬核好处：

- **启动极快**：无需 JIT 预热，毫秒级启动
- **内存更低**：没有 JIT 堆和运行时元数据
- **单文件部署**：一个 exe/elf，自包含无需运行时
- **体积更小**：裁剪未使用的代码，发布产物最小化

但 Native AOT 有一个先天性短板 ——**它依赖操作系统的原生链接器**：

- Windows 需要 MSVC 链接器（Visual Studio C++ 工具链）
- Linux 需要 ld / mold 以及 glibc 或 musl 的 sysroot
- macOS 需要 Xcode 的 ld64 **和 macOS SDK**

微软官方只支持**同平台构建**（Windows 上构建 Windows，Linux 上构建 Linux）。一旦试图跨平台，就会直接报错中止。

## 三、现有方案为什么不够好

为了解决这个问题，社区想了不少办法：

**方案一：安装 Visual Studio C++ 工具链**

- 只能在 Windows 上用
- 安装包超过 5GB，arm64 交叉编译支持有限
- CI 里装 VS 是最重的依赖

**方案二：Docker 交叉构建**

- 需要 Docker，Linux 容器配置繁琐
- 每次构建拉镜像，CI 时间长
- 不适合 Windows 目标，更无法产出 macOS 目标

**方案三：手动配置交叉编译工具链**

- 灵活但繁琐：需自行下载编译工具、配置环境变量、管理版本
- macOS 目标还要处理 Apple SDK 的获取与注入
- 在 CI 里需要额外脚本维护

这些方案有一个共同问题：**不够"开箱即用"**。

## 四、PublishAotCross.Tools 的解法

PublishAotCross.Tools 是一个 MSBuild 扩展 NuGet 包，它做的事情非常简单直白：**在 `dotnet publish` 时替换掉原生的链接器工具链，让你从任何平台构建任何平台**。

它不仅覆盖 Windows / Linux 目标，**现在也能从 Windows / Linux 直接交叉编译出 macOS（Apple Silicon）产物——不需要任何 Mac 机器**。

## 五、3 分钟上手

### 步骤 1：添加 NuGet 引用

在已开启 Native AOT 的项目中：

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <PublishAot>true</PublishAot>
    <InvariantGlobalization>true</InvariantGlobalization>
    <RuntimeIdentifiers>win-x64;win-arm64;linux-x64;linux-arm64;linux-musl-x64;linux-musl-arm64;osx-arm64</RuntimeIdentifiers>
  </PropertyGroup>

  <PropertyGroup>
    <DebugType>none</DebugType>
    <StripSymbols>false</StripSymbols>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="PublishAotCross.Tools" Version="0.6.0.11" />
  </ItemGroup>
</Project>
```

> 支持 `.NET 8+`（`net8.0`、`net9.0`、`net10.0` 均已验证），`<TargetFramework>` 按实际项目框架配置即可。
>
> `<DebugType>none</DebugType>` 和 `<StripSymbols>false</StripSymbols>` 是推荐搭配，这样发布的二进制已经足够精简，无需额外剥离符号的工具。

### 步骤 2：一条命令构建

```bash
# Windows 目标（无需 Visual Studio！）
dotnet publish -c Release -r win-x64
dotnet publish -c Release -r win-arm64

# Linux GNU 目标
dotnet publish -c Release -r linux-x64
dotnet publish -c Release -r linux-arm64

# Linux MUSL（Alpine）目标
dotnet publish -c Release -r linux-musl-x64
dotnet publish -c Release -r linux-musl-arm64

# macOS（Apple Silicon）目标 —— 不需要 Mac！
dotnet publish -c Release -r osx-arm64
```

所有命令在本机执行，无需切换操作系统、无需安装交叉工具链、无需管理员权限。

> **跨平台亮点**：这些命令不仅适用于 Windows 宿主。在 Linux 或 macOS 机器上执行 `dotnet publish -r win-x64` 同样可以直接产出 Windows 二进制；甚至 `dotnet publish -r osx-arm64` 也能在 Windows / Linux 上直接产出可在 Apple Silicon 运行的二进制。

### 进阶参数

- **指定 glibc 版本**：`/p:GlibcVersion=2.35`（用于兼容旧 Linux 发行版）
- **使用系统原生工具链**：`-p:AotPreferCustom=false`（默认 `true` 优先使用包内置的工具链；设为 `false` 则回退到系统原生的链接器——VS link.exe、系统 ld/gcc、Xcode ld64 等）
- **剥离符号**：如需更小的文件体积，可通过 `/p:StripSymbols=true` 剥离调试符号（包内已包含符号剥离工具，自动处理）
- **自定义 macOS SDK**：如需支持更多系统框架，可用 `/p:MacOSXSDKDir=<完整SDK路径>` 覆盖内置的精简 SDK

## 六、交叉编译覆盖矩阵

以下是经过 CI 验证的宿主 → 目标组合：

| 宿主 ↓\\ 目标 →         | win-x64 | win-arm64 | linux-gnu-x64 | linux-gnu-arm64 | linux-musl-x64 | linux-musl-arm64 | osx-arm64 |
| ------------------------- | ------- | --------- | ------------- | --------------- | -------------- | ---------------- | --------- |
| **Windows x64**     | ✅      | ✅        | ✅            | ✅              | ✅             | ✅               | ✅        |
| **Linux GNU x64**   | ✅      | ✅        | ✅            | ✅              | ✅             | ✅               | ✅        |
| **Linux GNU arm64** | ✅      | ✅        | ✅            | ✅              | ✅             | ✅               | ✅        |
| **macOS arm64**     | ✅      | ✅        | ✅            | ✅              | ✅             | ✅               | ✅        |

> **macOS 目标说明**：借助自动提供的精简 macOS SDK（`MacOSX.SDK` 包），**从 Windows / Linux 也能直接产出 macOS（arm64）二进制**，全程无需 Mac。产物可直接在 Apple Silicon 上运行（无需额外签名）。当前支持 `osx-arm64`。
>
> macOS arm64 宿主的编译能力与其它宿主一致；macOS 原生构建则走 Apple 原生工具链。

一个 Windows 或 Linux 环境，就能产出**全部**目标平台的 Native AOT 二进制（Windows + Linux(glibc/musl) + macOS arm64），无需任何 Mac。

## 七、技术原理浅析

### 工具链选择逻辑

PublishAotCross.Tools 自动检测宿主与目标平台，分别使用两套工具链路：

- **目标为 Windows** → XWin 链路：使用预打包的 Windows SDK 导入库（来自 xwin 项目）和 MSVC 兼容的 lld-link 链接器
- **目标为 Linux / macOS** → Zig 链路：利用 Zig 编译器的交叉编译能力，自动处理目标平台对应的 C 库和启动代码；macOS 目标额外注入精简 macOS SDK

#### XWin 链路（Windows 目标）

Native AOT 编译需要 MSVC 兼容的链接器以及 Windows SDK/CRT 导入库。包内预置了这些组件，构建时自动注入链接器参数：

```
/vctoolsdir:<store>/splat/crt
/winsdkdir:<store>/splat/sdk
/LIBPATH:<store>/splat/sdk/lib/ucrt/arm64/
/LIBPATH:<store>/splat/sdk/lib/um/arm64/
/LIBPATH:<store>/splat/crt/lib/arm64/
```

包内根据宿主平台自动选择对应架构的 lld-link 链接器，整个过程对开发者完全透明。

#### Zig 链路（Linux / macOS 目标）

当目标不是 Windows 时，使用 Zig 作为交叉编译器。自动确定目标三元组（如 `aarch64-linux-gnu`、`x86_64-linux-musl`、`aarch64-macos`），通过 `--target=<triple>` 参数以交叉编译模式运行。包内还内置了参数兼容包装器，确保 Native AOT 编译器生成的命令参数能正确传递给 Zig。

Zig 自带所有平台的 libc 和启动代码，无需宿主机预装任何交叉编译工具。**唯一的例外是 macOS**——Zig 不含 Apple 的 libSystem 与框架，需要额外提供 macOS SDK。

#### macOS SDK 是怎么"自动提供"的

macOS 目标需要 Apple SDK 里的系统库 stub（`.tbd`）与框架。为了做到"装上即用"，本项目：

1. 从公开来源获取 macOS SDK，**只保留 Native AOT 链接所需的一小部分**（`usr/include`、系统 `.tbd`、若干个框架的 `.tbd`），把约 1.9GB 的完整 SDK 压缩成约 **15MB 的 NuGet 包 `MacOSX.SDK`**；
2. 主包自动引用它，安装时即注入 `MacOSXSDKDir`，构建时由工具链自动传给 Zig（`-isysroot` + 显式框架/库搜索路径）；
3. 产物可直接在 Apple Silicon 运行，**无需代码签名**。

> 细节：Zig 不会从 `-isysroot` 自动推导框架搜索路径，需要显式传 `-F`/`-L`；Swift 运行时 stub 位于 `usr/lib/swift`。这些都已在包装器里处理。

#### 符号剥离

.NET Native AOT 默认的 `<DebugType>none</DebugType>` 和 `<StripSymbols>false</StripSymbols>` 已使发布产物不含调试符号，无需额外处理。

### 同平台优化

即使宿主和目标相同（如 Windows → Windows、Linux → Linux），PublishAotCross.Tools 也会自动接管工具链，使用包内置的编译器而非系统原生工具链。这样构建产物不依赖宿主机的 VS 版本或 GCC 版本，环境一致性更好，尤其适合 CI/CD。（macOS 原生构建例外，会回退到 Apple 原生工具链。）

通过 `-p:AotPreferCustom=false` 可回退到使用系统原生的工具链。

> **关键设计**：所有工具链文件（含 macOS SDK 精简包）都打包在 NuGet 中，`dotnet restore` 时自动解压。用户无需额外下载、安装或配置任何东西。

## 八、CI/CD 集成实战

现在**一个 runner 就能产出所有平台的二进制**——包括 macOS arm64，不再需要 macOS 构建机：

```yaml
name: Publish Native AOT

on:
  push:
    tags: [ 'v*' ]

jobs:
  build:
    strategy:
      matrix:
        rid:
          - win-x64
          - win-arm64
          - linux-x64
          - linux-arm64
          - linux-musl-x64
          - linux-musl-arm64
          - osx-arm64

    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 10.0.x

      - name: Publish for ${{ matrix.rid }}
        run: dotnet publish -c Release -r ${{ matrix.rid }}

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: app-${{ matrix.rid }}
          path: bin/Release/net10.0/${{ matrix.rid }}/publish/
```

**亮点**：无需为每个平台准备专用构建机，不用安装 Visual Studio、不用配置交叉编译器、不用维护 Docker 镜像、**连 Mac 都不需要**。一个 `ubuntu-latest` runner，就能产出包括 macOS arm64 在内的全部目标平台二进制。

## 九、开源与社区

PublishAotCross.Tools 基于 Apache-2.0 许可开源，可自由用于商业与闭源项目。

- GitHub 仓库：`DotNet-AGPL/PublishAotCross.Tools`（https://github.com/DotNet-AGPL/PublishAotCross.Tools）
- 通过 NuGet 安装：`dotnet add package PublishAotCross.Tools`
- 接受 Issue 反馈和 Pull Request 贡献

## 十、试试看

你的项目还在为跨平台 Native AOT 发愁吗？尤其是那个总也躲不开的"要出 macOS 就得有台 Mac"？

如果你是 .NET 开发者，正在用 Native AOT，或正准备尝试，**不妨花三分钟加一个 NuGet 包，看看一条命令构建全平台（含 macOS）是什么体验**。

在 GitHub 上搜索 PublishAotCross.Tools，点个 Star 支持一下，也欢迎提出你的使用反馈和建议。
