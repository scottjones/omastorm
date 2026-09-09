#!/usr/bin/env bash
# Live KTLX stills for the user-facing README: the window and the production
# popover card. Isolated daemon and cache; the shared daemon is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d /tmp/omastorm-readme-capture.XXXXXX)
export XDG_RUNTIME_DIR="$scratch/runtime" XDG_CACHE_HOME="$scratch/cache"
export OMASTORM_ROOT="$PWD" OMASTORM_CONFIG="$scratch/config.toml"
export QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic
export QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl
mkdir -p "$XDG_RUNTIME_DIR" docs/media
jq -r '.sites[] | select(.id=="KTLX") | "center_lat = \(.lat)\ncenter_lon = \(.lon)\nlocked_radar = \"KTLX\""' engine/data/sites.json > "$OMASTORM_CONFIG"
cleanup() { target/debug/omastorm-engine stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

OMASTORM_WIDTH=1200 OMASTORM_HEIGHT=800 OMASTORM_STYLE=GLYPHS \
  OMASTORM_CAPTURE_DELAY=15000 OMASTORM_CAPTURE="$PWD/docs/media/window-live.png" \
  bash run.sh > "$scratch/window.log" 2>&1
[[ -s docs/media/window-live.png ]] || { cat "$scratch/window.log"; echo "No window-live.png" >&2; exit 1; }
target/debug/omastorm-engine stop >/dev/null 2>&1 || true

# Popover uses its own scratch daemon so its XDG does not collide.
unset XDG_RUNTIME_DIR XDG_CACHE_HOME OMASTORM_CONFIG
bash scripts/capture-popover.sh
cp review/popover-glyphs.png docs/media/popover.png
echo 'docs/media/window-live.png · popover.png'
