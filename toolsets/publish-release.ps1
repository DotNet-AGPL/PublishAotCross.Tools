param(
  # Verify only (default). Nothing is uploaded.
  [switch]$Check,
  # Actually push to the source, in dependency order.
  [switch]$Push,
  # Push even when the exact version already exists on the source.
  [switch]$Force,
  [string]$ApiKey,
  [string]$Source = "https://api.nuget.org/v3/index.json",
  [string]$ArtifactsDir = "$PSScriptRoot\..\artifacts"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Release set for the current Revision. Order matters: every package must be
# pushed after the packages it depends on.
#
#   $Children  per-host content packages (new ones only; published ones are skipped)
#   $Parents   meta packages, depend on the children
#   $Main      PublishAotCross.Tools, depends on the parents + Zig
#
# Packages that are already public at the same version are NOT part of this
# list (e.g. XWin.Store.x64/arm64, LLD.Link.Toolsets.*, MacOSX.SDK for .14).
# ---------------------------------------------------------------------------

[xml]$versions = Get-Content "$PSScriptRoot\ToolsetsVersion.props"
$props = $versions.Project.PropertyGroup | Select-Object -First 1
$revision = $props.Revision.InnerText
$lld = $props.LLDVersion.InnerText
$xwin = $props.XWinVersion.InnerText
$sdk = $props.MacOSXSDKVersion.InnerText
$mainVer = "$($props.PublishAotCrossVersionPrefix.InnerText).$revision"

$release = @(
  @{ Id = "MacOSX.Symbols.Toolsets.win-x64";   Version = "$lld.$revision"; File = "MacOSX.Symbols.Toolsets.win-x64.$lld.$revision.nupkg" }
  @{ Id = "MacOSX.Symbols.Toolsets.win-arm64"; Version = "$lld.$revision"; File = "MacOSX.Symbols.Toolsets.win-arm64.$lld.$revision.nupkg" }
  @{ Id = "MacOSX.Symbols.Toolsets.linux-x64"; Version = "$lld.$revision"; File = "MacOSX.Symbols.Toolsets.linux-x64.$lld.$revision.nupkg" }
  @{ Id = "MacOSX.Symbols.Toolsets.linux-arm64"; Version = "$lld.$revision"; File = "MacOSX.Symbols.Toolsets.linux-arm64.$lld.$revision.nupkg" }
  @{ Id = "MacOSX.Symbols.Toolsets";           Version = "$lld.$revision"; File = "MacOSX.Symbols.Toolsets.$lld.$revision.nupkg" }
  @{ Id = "LLD.Link.Toolsets";                 Version = "$lld.$revision"; File = "LLD.Link.Toolsets.$lld.$revision.nupkg" }
  @{ Id = "XWin.Store";                        Version = "$xwin.$revision"; File = "XWin.Store.$xwin.$revision.nupkg" }
  @{ Id = "PublishAotCross.Tools";             Version = $mainVer;         File = "PublishAotCross.Tools.$mainVer.nupkg" }
)

function Read-Nuspec([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
  $zip = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like '*.nuspec' } | Select-Object -First 1
    if (-not $entry) { throw "no .nuspec in $Path" }
    $sr = New-Object IO.StreamReader($entry.Open())
    try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
  } finally { $zip.Dispose() }

  $id = [regex]::Match($text, '<id>([^<]+)</id>').Groups[1].Value
  $ver = [regex]::Match($text, '<version>([^<]+)</version>').Groups[1].Value
  $deps = @([regex]::Matches($text, '<dependency id="([^"]+)" version="([^"]+)"') |
    ForEach-Object { [pscustomobject]@{ Id = $_.Groups[1].Value; Version = $_.Groups[2].Value } })
  [pscustomobject]@{ Id = $id; Version = $ver; Dependencies = $deps }
}

function Test-OnNuGet([string]$Id, [string]$Version) {
  $lower = $Id.ToLowerInvariant()
  try {
    $j = Invoke-RestMethod -Uri "https://api.nuget.org/v3-flatcontainer/$lower/index.json" -TimeoutSec 30
    return ($j.versions -contains $Version)
  } catch {
    return $false
  }
}

Write-Host "=== PublishAotCross release $revision ==="
Write-Host "main     : $mainVer"
Write-Host "toolsets : LLD $lld.$revision, XWin $xwin.$revision, macOS SDK $sdk.$revision"
Write-Host "artifacts: $(Resolve-Path $ArtifactsDir -ErrorAction SilentlyContinue)"
Write-Host ""

$failures = @()
$planned = @{}

