#!/usr/bin/env bash
# Build a native Linux release asset, SHA256SUMS, and a candidate pin under
# target/dist/. Publish the asset before copying the candidate into engine/.
# Does not modify committed pins, tag, publish, or push.
set -euo pipefail
cd "$(dirname "$0")/.."

die() { printf '%s\n' "$@" >&2; exit 1; }
[[ $# == 0 ]] || die 'Usage: bash scripts/build-engine-release.sh (pins are promoted only after publication)'

if ! command -v rustc >/dev/null && [[ -x .tools/cargo/bin/rustc ]]; then
  export RUSTUP_HOME="$PWD/.tools/rustup" CARGO_HOME="$PWD/.tools/cargo"
  export PATH="$CARGO_HOME/bin:$PATH"
fi
host=$(rustc -vV | awk '/^host:/{print $2}')
case $host in
  x86_64-unknown-linux-gnu) pin_name=release.pin ;;
  aarch64-unknown-linux-gnu) pin_name=release-aarch64.pin ;;
  *) die "Unsupported release host: $host (use native x86_64 or aarch64 Linux GNU)." ;;
esac

# Explicit target keeps a Cargo target override from packaging the wrong CPU.
bash scripts/cargo.sh build --release --locked --offline --target "$host" --target-dir target
src=target/$host/release/omastorm-engine
[[ -x $src ]] || die "cargo did not produce $src"

mkdir -p target/dist
asset=omastorm-engine-$host
dest=target/dist/$asset
cp -- "$src" "$dest"
strip --strip-unneeded -- "$dest"
chmod 755 -- "$dest"

sum=$(sha256sum -- "$dest" | awk '{print $1}')
# Include both assets if native builds have been collected in this directory.
(cd target/dist && sha256sum -- omastorm-engine-*-unknown-linux-gnu > SHA256SUMS)
printf '%s  %s\n' "$sum" "$dest"
version=$(awk -F'"' '/^version = /{print $2; exit}' engine/Cargo.toml)
cat > "target/dist/$pin_name" <<PIN
# Pinned GitHub Release for the engine binary (DESIGN.md, distribution).
# Bump only after the named release exists on wesleygrimes/omastorm.
tag=engine-$version
repo=wesleygrimes/omastorm
asset=$asset
sha256=$sum
PIN
printf 'Candidate pin: target/dist/%s; publish and verify the asset before copying to engine/%s.\n' "$pin_name" "$pin_name"
