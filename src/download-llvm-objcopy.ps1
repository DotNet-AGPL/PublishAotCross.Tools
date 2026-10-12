# Regenerates the bundled llvm-objcopy binaries in src/build/llvm-objcopy/.
#
# NOTE: the LLVM release assets are ~1-2 GB each, so this is slow. The preferred
# way to (re)generate the binaries is the "Fetch llvm-objcopy" GitHub workflow
# (.github/workflows/fetch-objcopy.yml), which downloads them in CI and uploads
# the extracted binaries as an artifact. Use this script on a machine with a
# fast connection to LLVM's release assets.
#
# Extracting .tar.zst requires a tar that understands zstd (GNU tar plus the
# `zstd` binary on PATH, or bsdtar built with libzstd).

param(
  [string]$Version = "",
  [string]$OutDir = "$PSScriptRoot\build\llvm-objcopy"
)

$ErrorActionPreference = "Stop"

if (-not $Version) {
  $props = Join-Path $PSScriptRoot "..\toolsets\ToolsetsVersion.props"
  $Version = [regex]::Match((Get-Content $props -Raw), '<LLDVersion[^>]*>([^<]+)</LLDVersion>').Groups[1].Value
}
if (-not $Version) { throw "Could not determine the LLVM version (LLDVersion)" }

Write-Host "LLVM version: $Version"
$base = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$Version"

$assets = [ordered]@{
  "linux-x64"   = @{ file = "LLVM-$Version-Linux-X64.tar.zst";                        member = "bin/llvm-objcopy"     }
  "linux-arm64" = @{ file = "LLVM-$Version-Linux-ARM64.tar.zst";                      member = "bin/llvm-objcopy"     }
  "osx-arm64"   = @{ file = "LLVM-$Version-macOS-ARM64.tar.zst";                      member = "bin/llvm-objcopy"     }
  "win-x64"     = @{ file = "clang+llvm-$Version-x86_64-pc-windows-msvc.tar.zst";     member = "bin/llvm-objcopy.exe" }
}

foreach ($rid in $assets.Keys) {
  $a = $assets[$rid]
  $destDir = Join-Path $OutDir $rid
  New-Item -ItemType Directory -Force $destDir | Out-Null

  $archive = Join-Path $env:TEMP $a.file
  if (-not (Test-Path $archive)) {
    Write-Host "Downloading $($a.file) ..."
    curl.exe -fsSL --ssl-no-revoke $base/$($a.file) -o $archive
    if (-not $?) { throw "Download failed: $($a.file)" }
  }

  $extract = Join-Path $env:TEMP "llvm-objcopy-$rid"
  Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $extract | Out-Null
  tar --zstd -xf $archive -C $extract --wildcards "*/$($a.member)"

  $leaf = Split-Path $a.member -Leaf
  $found = Get-ChildItem $extract -Recurse -File -Filter $leaf | Select-Object -First 1
  if (-not $found) { throw "Could not find $($a.member) in $($a.file)" }

  Copy-Item $found.FullName (Join-Path $destDir $leaf) -Force
  Write-Host "  -> $destDir\$leaf ($($found.Length) bytes)"
  Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Done. Review and commit src/build/llvm-objcopy/."
