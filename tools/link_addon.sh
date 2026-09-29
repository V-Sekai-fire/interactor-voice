#!/usr/bin/env bash
# Link an existing godot_sandbox addon (for example interactor-dress-on's project/addons/godot_sandbox)
# into project/addons, where the harness loads it. The addon's binaries are not carried here.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: tools/link_addon.sh <path to addons/godot_sandbox>}"
mkdir -p "$HERE/project/addons"
ln -sfn "$(cd "$SRC" && pwd)" "$HERE/project/addons/godot_sandbox"
