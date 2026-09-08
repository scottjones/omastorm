#!/usr/bin/env bash
# Installer and pin (DESIGN.md, distribution): hash verify, refuse a
# mismatch, install under a scratch XDG_DATA_HOME, skip a current dest,
# reject an unsupported machine, keep ordinary launch and a checkout
# --ensure off the installer. Uses a scratch pin and the debug engine so
# check.sh does not need a release rebuild. A native candidate in target/dist
# is also installed and bootstrapped when present.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf '%s\n' "$@" >&2; exit 1; }
[[ -x target/debug/omastorm-engine ]] || fail 'Need target/debug/omastorm-engine (check.sh builds it).'

scratch=$(mktemp -d /tmp/omastorm-engine-install.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
export XDG_DATA_HOME="$scratch/data" XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
debug=$PWD/target/debug/omastorm-engine
sum=$(sha256sum -- "$debug" | awk '{print $1}')
pin=$scratch/release.pin
cat > "$pin" <<PIN
tag=engine-test
repo=wesleygrimes/omastorm
asset=omastorm-engine-$(uname -m)-unknown-linux-gnu
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

# Both architectures select their own default pin and reject the other asset.
# Synthetic payloads test selection/hashing; native bootstrap is tested below.
selector=$scratch/selector
mkdir -p "$selector/scripts" "$selector/engine"
cp scripts/install-engine.sh "$selector/scripts/"
for machine in x86_64 aarch64; do
  pin_name=release.pin
  [[ $machine == aarch64 ]] && pin_name=release-aarch64.pin
  printf 'payload for %s\n' "$machine" > "$scratch/$machine"
  arch_sum=$(sha256sum "$scratch/$machine" | awk '{print $1}')
  cat > "$selector/engine/$pin_name" <<PIN
tag=engine-test
repo=wesleygrimes/omastorm
asset=omastorm-engine-$machine-unknown-linux-gnu
sha256=$arch_sum
PIN
  env -u OMASTORM_ENGINE_PIN OMASTORM_ENGINE_MACHINE=$machine \
    OMASTORM_ENGINE_ASSET="$scratch/$machine" bash "$selector/scripts/install-engine.sh"
  [[ $(sha256sum "$dest" | awk '{print $1}') == "$arch_sum" ]] || fail "Wrong $machine pin selected"
  other=x86_64
  [[ $machine == x86_64 ]] && other=aarch64
  if OMASTORM_ENGINE_MACHINE=$other OMASTORM_ENGINE_PIN="$selector/engine/$pin_name" \
    bash scripts/install-engine.sh 2>"$scratch/arch.err"; then
    fail 'Installer accepted a pin for the wrong architecture'
  fi
  rg -q 'does not match architecture' "$scratch/arch.err" || fail 'Wrong-arch error unclear'
done
rm "$selector/engine/release-aarch64.pin"
if env -u OMASTORM_ENGINE_PIN OMASTORM_ENGINE_MACHINE=aarch64 \
  bash "$selector/scripts/install-engine.sh" 2>"$scratch/arch.err"; then
  fail 'Installer accepted missing ARM pin'
fi
rg -q 'No published aarch64 engine pin' "$scratch/arch.err" || fail 'Missing ARM pin error unclear'
if OMASTORM_ENGINE_MACHINE=riscv64 bash scripts/install-engine.sh 2>"$scratch/arch.err"; then
  fail 'Installer accepted unsupported architecture'
fi
rg -q 'Unsupported engine architecture' "$scratch/arch.err" || fail 'Unsupported arch error unclear'

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
# Working tree: this check runs before the packaging commit is on HEAD.
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

# Every committed pin is well formed and agrees with its architecture.
for machine in x86_64 aarch64; do
  pin_name=release.pin
  [[ $machine == aarch64 ]] && pin_name=release-aarch64.pin
  committed_pin=$PWD/engine/$pin_name
  [[ -f $committed_pin ]] || continue
  committed=$(awk -F= '/^sha256=/{print $2}' "$committed_pin")
  [[ $committed =~ ^[a-f0-9]{64}$ ]] || fail "Invalid checksum in $committed_pin"
  [[ $(awk -F= '/^asset=/{print $2}' "$committed_pin") == "omastorm-engine-$machine-unknown-linux-gnu" ]] \
    || fail "Wrong architecture in $committed_pin"
done

# Exercise the actual native release candidate when available, including hello.
case $(uname -m) in
  x86_64) candidate=target/dist/release.pin ;;
  aarch64) candidate=target/dist/release-aarch64.pin ;;
esac
if [[ -f $candidate ]]; then
  export OMASTORM_ENGINE_PIN=$PWD/$candidate
  export OMASTORM_ENGINE_ASSET=$PWD/target/dist/omastorm-engine-$(uname -m)-unknown-linux-gnu
  rm -f "$dest"
  bash scripts/install-engine.sh
  "$dest" ensure >/dev/null
  timeout 2 socat -t0.2 - "UNIX-CONNECT:$XDG_RUNTIME_DIR/omastorm/engine.sock" < /dev/null | rg -q '"type":"hello"' \
    || fail 'Release candidate did not produce a hello'
  "$dest" stop >/dev/null
fi

echo 'Engine install: pin verify, mismatch refuse, dest install, skip current, replace stale, both architectures, checkout --ensure, clone --ensure PASS'
