# 原生运行时依赖的可移植性：VC++ / glibc / libstdc++ / libgcc_s 的坑与解法

> 一份与具体项目无关的“踩坑沉淀”。适用于任何**把原生二进制打包进 NuGet / 容器 / 分发包**的项目
> （尤其是与 .NET `AppLocalIcu`、`DllImport`、`dlopen` 相关的场景）。
>
> 核心问题只有一句话：**构建机上的依赖，会悄悄泄漏进制品，然后在“干净”的目标机上炸**。

---

## 0. 先理解加载器（决定一切）

### Windows
.NET 的 `AppLocalIcu` 用：
```csharp
NativeLibrary.TryLoad("icuuc<ver>.dll", typeof(object).Assembly,
    DllImportSearchPath.ApplicationDirectory | DllImportSearchPath.System32, out _);
```
- **只搜索「应用目录 + System32」**；并且因为它走 `LOAD_LIBRARY_SEARCH_*` 语义，
  **被加载 DLL 的依赖也只在这两个位置解析**。
- 所以：native DLL（及其依赖）**必须位于应用目录**（或系统目录）。

### Linux / macOS
```csharp
dlopen("libicuuc.so.<ver>", ...)   // 先加载 libicudata，再 libicuuc、libicui18n
```
- 按**精确文件名**加载（版本 `77.1` → `libicuuc.so.77.1`）。
- 搜索「应用目录」；**依赖**（该 `.so` 的 `NEEDED`）按 `RPATH/RUNPATH`、`LD_LIBRARY_PATH` 等常规规则解析。

### 推论（贯穿全文）
1. 自包含（SCD）**只带 .NET 运行时，不带操作系统的系统库**（libc/libm/libdl/libstdc++/libgcc/libssl/…）。
2. 目标机的**发行版、glibc 版本、libstdc++ 版本、是否装了 VC++ Redist**，都会决定能不能加载。
3. **验证必须在“最接近生产、且尽量干净”的发行版/镜像上做**，官方 runtime 镜像“太全”，会掩盖问题。

---

## 1. Windows：MSVC 运行库（VC++）依赖

### 症状
```
Process terminated. Failed to load app-local ICU: icuuc77.1.dll
```
或加载 `icuuc77.dll` 时 `0xC0000005`（访问冲突）在 `GlobalizationMode.InitICUFunctions`。

### 根因
- 用 MSVC 以 **`/MD`（动态 CRT）** 构建的 DLL 会 `IMPORT`：
  `msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`。
- 目标机没装 **VC++ 2015–2022 可再发行组件（x64/x86/arm64）** → `LoadLibrary` 失败。

### 诊断
1. 扫描 DLL 的导入字符串：
   ```powershell
   $ascii = [System.Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dll)).ToLowerInvariant()
   foreach ($dep in 'msvcp140','vcruntime140','vcruntime140_1') { if ($ascii -match $dep) { "needs $dep" } }
   ```
2. 看依赖闭包：`icuuc/icuin` 引用的 CRT DLL **是否都在应用目录**。

### 解决方案
**方案 A（推荐）：随包做 app-local CRT**
- 从 VS 的 `VC/Redist/MSVC/<ver>/<arch>/Microsoft.VC143.CRT/` 复制：
  `msvcp140.dll, msvcp140_1.dll, msvcp140_2.dll, msvcp140_atomic_wait.dll, msvcp140_codecvt_ids.dll, vcruntime140.dll, vcruntime140_1.dll`
- 微软许可**允许**以 app-local 方式随应用再分发这些文件（在 `THIRD-PARTY-NOTICES` 里声明）。

**方案 B：静态 CRT（`/MT`）**
- 消除 CRT 依赖，但需改 ICU 工程文件（其 `RuntimeLibrary` 硬编码为 `MultiThreadedDLL`），
  且**每个 DLL 各带一份 CRT 状态**，跨模块分配/释放有风险。

### 两个必踩的坑
1. **必须取“与工具链匹配”的 redist 版本**。
   若在 VS2022 用 `Select -First 1` 拿到 VS2019 的 `msvcp140`（14.29），会与 VS2022 构建的 DLL
   **ABI 不兼容 → 加载即崩**。做法：**匹配 MSVC 工具链版本，否则取最高版本**，并加“不得低于工具链”的守卫。
2. **必须校验架构**。
   arm64 的 redist 目录里可能**混入 x64 的 `vcruntime140_1.dll`**；把它打进 arm64 包是错的。
   做法：读取每个 DLL 的 PE `Machine`，与目标架构不符就**跳过**；ARM64 上很多库根本不 `IMPORT vcruntime140_1`。

### 回归验证
- 导入闭包检查（缺一即失败）。
- 在**没装 VC++ Redist** 的环境里运行（或检查应用目录已含全部 CRT DLL）。

---

## 2. Linux（glibc）：符号版本地板

