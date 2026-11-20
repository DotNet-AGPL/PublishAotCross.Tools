param(
  [string]$Version = "23.1.3",
  [ValidateSet("all", "win-x64", "win-arm64", "linux-x64", "linux-arm64")]
  [string]$Platform = "all"
)

$ErrorActionPreference = "Stop"

# dsymutil is the only tool that can turn the debug map of a cross-linked Mach-O into
# a .dSYM bundle: ld64 / ld64.lld never emit DWARF into the executable (verified: a
# Mach-O linked with -g still reports zero compile units), they only record an N_OSO
# debug map. Apple's dsymutil ships with Xcode and cannot be redistributed, so we take
# the LLVM upstream build for each supported host.
#
# PublishAotCross.Tools' Crosscompile.targets consumes the result: when
# StripSymbols=true and the target is macOS on a non-macOS host it runs
#   <dsymutil> --quiet <binary>
#   <llvm-objcopy> -x <binary>
# which is what ILCompiler's Apple branch does natively with Xcode's dsymutil/strip.

$sourceDir = "$PSScriptRoot\LLVM-Source"
$baseUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$Version"

$targets = @{
  "win-x64" = @{
    Archive = "clang+llvm-$Version-x86_64-pc-windows-msvc.tar.xz"
    Member  = "clang+llvm-$Version-x86_64-pc-windows-msvc/bin/dsymutil.exe"
    Bin     = "dsymutil.exe"
    PkgDir  = "MacOSX.SymbolTools/win-x64"
    Strip   = $false
  }
  "win-arm64" = @{
    Archive = "clang+llvm-$Version-aarch64-pc-windows-msvc.tar.xz"
    Member  = "clang+llvm-$Version-aarch64-pc-windows-msvc/bin/dsymutil.exe"
    Bin     = "dsymutil.exe"
    PkgDir  = "MacOSX.SymbolTools/win-arm64"
    Strip   = $false
  }
  "linux-x64" = @{
    # LLVM's Linux release builds are not stripped: dsymutil is ~136 MB until stripped.
    Archive = "LLVM-$Version-Linux-X64.tar.xz"
    Member  = "LLVM-$Version-Linux-X64/bin/dsymutil"
    Bin     = "dsymutil"
    PkgDir  = "MacOSX.SymbolTools/linux-x64"
    Strip   = $true
  }
  "linux-arm64" = @{
    Archive = "LLVM-$Version-Linux-ARM64.tar.xz"
    Member  = "LLVM-$Version-Linux-ARM64/bin/dsymutil"
    Bin     = "dsymutil"
    PkgDir  = "MacOSX.SymbolTools/linux-arm64"
    Strip   = $true
  }
}

# The bundled multi-format llvm-objcopy can strip foreign-architecture binaries, so the
# host's own binutils are not needed (and are single-format anyway).
$llvmObjcopy = "$PSScriptRoot\..\src\build\llvm-objcopy\win-x64\llvm-objcopy.exe"

