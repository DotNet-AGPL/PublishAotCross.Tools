<#
.SYNOPSIS
  Downloads the macOS SDK from Apple's Command Line Tools package and extracts the
  subset that Native AOT needs to cross-link osx-arm64 binaries.

.DESCRIPTION
  The heavy lifting (xar -> pbzx -> cpio) lives in toolsets/MacOSX.SDK.Fetch, which is
  also what a future "download at build time" flow would reuse. This script only pins
  the package URL/hash, keeps a local copy of the .pkg and runs the tool.

  The .pkg comes from Apple's public software-update CDN, so no Apple ID, no Mac and no
  Xcode are involved. Using the SDK is still subject to Apple's Xcode license terms.

.EXAMPLE
  pwsh toolsets/download-macosx-sdk.ps1 -AcceptLicense

.EXAMPLE
  # Offline: reuse a package that was downloaded earlier.
  pwsh toolsets/download-macosx-sdk.ps1 -AcceptLicense -PackagePath D:\pkgs\CLTools_macOSNMOS_SDK.pkg
#>
param(
  [switch]$AcceptLicense,
  [string]$Version = "",
  [string]$PackagePath = "",
  [string]$StoreTmp = "$PSScriptRoot\MacOSX.SDK\.macosx-sdk-tmp",
  [string]$KeepPackage = "$PSScriptRoot\.pkg-cache",
  [string]$Decoder = ""
)

$ErrorActionPreference = "Stop"

if (-not $AcceptLicense) {
  Write-Host "=== Apple Xcode License Notice ==="
  Write-Host "The macOS SDK is subject to Apple's Xcode license terms:"
  Write-Host "  https://www.apple.com/legal/sla/docs/xcode.pdf"
  Write-Host ""
  $confirm = Read-Host "Do you accept the license terms? (y/N)"
  if ($confirm -ne "y" -and $confirm -ne "Y") { Write-Error "License not accepted"; exit 1 }
}

# Version comes from ToolsetsVersion.props so the package and the extracted content
# can never disagree.
$propsPath = Join-Path $PSScriptRoot "ToolsetsVersion.props"
[xml]$props = Get-Content $propsPath
if (-not $Version) {
  $Version = $props.SelectSingleNode("/Project/PropertyGroup/MacOSXSDKVersion").InnerText
}
Write-Host "macOS SDK version: $Version"

# Pinned Command Line Tools 27.2 SDK package (NMOS = the current SDK, LMOS carries the
# previous major). Keep this table in sync with MacOSX.SDK.Fetch's default URL.
$packages = @{
  "27.2" = @{
    Url    = "https://swcdn.apple.com/content/downloads/53/49/142-50405-A_WOBLDDXP4W/wk3d2yw94ir1jieuddcu9b9tffxrb09bq8/CLTools_macOSNMOS_SDK.pkg"
    Sha256 = "1eb5196e069ad6e0abde1d750d967b7ea58f5b97f179dbf07aee2d00ca6c813e"
    File   = "CLTools_macOSNMOS_SDK-27.2.pkg"
  }
}

$entry = $packages[$Version]
if (-not $entry) {
  throw "Unknown macOS SDK version $Version. Add its package URL/SHA256 (see toolsets/MacOSX.SDK.Fetch/Program.cs)."
}

$toolProject = Join-Path $PSScriptRoot "MacOSX.SDK.Fetch\MacOSX.SDK.Fetch.csproj"
$arguments = @(
  "run", "--project", $toolProject, "-c", "Release", "--",
  "--out", $StoreTmp,
  "--version", $Version,
  "--accept-license"
)

if ($PackagePath) {
  Write-Host "Using local package: $PackagePath"
  $arguments += @("--package", $PackagePath, "--sha256", $entry.Sha256)
} else {
  New-Item -ItemType Directory -Force -Path $KeepPackage | Out-Null
  $cached = Join-Path $KeepPackage $entry.File
  Write-Host "Package URL: $($entry.Url)"
  $arguments += @("--package", $entry.Url, "--sha256", $entry.Sha256, "--keep-package", $cached)
}

if ($Decoder) { $arguments += @("--decoder", $Decoder) }

Write-Host "Running MacOSX.SDK.Fetch ..."
& dotnet @arguments
if ($LASTEXITCODE -ne 0) { throw "MacOSX.SDK.Fetch failed with exit code $LASTEXITCODE" }

$size = (Get-ChildItem $StoreTmp -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host ""
Write-Host ("Done. Filtered SDK at {0} ({1:N0} MB)" -f $StoreTmp, ($size / 1MB))
Write-Host "Next: dotnet pack toolsets\MacOSX.SDK\MacOSX.SDK.nuproj -o artifacts --force"
