param(
  [string]$StoreTmp = "$PSScriptRoot\.xwin-store-tmp"
)

$xwin = "$PSScriptRoot\xwin.exe"
$splat = "$StoreTmp\splat"
$x64Dir = "$PSScriptRoot\XWin.Store.x64\.xwin-store-tmp"
$arm64Dir = "$PSScriptRoot\XWin.Store.arm64\.xwin-store-tmp"

# Run xwin splat for both architectures
if (-not (Test-Path "$splat\sdk\lib\ucrt\x64\ucrt.lib")) {
  Write-Host "Running xwin splat (needs admin)..."
  & $xwin --accept-license --cache-dir $StoreTmp --arch x86_64,aarch64 --sdk-version 10.0.22621 splat --disable-symlinks --preserve-ms-arch-notation
  if (-not $?) { Write-Error "xwin splat failed"; exit 1 }
}

function Filter-Store {
  param($Source, $Target, $Arch)

  Write-Host "  Filtering for $Arch..."
  Remove-Item -Recurse -Force $Target -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path "$Target\splat" -Force | Out-Null

  # CRT: copy non-arch files first, then only matching arch libs
  robocopy "$Source\crt" "$Target\splat\crt" /E /XJ /NDL /NJH /NJS /NP /XD arm64 x64 > $null
  robocopy "$Source\crt\lib\$Arch" "$Target\splat\crt\lib\$Arch" /E /XJ /NDL /NJH /NJS /NP > $null

  # SDK lib - only specified arch
  robocopy "$Source\sdk\lib\ucrt\$Arch" "$Target\splat\sdk\lib\ucrt\$Arch" /E /XJ /NDL /NJH /NJS /NP > $null
  robocopy "$Source\sdk\lib\um\$Arch" "$Target\splat\sdk\lib\um\$Arch" /E /XJ /NDL /NJH /NJS /NP > $null

  # Include (common)
  robocopy "$Source\sdk\include" "$Target\splat\sdk\include" /E /XJ /NDL /NJH /NJS /NP > $null
}

Filter-Store -Source $splat -Target $x64Dir -Arch "x64"
Filter-Store -Source $splat -Target $arm64Dir -Arch "arm64"

Write-Host "Done. Both stores ready for packing."

# Show sizes
$szX64 = (Get-ChildItem $x64Dir -Recurse -File | Measure-Object -Property Length -Sum).Sum
$szArm64 = (Get-ChildItem $arm64Dir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host "  X64 store: $([math]::Round($szX64/1MB, 0)) MB"
Write-Host "  ARM64 store: $([math]::Round($szArm64/1MB, 0)) MB"
