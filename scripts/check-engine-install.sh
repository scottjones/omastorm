#!/usr/bin/env bash
# Installer and pin (DESIGN.md, distribution): hash verify, refuse a
# mismatch, install under a scratch XDG_DATA_HOME, skip a current dest,
# reject an unsupported machine, keep ordinary launch and a checkout
# --ensure off the installer. Uses a scratch pin and the debug engine so
# check.sh does not need a release rebuild. The committed pin is then installed
# for real and its asset must hash to the pin, speak the protocol the UI
# accepts, and report the version its tag names.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf '%s\n' "$@" >&2; exit 1; }
[[ -x target/debug/omastorm-engine ]] || fail 'Need target/debug/omastorm-engine (check.sh builds it).'

# Several copies of the debug engine and a tree of HEAD: under target/, and
# gone on exit, pass or fail.
scratch=$PWD/target/check-engine-install
rm -rf "$scratch"
mkdir -p "$scratch"
trap 'rm -rf "$scratch"' EXIT
export XDG_DATA_HOME="$scratch/data" XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
debug=$PWD/target/debug/omastorm-engine
sum=$(sha256sum -- "$debug" | awk '{print $1}')
pin=$scratch/release.pin
cat > "$pin" <<PIN
tag=engine-test
repo=wesleygrimes/omastorm
asset=omastorm-engine-x86_64-unknown-linux-gnu
sha256=$sum
PIN
export OMASTORM_ENGINE_PIN=$pin
dest=$XDG_DATA_HOME/omastorm/bin/omastorm-engine
install_cmd=(bash scripts/install-engine.sh)

# A substituted file is refused and leaves no dest.
printf 'not-the-engine' > "$scratch/bogus"
if OMASTORM_ENGINE_ASSET="$scratch/bogus" "${install_cmd[@]}" 2>"$scratch/mismatch.err"; then
  fail 'Installer accepted a sha256 mismatch'
fi
rg -q 'sha256 mismatch' "$scratch/mismatch.err" || fail "Mismatch error was unclear: $(cat "$scratch/mismatch.err")"
[[ ! -e $dest ]] || fail 'Mismatch wrote a dest'

# Matching asset installs, is executable, and hashes to the pin.
OMASTORM_ENGINE_ASSET="$debug" "${install_cmd[@]}"
[[ -x $dest ]] || fail 'Installer did not write an executable dest'
[[ $(sha256sum -- "$dest" | awk '{print $1}') == "$sum" ]] || fail 'Installed dest does not match the pin'
path=$(OMASTORM_ENGINE_ASSET="$debug" bash scripts/install-engine.sh --print-path)
[[ $path == "$dest" ]] || fail "--print-path: $path"

# A dest that already matches is left alone; no asset and no download.
unset OMASTORM_ENGINE_ASSET
bash scripts/install-engine.sh

# The curl path (file://, no GitHub) verifies and installs too.
rm -f "$dest"
OMASTORM_ENGINE_URL="file://$debug" bash scripts/install-engine.sh
[[ -x $dest && $(sha256sum -- "$dest" | awk '{print $1}') == "$sum" ]] || fail 'file:// install did not match the pin'

# A stale dest is replaced when a matching asset is supplied.
printf 'stale' > "$dest"
chmod 755 -- "$dest"
OMASTORM_ENGINE_ASSET="$debug" bash scripts/install-engine.sh
[[ $(sha256sum -- "$dest" | awk '{print $1}') == "$sum" ]] || fail 'Stale dest was not replaced'

# aarch64 is named, not fetched.
if OMASTORM_ENGINE_MACHINE=aarch64 bash scripts/install-engine.sh 2>"$scratch/arch.err"; then
  fail 'Installer accepted aarch64'
fi
rg -q 'aarch64 is deferred' "$scratch/arch.err" || fail "Arch error was unclear: $(cat "$scratch/arch.err")"

# Checkout --ensure uses the debug engine and does not write the data home.
rm -rf "$XDG_DATA_HOME"
bash run.sh --ensure
[[ ! -e $dest ]] || fail 'Checkout --ensure wrote the release dest'
timeout 2 socat -t0.2 - "UNIX-CONNECT:$XDG_RUNTIME_DIR/omastorm/engine.sock" < /dev/null | rg -q '"type":"hello"' \
  || fail 'Checkout --ensure did not produce a hello'
