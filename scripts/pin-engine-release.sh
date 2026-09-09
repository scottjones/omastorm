#!/usr/bin/env bash
# Pin already-built CI/local assets only after verifying their public release.
set -euo pipefail
cd "$(dirname "$0")/.."
die() { printf '%s\n' "$@" >&2; exit 1; }
source scripts/engine-pin.sh
candidate=${1:-target/dist/release.pin}
work=$(mktemp -d "${TMPDIR:-/tmp}/omastorm-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
cp -- "$candidate" "$work/release.pin"
read_engine_pin "$work/release.pin"
for arch in x86_64 aarch64; do
  [[ -n ${assets[$arch]:-} ]] || continue
  url=https://github.com/$repo/releases/download/$tag/${assets[$arch]}
  curl -fsSL --retry 2 -o "$work/asset" -- "$url" \
    || die "Publish ${assets[$arch]} on $tag before updating engine/release.pin."
  got=$(sha256sum -- "$work/asset" | awk '{print $1}')
  [[ $got == "${hashes[$arch]}" ]] \
    || die "Published ${assets[$arch]} does not match the candidate checksum; engine/release.pin was not changed."
done
cp -- "$work/release.pin" engine/release.pin
printf 'Verified published assets and updated engine/release.pin\n'
