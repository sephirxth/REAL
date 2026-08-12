#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"

if ! command -v "$godot_bin" >/dev/null 2>&1 && [[ ! -x "$godot_bin" ]]; then
  echo "GODOT_BIN is not executable: $godot_bin" >&2
  exit 2
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
cp -R "$repo_root/tests/fixture/." "$fixture_dir/"
python3 "$repo_root/scripts/install.py" "$fixture_dir"
export XDG_DATA_HOME="$fixture_dir/.xdg/data"
export XDG_CONFIG_HOME="$fixture_dir/.xdg/config"
export XDG_CACHE_HOME="$fixture_dir/.xdg/cache"
export REAL_CHECK_ONLY=1
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
"$godot_bin" --headless --path "$fixture_dir" --editor --quit -- --check-only
"$godot_bin" --headless --path "$fixture_dir" --quit-after 120 -- --check-only