target/debug/omastorm-engine stop >/dev/null

# A tree without target/debug installs from the asset and ensures.
clone=$scratch/clone
mkdir -p "$clone"
git archive HEAD | tar -x -C "$clone"
# The launcher and installer come from the working tree so the check covers
# uncommitted changes to them; everything else is HEAD, as a clone would be.
mkdir -p "$clone/scripts" "$clone/engine"
cp -- run.sh "$clone/run.sh"
cp -- scripts/install-engine.sh "$clone/scripts/install-engine.sh"
install -D -m 644 "$pin" "$clone/engine/release.pin"
rm -rf "$clone/target"
export OMASTORM_ENGINE_ASSET=$debug OMASTORM_ENGINE_PIN=$clone/engine/release.pin
(cd "$clone" && bash run.sh --ensure)
[[ -x $dest ]] || fail 'Clone --ensure did not install the engine'
timeout 2 socat -t0.2 - "UNIX-CONNECT:$XDG_RUNTIME_DIR/omastorm/engine.sock" < /dev/null | rg -q '"type":"hello"' \
  || fail 'Clone --ensure did not produce a hello'
"$dest" stop >/dev/null

# The committed pin names what users get. Install from it for real: the
# asset the pin names must exist on GitHub, hash to the pin, speak the
# protocol version the UI accepts, and report the version its tag names.
# The asset is fetched once into target/pinned/<sha256> and reused. When
# GitHub is unreachable the step says so and passes; a checkout is correct
# without the network, and the fetch is retried on the next run.
committed=$(awk -F= '/^sha256=/{print $2}' engine/release.pin)
tag=$(awk -F= '/^tag=/{print $2}' engine/release.pin)
[[ $committed =~ ^[a-f0-9]{64}$ ]] || fail 'Committed pin sha256 is not 64 lowercase hex digits'
[[ $tag =~ ^engine-([0-9]+\.[0-9]+\.[0-9]+)$ ]] || fail "Committed pin tag is not engine-<version>: $tag"
pinned_version=${BASH_REMATCH[1]}
ui_protocol=$(rg -o 'message\.v !== ([0-9]+)' -r '$1' ui/Engine.qml)
[[ -n $ui_protocol ]] || fail 'Could not read the protocol version ui/Engine.qml accepts'
cache=target/pinned/$committed
unset OMASTORM_ENGINE_ASSET
export OMASTORM_ENGINE_PIN=$PWD/engine/release.pin
rm -f "$dest"
if [[ -f $cache ]]; then
  OMASTORM_ENGINE_ASSET=$cache bash scripts/install-engine.sh
elif curl -fsI --max-time 5 https://github.com > /dev/null 2>&1; then
  bash scripts/install-engine.sh
  install -D -m 755 "$dest" "$cache"
else
  echo 'Committed pin: GitHub unreachable, the published asset was not verified this run.' >&2
fi
if [[ -x $dest ]]; then
  [[ $(sha256sum -- "$dest" | awk '{print $1}') == "$committed" ]] || fail 'Pinned asset install did not match the pin'
  "$dest" ensure
  hello=$(timeout 2 socat -t0.2 - "UNIX-CONNECT:$XDG_RUNTIME_DIR/omastorm/engine.sock" < /dev/null | head -n1 || true)
  "$dest" stop >/dev/null
  rg -q '"type":"hello"' <<< "$hello" || fail 'Pinned asset did not produce a hello'
  [[ $(jq -r .v <<< "$hello") == "$ui_protocol" ]] \
    || fail "Pinned asset speaks protocol v$(jq -r .v <<< "$hello"); ui/Engine.qml accepts v$ui_protocol"
  [[ $(jq -r .engine <<< "$hello") == "$pinned_version" ]] \
    || fail "Pinned asset reports engine $(jq -r .engine <<< "$hello"); the pin names $tag"
fi

echo 'Engine install: pin verify, mismatch refuse, dest install, skip current, replace stale, arch, checkout --ensure, clone --ensure, pinned asset PASS'
