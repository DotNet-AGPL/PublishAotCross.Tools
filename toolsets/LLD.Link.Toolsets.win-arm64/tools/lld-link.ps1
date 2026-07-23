param()

$rspFile = $null
foreach ($a in $args) {
  if ($a.StartsWith('@')) {
    $rspFile = $a.Substring(1)
    break
  }
}

if (-not $rspFile) {
  Write-Error "lld-link.ps1: no response file found"
  exit 1
}

$content = [IO.File]::ReadAllText($rspFile).TrimStart([char]0xFEFF)
$rspArgs = @($content -replace '"', '') -split '\s+' | Where-Object { $_.Length -gt 0 }

$zigArgs = @()
$outFile = $null

foreach ($a in $rspArgs) {
  if ($a -match '^/OUT:(.+)') {
    $outFile = $matches[1]
  } elseif ($a -match '^/DEF:(.+)') {
  } elseif ($a -match '^/SOURCELINK:(.+)') {
  } elseif ($a -match '^/NATVIS:(.+)') {
  } elseif ($a -match '^/MERGE:.+') {
  } elseif ($a -match '^/INCREMENTAL:.+') {
  } elseif ($a -match '^/vctoolsdir:.+') {
  } elseif ($a -match '^/winsdkdir:.+') {
  } elseif ($a -match '^/NOLOGO.*') {
  } elseif ($a -match '^/MANIFEST:.+') {
  } elseif ($a -match '^/NOEXP.*') {
  } elseif ($a -match '^/NOIMPLIB.*') {
  } elseif ($a -match '^/IGNORE:\d+') {
  } elseif ($a -match '^/SUBSYSTEM:(.+)') {
    $zigArgs += '-Wl,--subsystem,' + $matches[1].ToLower()
  } elseif ($a -match '^/ENTRY:(\S+)') {
    $zigArgs += '-Wl,--entry,' + $matches[1]
  } elseif ($a -match '^/STACK:(\d+)') {
    $zigArgs += '-Wl,--stack=' + $matches[1]
  } elseif ($a -match '^/DEBUG.*') {
    $zigArgs += '-g'
  } elseif ($a -match '^/OPT:REF') {
    $zigArgs += '-Wl,--gc-sections'
  } elseif ($a -match '^/OPT:ICF') {
  } elseif ($a -match '^/CETCOMPAT.*') {
  } elseif ($a -match '^/NODEFAULTLIB:.+') {
  } elseif ($a -match '^/LIBPATH:(.+)') {
    $zigArgs += '-L'; $zigArgs += $matches[1]
  } elseif ($a -match '^/DLL') {
    $zigArgs += '-shared'
  } elseif ($a -match '^/DEFAULTLIB:(.+)') {
  } elseif ($a -match '^-target=') {
  } elseif ($a -match '^.+\.[Oo][Bb][Jj]$') {
    $zigArgs += $a
  } elseif ($a -match '^.+\.[Ll][Ii][Bb]$') {
    $zigArgs += $a
  } else {
    $zigArgs += $a
  }
}

if ($outFile) {
  $zigArgs += '-o'
  $zigArgs += $outFile
}

$zig = if (Get-Command zig -ErrorAction SilentlyContinue) { 'zig' } else {
  Join-Path $env:ProgramData "Nuget\packages\vezel.zig.toolsets.win-x64\0.16.0.2\tools\zig.exe"
}

& $zig cc --target=x86_64-windows-msvc @zigArgs
exit $LASTEXITCODE