Write-Host "--- 1. package contents ---"
foreach ($p in $release) {
  $path = Join-Path $ArtifactsDir $p.File
  if (-not (Test-Path $path)) {
    Write-Host ("  MISSING  {0}" -f $p.File) -ForegroundColor Red
    $failures += "missing file: $($p.File)"
    continue
  }

  $spec = Read-Nuspec $path
  if ($spec.Id -ne $p.Id) { $failures += "id mismatch in $($p.File): $($spec.Id) != $($p.Id)" }
  if ($spec.Version -ne $p.Version) { $failures += "version mismatch in $($p.File): $($spec.Version) != $($p.Version)" }

  $mb = [math]::Round((Get-Item $path).Length / 1MB, 1)
  $sha = (Get-FileHash $path -Algorithm SHA256).Hash
  Write-Host ("  {0,-46} {1,7} MB  {2}" -f $p.Id, $mb, $sha)
  $planned[$p.Id] = $spec.Version
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "内容校验失败：" -ForegroundColor Red
  $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}

Write-Host ""
Write-Host "--- 2. dependency closure ---"
$closureFailures = @()
foreach ($p in $release) {
  $path = Join-Path $ArtifactsDir $p.File
  $spec = Read-Nuspec $path
  foreach ($d in $spec.Dependencies) {
    $inRelease = $planned.ContainsKey($d.Id) -and $planned[$d.Id] -eq $d.Version
    if ($inRelease) {
      Write-Host ("  ok (in release) {0} {1} <- {2}" -f $d.Id, $d.Version, $p.Id)
      continue
    }
    if (Test-OnNuGet $d.Id $d.Version) {
      Write-Host ("  ok (on nuget)   {0} {1} <- {2}" -f $d.Id, $d.Version, $p.Id)
    } else {
      Write-Host ("  MISSING         {0} {1} <- {2}" -f $d.Id, $d.Version, $p.Id) -ForegroundColor Red
      $closureFailures += "$($p.Id) needs $($d.Id) $($d.Version), which is neither in this release nor on nuget.org"
    }
  }
}
if ($closureFailures.Count -gt 0) {
  Write-Host ""
  Write-Host "依赖闭包校验失败：" -ForegroundColor Red
  $closureFailures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}

Write-Host ""
Write-Host "--- 3. remote state ---"
foreach ($p in $release) {
  $exists = Test-OnNuGet $p.Id $p.Version
  $state = if ($exists) { "already published (will " + $(if ($Force) { "push with -Force" } else { "skip" }) + ")" } else { "new" }
  Write-Host ("  {0,-46} {1}" -f $p.Id, $state)
}

if (-not $Push) {
  Write-Host ""
  Write-Host "CHECK ONLY - nothing was pushed. Re-run with -Push to publish (order is children -> parents -> main)."
  exit 0
}

if (-not $ApiKey) {
  $envFile = "$PSScriptRoot\..\.env"
  if (Test-Path $envFile) {
    $line = Get-Content $envFile | Where-Object { $_ -match '^\s*nugetkey\s*=' } | Select-Object -First 1
    if ($line) { $ApiKey = ($line -replace '^\s*nugetkey\s*=\s*', '').Trim() }
  }
}
if (-not $ApiKey) { throw "No API key. Pass -ApiKey or put nugetkey=<key> into .env" }

Write-Host ""
Write-Host "--- 4. push ---"
foreach ($p in $release) {
  if (-not $Force -and (Test-OnNuGet $p.Id $p.Version)) {
    Write-Host ("  skip (exists): {0} {1}" -f $p.Id, $p.Version)
    continue
  }
  $path = Join-Path $ArtifactsDir $p.File
  Write-Host ("  pushing {0} {1} ..." -f $p.Id, $p.Version)
  & dotnet nuget push $path --api-key $ApiKey --source $Source --skip-duplicate
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  push failed: $($p.Id) $($p.Version)" -ForegroundColor Red
    exit 1
  }
}

Write-Host ""
Write-Host "--- 5. verify on nuget.org ---"
Start-Sleep -Seconds 10
$missing = @()
foreach ($p in $release) {
  $ok = (Test-OnNuGet $p.Id $p.Version)
  Write-Host ("  {0,-46} {1}" -f $p.Id, $(if ($ok) { "ok" } else { "NOT FOUND (indexing may take a minute)" }))
  if (-not $ok) { $missing += $p.Id }
}
if ($missing.Count -gt 0) {
  Write-Host "尚未索引：" -ForegroundColor Yellow; $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
Write-Host ""
Write-Host "Done."
