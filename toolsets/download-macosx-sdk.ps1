param(
  [switch]$AcceptLicense,
  [string]$Version = "26.1",
  [string]$StoreTmp = "$PSScriptRoot\MacOSX.SDK\.macosx-sdk-tmp"
)

$ErrorActionPreference = "Stop"

if (-not $AcceptLicense) {
  Write-Host "=== Apple Xcode License Notice ==="
  Write-Host "This script downloads the macOS SDK from joseluisq/macosx-sdks."
  Write-Host "The macOS SDK is subject to Apple's Xcode license terms:"
  Write-Host "  https://www.apple.com/legal/sla/docs/xcode.pdf"
  Write-Host "By downloading and using this SDK, you agree to those terms."
  Write-Host ""
  $confirm = Read-Host "Do you accept the license terms? (y/N)"
  if ($confirm -ne "y" -and $confirm -ne "Y") { Write-Error "License not accepted"; exit 1 }
}

# SHA256 values from https://raw.githubusercontent.com/joseluisq/macosx-sdks/master/macosx_sdks.json
$sha256 = switch ($Version) {
  "26.1" { "beee7212d265a6d2867d0236cc069314b38d5fb3486a6515734e76fa210c784c" }
  "26.0" { "07ccaa2891454713c3a230dd87283f76124193309d9a7617ebee45354c9302d2" }
  "15.5" { "c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd" }
  default { throw "Unknown version $Version. Add its SHA256 from https://raw.githubusercontent.com/joseluisq/macosx-sdks/master/macosx_sdks.json" }
}

$url = "https://github.com/joseluisq/macosx-sdks/releases/download/$Version/MacOSX$Version.sdk.tar.xz"
$archive = Join-Path $env:TEMP "MacOSX$Version.sdk.tar.xz"

if (-not (Test-Path $archive)) {
  Write-Host "Downloading $url ..."
  curl.exe -fsSL --ssl-no-revoke $url -o $archive
  if (-not $?) { throw "Download failed" }
}

$actual = (Get-FileHash -Path $archive -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $sha256) {
  throw "SHA256 mismatch:`n  Expected: $sha256`n  Actual:   $actual"
}
Write-Host "SHA256 verified."

# --- Extract the full SDK to a scratch dir ---
$work = Join-Path $env:TEMP "MacOSX$Version.sdk-extract"
Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null

$sevenZip = (Get-Command 7z, 7za, 7zr -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if ($sevenZip) {
  Write-Host "Extracting with 7-Zip ..."
  & $sevenZip x $archive "-o$work" -y | Out-Null
  $tar = Get-ChildItem $work -Filter *.tar | Select-Object -First 1
  if ($tar) {
    # 7-Zip (x86) cannot open the very large .tar; use bsdtar for the second step.
    tar -xf $tar.FullName -C $work
    Remove-Item $tar.FullName -Force -ErrorAction SilentlyContinue
  }
} else {
  Write-Host "Extracting with tar ..."
  tar -xf $archive -C $work
}

$sdkSrc = Join-Path $work "MacOSX$Version.sdk"
if (-not (Test-Path $sdkSrc)) { throw "SDK not found after extraction: $sdkSrc" }

# --- Filter the subset that NativeAOT needs for osx-arm64 ---
Remove-Item -Recurse -Force $StoreTmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $StoreTmp | Out-Null

function Copy-Tbd([string]$src, [string]$dst) {
  if (-not (Test-Path $src)) { return }
  robocopy $src $dst *.tbd /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
}

Write-Host "Filtering SDK subset ..."
robocopy "$sdkSrc\usr\include" "$StoreTmp\usr\include" /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null

# Framework .tbd stubs used by NativeAOT (extend as linker errors appear).
$frameworks = @("CoreFoundation", "Foundation", "Security", "Network", "GSS", "CryptoKit")
foreach ($fw in $frameworks) {
  $src = "$sdkSrc\System\Library\Frameworks\$fw.framework"
  $dst = "$StoreTmp\System\Library\Frameworks\$fw.framework"
  if (Test-Path $src) { Copy-Tbd $src $dst } else { Write-Warning "framework not found in SDK: $fw" }
}

# All system/CRT/Swift .tbd stubs (libSystem, libobjc, libicucore, libswiftCore, ...).
Copy-Tbd "$sdkSrc\usr\lib" "$StoreTmp\usr\lib"

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue

$sz = (Get-ChildItem $StoreTmp -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host "Done. Filtered SDK at $StoreTmp ($([math]::Round($sz/1MB,0)) MB)"
Write-Host ""
Write-Host "Next: dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force"
