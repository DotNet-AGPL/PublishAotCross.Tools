#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACTS_DIR="$SCRIPT_DIR/artifacts"

pack_store_x64() {
    echo "Packing XWin.Store.x64..."
    dotnet pack "$SCRIPT_DIR/toolsets/XWin.Store.x64" -o "$ARTIFACTS_DIR" --force
}

pack_store_arm64() {
    echo "Packing XWin.Store.arm64..."
    dotnet pack "$SCRIPT_DIR/toolsets/XWin.Store.arm64" -o "$ARTIFACTS_DIR" --force
}

pack_lld() {
    echo "Packing LLD.Link.Toolsets.win-x64..."
    dotnet pack "$SCRIPT_DIR/toolsets/LLD.Link.Toolsets.win-x64" -o "$ARTIFACTS_DIR" --force
}

pack_lld_linux_x64() {
    echo "Packing LLD.Link.Toolsets.linux-x64..."
    dotnet pack "$SCRIPT_DIR/toolsets/LLD.Link.Toolsets.linux-x64" -o "$ARTIFACTS_DIR" --force
}

pack_lld_linux_arm64() {
    echo "Packing LLD.Link.Toolsets.linux-arm64..."
    dotnet pack "$SCRIPT_DIR/toolsets/LLD.Link.Toolsets.linux-arm64" -o "$ARTIFACTS_DIR" --force
}

pack_lld_win_arm64() {
    echo "Packing LLD.Link.Toolsets.win-arm64..."
    dotnet pack "$SCRIPT_DIR/toolsets/LLD.Link.Toolsets.win-arm64" -o "$ARTIFACTS_DIR" --force
}

pack_lld_osx_arm64() {
    echo "Packing LLD.Link.Toolsets.osx-arm64..."
    dotnet pack "$SCRIPT_DIR/toolsets/LLD.Link.Toolsets.osx-arm64" -o "$ARTIFACTS_DIR" --force
}

case "${1:-all}" in
    all)
        pack_store_x64
        pack_store_arm64
        pack_lld
        pack_lld_linux_x64
        pack_lld_linux_arm64
        pack_lld_win_arm64
        pack_lld_osx_arm64
        ;;
    store-x64)
        pack_store_x64
        ;;
    store-arm64)
        pack_store_arm64
        ;;
    lld)
        pack_lld
        ;;
    lld-linux-x64)
        pack_lld_linux_x64
        ;;
    lld-win-arm64)
        pack_lld_win_arm64
        ;;
    lld-osx-arm64)
        pack_lld_osx_arm64
        ;;
    *)
        echo "Usage: $0 [target]"
        echo "Targets:"
        echo "  all (default)    Pack all packages in dependency order"
        echo "  store-x64        Pack XWin.Store.x64"
        echo "  store-arm64      Pack XWin.Store.arm64"
        echo "  lld              Pack LLD.Link.Toolsets.win-x64"
        echo "  lld-linux-x64    Pack LLD.Link.Toolsets.linux-x64"
        echo "  lld-win-arm64    Pack LLD.Link.Toolsets.win-arm64"
        echo "  lld-osx-arm64    Pack LLD.Link.Toolsets.osx-arm64"
        exit 1
        ;;
esac

echo "Done."
