# Data

## Archived fixture

NOAA/NEXRAD **KTLX**, Oklahoma City, **2013-05-20 20:16:43 UTC**. The lowest
sweep ends at 20:17:00 UTC; its fixed elevation is approximately 0.48°
(displayed as 0.5°). This is an archived reflectivity scan, never live weather,
and the window labels it ARCHIVED.

- [Original Level II scan](https://unidata-nexrad-level2.s3.amazonaws.com/2013/05/20/KTLX/KTLX20130520_201643_V06.gz), 9,548,976 bytes.
- [NEXRAD on AWS](https://registry.opendata.aws/noaa-nexrad/), accessed 2026-09-04.
  The current archive bucket is `unidata-nexrad-level2`.
- Golden files under `golden/ktlx-20130520/` were decoded once with
  [Py-ART 2.2.5](https://arm-doe.github.io/pyart/API/generated/pyart.io.read_nexrad_archive.html),
  sweep 0, nearest-neighbor handling of any mixed-resolution rays. They are the
  decoder's answer key (`docs/protocol.md`, golden files).

## Geography

Natural Earth coastline, lakes, country boundary lines on land, and
state/province lines at 1:10m and 1:50m, plus 1:10m populated places, from
[natural-earth-vector](https://github.com/nvkelso/natural-earth-vector) master.
Made with Natural Earth; [public domain](https://www.naturalearthdata.com/about/terms-of-use/).
`engine/build.rs` embeds them as polylines (the 1:10m set clipped to the NEXRAD
network envelope) and the engine strokes them into `ne` tiles at any zoom
(`docs/protocol.md`, tiles). Roads and place labels at closer zooms come from
OpenMapTiles vector tiles served by OpenFreeMap, © OpenStreetMap contributors
(ODbL), fetched by the engine at run time and attributed in the UI.

## Fetching

The engine embeds the Natural Earth geography at build time; the archived
volume is read at run time by the decoder tests and by a daemon started with
`OMASTORM_ARCHIVE` (the checks and captures). `data/raw/` is ignored, so a
fresh checkout runs `bash scripts/setup-fixture.sh` once: it downloads the
volume and the nine Natural Earth files and verifies `data/SHA256SUMS`. A build
without the geography stops with a message naming the script; a shipped daemon
embeds nothing archived. The geography URLs
reference upstream master; if upstream changes, checksum verification stops
rather than silently changing the fixture. Installing and launching the plugin
needs none of this; only a checkout build does.

## Decoder and rendering contract

The [wire protocol](../docs/protocol.md#texture-files) defines radar codes,
palette lookup, and sampling; the [engine guide](../engine/README.md#verification)
explains verification against the golden files.