function Get-XzPath {
  $cmd = Get-Command xz -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  # bsdtar shells out to `xz` for .tar.xz; Windows' bundled bsdtar has no liblzma, and
  # Git for Windows / MSYS2 / Chocolatey ship an xz that is usually not on PATH.
  $candidates = @(
    "C:\Program Files\Git\usr\bin\xz.exe",
    "C:\Program Files (x86)\Git\usr\bin\xz.exe",
    "C:\msys64\usr\bin\xz.exe",
    "$env:LOCALAPPDATA\Programs\Git\usr\bin\xz.exe",
    "C:\ProgramData\chocolatey\bin\xz.exe"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  return $null
}

function Test-Wsl {
  if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
  & wsl.exe -e true 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function ConvertTo-WslPath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  $drive = $full.Substring(0, 1).ToLowerInvariant()
  return "/mnt/$drive" + $full.Substring(2).Replace('\', '/')
}

# Extracts a single member from a .tar.xz, trying every decompressor route available on
# Windows: native bsdtar, bsdtar + xz on PATH, WSL, then full 7-Zip (7zr cannot read xz).
function Expand-TarMember([string]$Archive, [string]$Member, [string]$Destination) {
  $target = Join-Path $Destination $Member

  tar -xf $Archive -C $Destination $Member 2>$null
  if (Test-Path $target) { return $true }

  $xz = Get-XzPath
  if ($xz) {
    Write-Host "  (bsdtar has no liblzma; using xz from $(Split-Path $xz))"
    $saved = $env:PATH
    $env:PATH = "$(Split-Path $xz);$env:PATH"
    try { tar -xf $Archive -C $Destination $Member 2>$null } finally { $env:PATH = $saved }
    if (Test-Path $target) { return $true }
  }

  if (Test-Wsl) {
    Write-Host "  (using tar inside WSL)"
    $a = ConvertTo-WslPath $Archive
    $d = ConvertTo-WslPath $Destination
    & wsl.exe bash -c "tar -xf '$a' -C '$d' '$Member'" 2>$null
    if (Test-Path $target) { return $true }
  }

  $sevenZip = (Get-Command 7z, 7za -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $sevenZip -and (Test-Path "C:\Program Files\7-Zip\7z.exe")) { $sevenZip = "C:\Program Files\7-Zip\7z.exe" }
  if ($sevenZip) {
    Write-Host "  (decompressing with 7-Zip)"
    $tarDir = "$Destination\.tar"
    Remove-Item -Recurse -Force $tarDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $tarDir -Force | Out-Null
    & $sevenZip x $Archive "-o$tarDir" -y | Out-Null
    $tarFile = Get-ChildItem $tarDir -Filter *.tar | Select-Object -First 1
    if ($tarFile) {
      tar -xf $tarFile.FullName -C $Destination $Member 2>$null
      Remove-Item -Recurse -Force $tarDir -ErrorAction SilentlyContinue
      if (Test-Path $target) { return $true }
    }
  }

  return $false
}

$keys = if ($Platform -eq "all") { @($targets.Keys) } else { @($Platform) }

if (-not (Test-Path $sourceDir)) {
  New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
}

foreach ($key in $keys) {
  $t = $targets[$key]
  $outDir = "$PSScriptRoot\$($t.PkgDir)\tools"
  if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  }

  $archive = Join-Path $sourceDir $t.Archive
  $url = "$baseUrl/$($t.Archive)"

  if (-not (Test-Path $archive)) {
    $part = "$archive.part"
    Remove-Item $part -Force -ErrorAction SilentlyContinue
    Write-Host "[$key] Downloading $($t.Archive)..."
    curl.exe -fsSL --ssl-no-revoke $url -o $part
    if (-not $?) { throw "Download failed: $url" }
    Move-Item $part $archive -Force
  } else {
    Write-Host "[$key] Using cached $archive"
  }

  $extractDir = Join-Path $sourceDir ".extract-$key"
  Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

  Write-Host "[$key] Extracting $($t.Member)..."
  if (-not (Expand-TarMember -Archive $archive -Member $t.Member -Destination $extractDir)) {
    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    throw "[$key] Cannot extract '$($t.Archive)'. Install Git for Windows (provides xz.exe), WSL, or 7-Zip, then retry."
  }

  $binPath = Join-Path $outDir $t.Bin
  Copy-Item (Join-Path $extractDir $t.Member) $binPath -Force
  Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue

  $rawMb = [math]::Round((Get-Item $binPath).Length / 1MB, 1)

  if ($t.Strip) {
    if (Test-Path $llvmObjcopy) {
      Write-Host "[$key] Stripping $($t.Bin)..."
      & $llvmObjcopy --strip-all $binPath
      if ($LASTEXITCODE -ne 0) { throw "[$key] llvm-objcopy failed to strip $binPath" }
    } else {
      Write-Warning "[$key] $llvmObjcopy not found; shipping the unstripped $rawMb MB binary."
    }
  }

  $mb = [math]::Round((Get-Item $binPath).Length / 1MB, 1)
  Write-Host "[$key] -> $binPath ($rawMb MB raw, $mb MB shipped)"
}

Write-Host "Done. dsymutil $Version prepared for: $($keys -join ', ')"
