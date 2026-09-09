#!/usr/bin/env bash
# Fixture sources (development only). Downloads the archived Level II volume
# that the engine embeds at build time, the Natural Earth files that
# `engine/build.rs` converts into the embedded geography (DESIGN.md, basemap
# tiles: coastline, lakes, country and state lines at 1:10m and 1:50m, plus
# populated places for map labels), and GeoNames cities5000 for the location
# picker, then verifies data/SHA256SUMS. data/raw is ignored, so a fresh
# checkout runs this once before `cargo build`. Launch never calls it.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/raw
curl -fL --retry 2 'https://unidata-nexrad-level2.s3.amazonaws.com/2013/05/20/KTLX/KTLX20130520_201643_V06.gz' -o data/raw/KTLX20130520_201643_V06.gz
ne='https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson'
curl -fL --retry 2 "$ne/ne_10m_populated_places_simple.geojson" -o data/raw/places.geojson
curl -fL --retry 2 'https://download.geonames.org/export/dump/cities5000.zip' -o data/raw/cities5000.zip
python3 -c "import zipfile; zipfile.ZipFile('data/raw/cities5000.zip').extract('cities5000.txt', 'data/raw')"
rm -f data/raw/cities5000.zip
curl -fL --retry 2 'https://download.geonames.org/export/dump/admin1CodesASCII.txt' -o data/raw/admin1CodesASCII.txt
for scale in 10m 50m; do
  for theme in coastline lakes admin_0_boundary_lines_land admin_1_states_provinces_lines; do
    curl -fL --retry 2 "$ne/ne_${scale}_${theme}.geojson" -o "data/raw/ne_${scale}_${theme}.geojson"
  done
done
sha256sum -c data/SHA256SUMS