### 症状
```
Failed to load app-local ICU: libicuuc.so.77.1
# 直接 dlopen 时可见：version `GLIBC_2.38' not found
```

### 根因
在**较新发行版**（如 ubuntu-24.04 / glibc 2.39）上构建，导出物绑定了新 glibc 的符号版本：
- C23 的 `__isoc23_strtol` / `__isoc23_strtoul`（glibc 2.38 引入），以及 `fmod@GLIBC_2.38`。

于是：**在 glibc < 2.38 的目标机（Debian 12=2.36、Ubuntu 22.04=2.35、RHEL9=2.34…）直接加载失败。**

### 诊断（确定性）
```bash
readelf -V libicuuc.so.77.1 | sed -n '/Version needs section/,/^$/p'
```
看 `libc.so.6` / `libm.so.6` 需要的最高 `GLIBC_2.x`。

### 解决方案：**老基线构建**
- 在**尽可能老的 glibc** 基线里构建（推荐 **AlmaLinux 8 = glibc 2.28**，用 `gcc-toolset-13` 保持新编译器）：
  ```bash
  docker run --rm -v "$PWD:/work" -w /work almalinux:8 bash -c '
    dnf install -y gcc-toolset-13-gcc-c++ make curl
    dnf install -y patchelf || { dnf install -y epel-release && dnf install -y patchelf; }
    source /opt/rh/gcc-toolset-13/enable
    ./scripts/build-icu-linux.sh 77.1 linux-x64
  '
  ```
- 备选基线：`debian:11`（2.31）、`ubuntu:20.04`（2.31）、`manylinux_2_28`（2.28）。
- **注意**：glibc **不能**静态链进 `.so`（`libc` 永远动态），所以只能靠“老基线”压低地板。

### 回归验证
- `readelf` 复核最高 `GLIBC_2.x` ≤ 目标地板。
- 在**最低地板发行版**上实际运行/`dlopen`。

---

## 3. Linux：`libstdc++` / `libgcc_s` 依赖

### 症状
```
error while loading shared libraries: libstdc++.so.6: cannot open shared object file
# 或：version `GLIBCXX_3.4.30' not found
```

### 根因
C/C++ 原生库默认为 **`/MD` 等价物**：动态链接 `libstdc++.so.6`（以及 `libgcc_s.so.1`）。
极简镜像（distroless、裸 Alpine）可能**没有**它们，或版本过旧（`GLIBCXX_3.4.30` = GCC 12+）。

### 解决方案
- **静态链接 C++ 运行库**（推荐，去依赖）：
  ```bash
  export LDFLAGS="$LDFLAGS -static-libstdc++ -static-libgcc"
  ```
- **或**：随包带 `libstdc++.so.6` + `libgcc_s.so.1`，并给 `.so` 加 `-Wl,-rpath,'$ORIGIN'`
  （让依赖在同目录解析）。
- 权衡：静态方式会让**每个 `.so` 各带一份 C++ 运行时**（各自静态状态）。**但 Linux 的 `malloc/free` 来自共享的 glibc，
  “跨模块分配/释放”的风险远小于 Windows 的 `/MT` 私有堆**，实际风险温和。

### 回归验证
```bash
readelf -d libicuuc.so.77.1 | grep -E 'NEEDED.*(libstdc\+\+|libgcc_s)' && echo "仍有 C++ 运行库依赖"
```

---

## 4. Linux（musl）：库间 `NEEDED` 与 SONAME（最隐蔽的一个）

### 症状
- **glibc 正常，musl（Alpine）加载失败**：
  ```
  Failed to load app-local ICU: libicuuc.so.77.1
  ```

### 根因
- 构建产物：文件名是 `libicuuc.so.77.1`，但其 `SONAME` 是 `libicuuc.so.77`；
  `libicuuc` 的 `NEEDED` 因此写作 **`libicudata.so.77`**（major）。
- 而包里**只有** `libicudata.so.77.1`（没有 `.so.77`）。
- **glibc** 靠“`AppLocalIcu` 先 `dlopen` 了 `libicudata.so.77.1`，按 SONAME 注册”从而解析成功；
- **musl 不做这种“已加载库的 SONAME 匹配”** → 找不到 `libicudata.so.77` → `dlopen` 失败。

### 解决方案：`patchelf`
把库间 `NEEDED` 改成**精确文件名**，并加 `$ORIGIN`：
```bash
for lib in libicuuc libicui18n libicudata; do
  f="runtimes/$rid/native/${lib}.so.${VER}"        # 例：.so.77.1
  patchelf --set-soname "${lib}.so.${VER}" "$f"
  patchelf --replace-needed "libicudata.so.${MAJOR}" "libicudata.so.${VER}" "$f" || true
  patchelf --replace-needed "libicuuc.so.${MAJOR}"   "libicuuc.so.${VER}"   "$f" || true
  patchelf --set-rpath '$ORIGIN' "$f"
