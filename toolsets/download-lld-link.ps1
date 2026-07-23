param(
  [string]$Version = "22.1.8",
  [switch]$Linux
)

if ($Linux) {
  # Linux x64: download LLVM-<version>-Linux-X64.tar.xz
  $downloadUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$Version/LLVM-$Version-Linux-X64.tar.xz"
  $localFile = "$env:TEMP\LLVM-$Version-Linux-X64.tar.xz"
  $outDir = "$PSScriptRoot\LLD.Link.Toolsets.linux-x64\tools"

  if (-not (Test-Path $localFile)) {
    Write-Host "Downloading LLVM $Version Linux ($downloadUrl)..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $localFile -UseBasicParsing
  }

  if (-not (Test-Path $localFile)) {
    Write-Error "Download failed: $localFile"
    exit 1
  }

  if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  }

  # Extract lld binary (rename to lld-link)
  if (Get-Command 7z -ErrorAction SilentlyContinue) {
    & 7z x $localFile "-o$env:TEMP\llvm-extract" "LLVM-$Version-Linux-X64/bin/lld" -y
    Copy-Item "$env:TEMP\llvm-extract\LLVM-$Version-Linux-X64\bin\lld" "$outDir\lld-link" -Force
    Remove-Item -Recurse -Force "$env:TEMP\llvm-extract" -ErrorAction SilentlyContinue
  } else {
    Write-Error "7-Zip not found. Install 7-Zip or extract manually:"
    exit 1
  }

  if (Test-Path "$outDir\lld-link") {
    Write-Host "lld-link extracted, creating lld-link.zip..."
    $zipPath = "$outDir\lld-link.zip"
    Compress-Archive -Path "$outDir\lld-link" -DestinationPath $zipPath -Force
    Remove-Item "$outDir\lld-link" -Force
    Write-Host "lld-link.zip created at $zipPath"
  } else {
    Write-Error "Extraction failed: lld-link not found in output directory"
    exit 1
  }
} else {
  # Windows x64: download LLVM-<version>-win64.exe
  $downloadUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$Version/LLVM-$Version-win64.exe"
  $localFile = "$env:TEMP\LLVM-$Version-win64.exe"
  $outDir = "$PSScriptRoot\LLD.Link.Toolsets.win-x64\tools"

  if (-not (Test-Path $localFile)) {
    Write-Host "Downloading LLVM $Version ($downloadUrl)..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $localFile -UseBasicParsing
  }

  if (-not (Test-Path $localFile)) {
    Write-Error "Download failed: $localFile"
    exit 1
  }

  if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  }

  # Try 7z first, then other extractors
  if (Get-Command 7z -ErrorAction SilentlyContinue) {
    & 7z e $localFile "bin/lld-link.exe" -o"$outDir" -r -y
  } elseif (Get-Command 7za -ErrorAction SilentlyContinue) {
    & 7za e $localFile "bin/lld-link.exe" -o"$outDir" -r -y
  } else {
    Write-Error "7-Zip not found. Install 7-Zip or extract manually:"
    Write-Error "  7z e `"$localFile`" bin/lld-link.exe -o"`$outDir`" -r -y"
    exit 1
  }

  if (Test-Path "$outDir\lld-link.exe") {
    Write-Host "lld-link.exe extracted, creating lld-link.zip..."
    $zipPath = "$outDir\lld-link.zip"
    Compress-Archive -Path "$outDir\lld-link.exe" -DestinationPath $zipPath -Force
    Remove-Item "$outDir\lld-link.exe" -Force
    Write-Host "lld-link.zip created at $zipPath"
  } else {
    Write-Error "Extraction failed: lld-link.exe not found in output directory"
    exit 1
  }
}
