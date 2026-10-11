if (-not (Get-Command -Name zig -CommandType Application -ErrorAction SilentlyContinue)) {
  Write-Host "Error: zig is not on the PATH. Install zig and make sure it's on PATH. Follow instructions at https://github.com/fallenwood/PublishAotCross."
  exit 1
}

if ($env:MACOSX_SDK) { [Console]::Error.WriteLine("[publishaotcross clang wrapper] invoked; MACOSX_SDK=$env:MACOSX_SDK") }

$zigArgs = @()

foreach ($arg in $args) {
  $translatedArg = $arg.Replace("'-Wl,-rpath,`$ORIGIN'", '-Wl,-rpath,$ORIGIN')
  $translatedArg = $translatedArg.Replace('--discard-all', '--as-needed')
  $translatedArg = $translatedArg.Replace('-static-pie', '-static')

  if ($translatedArg -eq '-lz' `
      -or $translatedArg -eq '-Wl,-pie' `
      -or $translatedArg -eq '-pie' `
      -or $translatedArg -eq '-Wl,-e0x0' `
      -or $translatedArg -eq '-Wl,--defsym,__xmknod=mknod') {
    # remove the argument
    continue
  }

  $zigArgs += $translatedArg
}

# macOS cross-compilation: zig does not derive framework/library search paths
# from -isysroot, so pass them explicitly.
if ($env:MACOSX_SDK -and (($zigArgs -join ' ') -match 'macos|apple')) {
  $sdk = $env:MACOSX_SDK
  $zigArgs = @(
    '-isysroot', $sdk,
    '-F', "$sdk/System/Library/Frameworks",
    '-F', "$sdk/System/Library/PrivateFrameworks",
    '-L', "$sdk/usr/lib",
    '-L', "$sdk/usr/lib/swift"
  ) + $zigArgs
}

# The -Wl,-u,__Module workaround targets the ELF (zig) linker; on Mach-O it
# makes the linker require an undefined symbol and fails, so skip it for macOS.
if (-not (($zigArgs -join ' ') -match 'macos|apple')) {
  $zigArgs = @('-Wl,-u,__Module') + $zigArgs
}

& zig cc @zigArgs
exit $LASTEXITCODE