done
```
> Alpine 装 `patchelf`：`apk add --no-cache patchelf`；Alma/EL8：`dnf install -y patchelf`（必要时先 `epel-release`）。

### 回归验证
```bash
readelf -d libicuuc.so.77.1 | grep -E 'NEEDED|RUNPATH'
# 期望：NEEDED 指向 libicudata.so.77.1（精确名）；RUNPATH=$ORIGIN
```
再在**裸 `alpine:3.20`** 里 `dlopen` 验证。

---

## 5. Alpine：官方 .NET 镜像默认 invariant

官方 Alpine .NET 镜像设置了：
```
DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true
```
**该环境变量优先**，会让 ICU 不被使用（表现为“只有 invariant 文化”）。需要覆盖：
```dockerfile
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
```

---

## 6. 澄清：自包含（SCD）≠ 零宿主依赖

SCD **只打包 .NET 运行时**，**不含**操作系统的系统库。以 musl SCD 为例（`readelf -d`）：
```
IcuJitTest (apphost)  -> libstdc++.so.6  libgcc_s.so.1  libc.musl
libcoreclr.so         -> libgcc_s.so.1   libstdc++.so.6 libc.musl
libSystem.Native.so   -> libc.musl                    (纯 C)
你的原生库            -> (仅彼此的精确名) libc.musl    (若按本文处理，则无 C++ 运行库依赖)
```
- .NET 的 C++ 组件（含 apphost）自身需要 `libstdc++`/`libgcc_s`；
- 所以**裸 Alpine（无 libstdc++）**能跑 AOT（纯 C），但 **JIT 起不来**——这是 .NET 运行时的要求，不是你的库的问题；
- 官方安装途径会自动装上这些：`apt/dnf install dotnet-runtime-*` 把 `libstdc++6 / libgcc-s1 / libicuNN / libssl / zlib / tzdata` 声明为依赖；官方镜像也在 Dockerfile 里装了。

---

## 7. 验证方法集合（可直接复制）

### 7.1 Windows：导入闭包
```powershell
$runtime = 'msvcp140','msvcp140_1','msvcp140_2','msvcp140_atomic_wait','msvcp140_codecvt_ids','vcruntime140','vcruntime140_1'
foreach ($f in 'icuuc77.dll','icuin77.dll') {
  $a = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($f)).ToLower()
  foreach ($r in $runtime) { if ($a -match "$r\.dll" -and -not (Test-Path "$r.dll")) { "MISSING: $f -> $r.dll" } }
}
```

### 7.2 Linux：地板 / NEEDED / rpath
```bash
readelf -V  libicuuc.so.77.1 | grep -oE 'GLIBC_2\.[0-9]+' | sort -uV | tail -1   # 最高 glibc 需求
readelf -d  libicuuc.so.77.1 | grep -E 'NEEDED|RUNPATH'
```

### 7.3 原生发行版 dlopen（不经 .NET，最干净）
```python
# dlopen-check.py <dir> <ver>
import ctypes, os, sys
d, v = sys.argv[1], sys.argv[2]
for n in (f"libicudata.so.{v}", f"libicuuc.so.{v}", f"libicui18n.so.{v}"):
    ctypes.CDLL(os.path.join(d, n))
print("dlopen OK")
```
```bash
docker run --rm -v "$PWD:/repo:ro" -v "$PWD/native:/libs:ro" alpine:3.20 \
  sh -c 'apk add --no-cache python3 >/dev/null; python3 /repo/dlopen-check.py /libs 77.1'
```

### 7.4 JIT / AOT 冒烟（在原生发行版上）
```bash
# glibc：self-contained 在 debian:12 上跑
dotnet publish app.csproj -c Release -r linux-x64 --self-contained -o out
docker run --rm -v "$PWD/out:/app" -w /app --entrypoint sh debian:12 -c './App'
# musl：AOT 产物在裸 alpine 上跑
docker run --rm -v "$PWD/aot:/app" -w /app --entrypoint sh alpine:3.20 -c './App'
```

### 7.5 在“最低地板”发行版上验证
- glibc：**`almalinux:8`（glibc 2.28）** —— 正好卡在你支持的最低地板。

---

## 8. 清单（Checklist）

- [ ] **Windows**：随包 CRT 取自**工具链匹配版本**；**逐 DLL 校验架构**；导入闭包完整（缺一即失败）。
- [ ] **glibc**：在**老基线**（AlmaLinux 8 / 2.28）构建；`readelf` 最高 `GLIBC_2.x` ≤ 目标地板。
- [ ] **无 `libstdc++`/`libgcc_s` 依赖**（`-static-libstdc++ -static-libgcc`）或已随包 + `$ORIGIN`。
- [ ] **musl**：库间 `NEEDED` = **精确文件名** + `RUNPATH=$ORIGIN`；在**裸 `alpine`** 上 `dlopen` 通过。
- [ ] **Alpine**：文档写明需 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`。
- [ ] **回归防护**：CI 里跑静态检查（地板/NEEDED/rpath）+ 原生发行版 `dlopen` + JIT/AOT 冒烟。

---

## 9. 经验总结（一句话版）

1. **“在我机器上能跑” ≠ “在目标机能跑”**：构建机依赖会泄漏。
2. **能静态就静态**（libstdc++/libgcc），**不能静态的（libc）就压低构建基线**。
3. **跨库依赖用精确文件名 + `$ORIGIN`**，别赌加载器的 SONAME 匹配（musl 不赌）。
4. **验证要在“原生且干净”的发行版上做**，最低地板发行版最能暴露问题。
5. **把上面这些做成 CI 的静态+运行时冒烟**，否则下一个平台会再踩一次。
