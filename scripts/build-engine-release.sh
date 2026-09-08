#!/usr/bin/env bash
# Build the x86_64-unknown-linux-gnu GitHub Release asset and SHA256SUMS
# under target/dist/ as a release candidate. It is not compared to the current
# pin; a candidate is expected to differ from the published binary. Pass
# --write-pin to copy its hash into engine/release.pin
# after a successful build. Does not publish, tag, or push.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { printf '%s\n' "$@" >&2; exit 1; }

write_pin=0
[[ ${1:-} == --write-pin ]] && write_pin=1

if ! command -v rustc >/dev/null && [[ -x .tools/cargo/bin/rustc ]]; then
  export RUSTUP_HOME="$PWD/.tools/rustup" CARGO_HOME="$PWD/.tools/cargo"
  export PATH="$CARGO_HOME/bin:$PATH"
fi
host=$(rustc -vV | awk '/^host:/{print $2}')
[[ $host == x86_64-unknown-linux-gnu ]] || die "This script builds the x86_64-unknown-linux-gnu asset (host is $host)."

bash scripts/cargo.sh build --release --locked --offline
src=target/release/omastorm-engine
[[ -x $src ]] || die "cargo did not produce $src"

mkdir -p target/dist
asset=omastorm-engine-x86_64-unknown-linux-gnu
dest=target/dist/$asset
cp -- "$src" "$dest"
strip --strip-unneeded -- "$dest"
chmod 755 -- "$dest"

sum=$(sha256sum -- "$dest" | awk '{print $1}')
# sha256sum -c format, names as they appear on the Release.
(cd target/dist && sha256sum -- "$asset" > SHA256SUMS)
printf '%s  %s\n' "$sum" "$dest"

version=$(awk -F'"' '/^version = /{print $2; exit}' engine/Cargo.toml)
pin=engine/release.pin
if (( write_pin )); then
  cat > "$pin" <<PIN
# Pinned GitHub Release for the engine binary (DESIGN.md, distribution).
# Bump only after the named release exists on wesleygrimes/omastorm.
tag=engine-$version
repo=wesleygrimes/omastorm
asset=$asset
sha256=$sum
PIN
fi
