if (!UseExternalZig) {
  Environment.SetEnvironmentVariable("PATH", ZigPath + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));
}

// Expose the macOS SDK root (if any) to the clang/gcc wrappers, which use it to
// cross-compile to osx. The value comes from the MacOSXSDKDir property (which
// defaults to the MACOSX_SDK environment variable).
if (!string.IsNullOrEmpty(MacOSXSDKDir)) {
  Environment.SetEnvironmentVariable("MACOSX_SDK", MacOSXSDKDir);
}

var buildenv = "";
var isHostWindows = false;
var isTargetingWindows = RuntimeIdentifier.StartsWith("win");
var isDebug = PublishAotCrossDebug;

if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) {
  var osDescription = RuntimeInformation.OSDescription;
  buildenv += "linux";
  if (osDescription.Contains("GNU")) {
    // noop
  } else if (osDescription.Contains("MUSL")) {
    buildenv += "-musl";
  } else {
    // TODO: android/loongarch/bionic/osx/ios
  }
} else if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
  buildenv += "win";
  isHostWindows = true;
} else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) {
  buildenv += "osx";
}

if (RuntimeInformation.OSArchitecture == Architecture.X64) {
  buildenv += "-x64";
} else if (RuntimeInformation.OSArchitecture == Architecture.Arm64) {
  buildenv += "-arm64";
} else if (RuntimeInformation.OSArchitecture == Architecture.Arm) {
  buildenv += "-arm";
}

if (isTargetingWindows) {
  if (!isHostWindows && (buildenv != RuntimeIdentifier || AotPreferCustom)) {
    // Cross-compile from *nix to Windows
    Environment.SetEnvironmentVariable("CustomAotToolChain", "xwin");
    CustomAotToolChain = "xwin";

    if (isDebug) {
      Console.Error.WriteLine($"PublishAotCross.Tools: using the xwin toolchain for {RuntimeIdentifier} (host {buildenv}).");
    }

    return Success;
  }

  // Only supported on win-x64 host
  if (buildenv == "win-x64" && AotPreferCustom) {
    // Use xwin toolchain for Windows native compilation instead of VS C++ tools
    Environment.SetEnvironmentVariable("CustomAotToolChain", "xwin");
    CustomAotToolChain = "xwin";

    if (isDebug) {
      Console.Error.WriteLine($"PublishAotCross.Tools: using the xwin toolchain for {RuntimeIdentifier} (host {buildenv}).");
    }

    return Success;
  }
} else {
  // On a macOS host targeting macOS, use the native Apple toolchain (Xcode):
  // Zig cannot link against Apple's libSystem/frameworks without a macOS SDK.
  var nativeMac = buildenv.StartsWith("osx") && buildenv == RuntimeIdentifier;

  if (!nativeMac && (buildenv != RuntimeIdentifier || AotPreferCustom)) {
    Environment.SetEnvironmentVariable("PATH", MSBuildThisFileDirectory + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));

    // Prefer the bundled multi-format llvm-objcopy for the AOT symbol-strip
    // step. The host's binutils objcopy can only handle its own architecture,
    // while llvm-objcopy can strip binaries built for any target.
    var objcopyHost = buildenv;
    var objcopyDir = Path.Combine(MSBuildThisFileDirectory, "llvm-objcopy", objcopyHost);
    if (!Directory.Exists(objcopyDir) && objcopyHost == "win-arm64") {
      // The x64 build runs on Windows arm64 hosts (emulation).
      objcopyDir = Path.Combine(MSBuildThisFileDirectory, "llvm-objcopy", "win-x64");
    }
    if (Directory.Exists(objcopyDir)) {
      Environment.SetEnvironmentVariable("PATH", objcopyDir + Path.PathSeparator + Environment.GetEnvironmentVariable("PATH"));
    }

    if (!isHostWindows) {
      var cmd = new Process();
      cmd.StartInfo.FileName = "chmod";
      cmd.StartInfo.Arguments = "-R +x " + MSBuildThisFileDirectory;
      cmd.StartInfo.CreateNoWindow = true;
      cmd.StartInfo.UseShellExecute = false;
      cmd.Start();
      cmd.WaitForExit();
    }

    if (isDebug) {
      Console.Error.WriteLine($"PublishAotCross.Tools: using the Zig toolchain for {RuntimeIdentifier} (host {buildenv}); added {MSBuildThisFileDirectory} to PATH.");
    }

    Environment.SetEnvironmentVariable("CustomAotToolChain", "zig");
    CustomAotToolChain = "zig";

    return Success;
  }
}

if (isDebug) {
  Console.Error.WriteLine($"PublishAotCross.Tools: native build on {buildenv} for {RuntimeIdentifier}; leaving the system toolchain in place.");
}
