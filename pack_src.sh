#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/pack_toolsets.sh" all

dotnet pack "$SCRIPT_DIR/src/PublishAotCross.Tools.nuproj" -o "$SCRIPT_DIR/artifacts" --force
echo "Package created in artifacts folder."
