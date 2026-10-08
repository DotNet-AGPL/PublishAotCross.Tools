param(
  [string]$Version = "23.1.3",
  [ValidateSet("all", "win-x64", "win-arm64", "linux-x64", "linux-arm64", "osx-arm64")]
  [string]$Platform = "all"
)

$ErrorActionPreference = "Stop"

# LLVM release assets are .tar.xz archives. We extract the single lld binary
# (lld-link.exe on Windows, lld elsewhere, renamed to lld-link) and repackage
# it as tools/lld-link.zip for each host platform package.

$sourceDir = "$PSScriptRoot\LLVM-Source"
$baseUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$Version"

$targets = @{
  "win-x64" = @{
    Archive = "clang+llvm-$Version-x86_64-pc-windows-msvc.tar.xz"
    Member  = "clang+llvm-$Version-x86_64-pc-windows-msvc/bin/lld-link.exe"
    Bin     = "lld-link.exe"
    PkgDir  = "LLD.Link.Toolsets.win-x64"
  }
  "win-arm64" = @{
    Archive = "clang+llvm-$Version-aarch64-pc-windows-msvc.tar.xz"
    Member  = "clang+llvm-$Version-aarch64-pc-windows-msvc/bin/lld-link.exe"
    Bin     = "lld-link.exe"
    PkgDir  = "LLD.Link.Toolsets.win-arm64"
  }
  "linux-x64" = @{
    Archive = "LLVM-$Version-Linux-X64.tar.xz"
    Member  = "LLVM-$Version-Linux-X64/bin/lld"
    Bin     = "lld-link"
    PkgDir  = "LLD.Link.Toolsets.linux-x64"
  }
  "linux-arm64" = @{
    Archive = "LLVM-$Version-Linux-ARM64.tar.xz"
    Member  = "LLVM-$Version-Linux-ARM64/bin/lld"
    Bin     = "lld-link"
    PkgDir  = "LLD.Link.Toolsets.linux-arm64"
  }
  "osx-arm64" = @{
    Archive = "LLVM-$Version-macOS-ARM64.tar.xz"
    Member  = "LLVM-$Version-macOS-ARM64/bin/lld"
    Bin     = "lld-link"
    PkgDir  = "LLD.Link.Toolsets.osx-arm64"
  }
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
    # Download to a .part file so an interrupted transfer is never mistaken for a cached archive.
    $part = "$archive.part"
    Remove-Item $part -Force -ErrorAction SilentlyContinue
    Write-Host "[$key] Downloading $($t.Archive)..."
    curl.exe -fsSL --ssl-no-revoke $url -o $part
    if (-not $?) { throw "Download failed: $url" }
    Move-Item $part $archive -Force
  } else {
    Write-Host "[$key] Using cached $archive"
  }

  # Extract only the required member into a scratch directory.
  $extractDir = Join-Path $sourceDir ".extract-$key"
  Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

  $extracted = Join-Path $extractDir $t.Member
  Write-Host "[$key] Extracting $($t.Member)..."

  # Fast path: tar can decompress .tar.xz directly when liblzma is available.
  tar -xf $archive -C $extractDir $t.Member 2>$null

  if (-not (Test-Path $extracted)) {
    # Fallback (e.g. Windows bsdtar without liblzma): decompress the .tar.xz with
    # 7-Zip first, then extract the member from the resulting .tar with tar.
    $sevenZip = (Get-Command 7z, 7za, 7zr -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $sevenZip) {
      throw "[$key] Cannot extract '$($t.Archive)': tar has no xz support and no 7z/7za/7zr was found on PATH. Install 7-Zip."
    }

    $tarDir = Join-Path $sourceDir ".tar-$key"
    Remove-Item -Recurse -Force $tarDir -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $tarDir -Force | Out-Null
    Write-Host "[$key] tar lacks xz support, decompressing with 7-Zip..."
    & $sevenZip x $archive "-o$tarDir" -y | Out-Null
    $tarFile = Get-ChildItem $tarDir -Filter *.tar | Select-Object -First 1
    if (-not $tarFile) { throw "[$key] 7-Zip did not produce a .tar from $($t.Archive)" }
    tar -xf $tarFile.FullName -C $extractDir $t.Member
    Remove-Item -Recurse -Force $tarDir -ErrorAction SilentlyContinue
  }

  if (-not (Test-Path $extracted)) {
    throw "[$key] Member not found after extraction: $extracted"
  }

  $binPath = Join-Path $outDir $t.Bin
  Copy-Item $extracted $binPath -Force
  Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue

  # Repackage as tools/lld-link.zip (the package extracts it at build time).
  $zipPath = Join-Path $outDir "lld-link.zip"
  Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
  Compress-Archive -Path $binPath -DestinationPath $zipPath -Force
  Remove-Item $binPath -Force

  $mb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
  Write-Host "[$key] -> $zipPath ($mb MB)"
}

Write-Host "Done. lld-link $Version extracted for: $($keys -join ', ')"
