# Omastorm design

How a change, feature, or fix should behave.

[README.md](README.md) is install and use. [docs/protocol.md](docs/protocol.md)
is the wire. [docs/configuration.md](docs/configuration.md) is the config keys.
[CONTRIBUTING.md](CONTRIBUTING.md) is the contribution workflow. Honor these; ask before
violating them.

## Picture

Weather occupies the view. Geography stays quiet: thin lines, sparse labels,
rings, a crosshair. Chrome follows the Omarchy theme; radar color comes only
from `frame.palette`, shared by the legend and the shader.

Pixels, Glyphs, and Stipple all stay. They sample the same cell and palette
and differ only in how the 3 px cell is painted. Glyphs is the default. A
shader or sampling change updates all three and is shown with a capture, not
described.

Show actual scan times. Label archived data. Missing, range-folded, and
below-threshold stay distinct from measured values. Whatever a change hides
is named in the legend. Keep OSM (ODbL) and Natural Earth attribution with
the data and on screen.

## Home and map

Home is a place, not a radar. The place is Omarchy's weather location
(`weather.json`). Do not add a geocoder, GeoClue, or a city/zip field. Do not
fetch at launch to find the user. `home_site` may pin a station; it does not
replace the place. The camera belongs on the place. `Shift+H` saves a station id, not a point.

One station's exact sweep at a time. Follow hands off as the centre moves;
lock pins; the picker locks; `n` releases. A hand-off does not move the
camera. Do not ship a downloaded mosaic; if several sites are ever shown,
composite their exact sweeps.

A station with no frame yet is the map without radar. Show no loading animation.

## Split

The engine fetches, decodes, caches, and rasterizes. The UI is small state
plus GPU textures. Radar values do not enter JSON or QML. Pan and zoom are
uniforms. The engine does not read `config.toml`; the UI sends commands.

New settings are optional, omit means default, and a bad value is named in
the status slot. Do not put session restore (last pan, lock) in config.toml.
Do not write Omarchy, Hyprland, or system configuration.

A product is a texture, legend, units, timestamp, and source from the engine.
Level II is what is drawn. Level III, if it lands, is an overlay.

## Scope

Keep the feature set small. Prefer the weather panel, the theme, and the
engine's state over a parallel mechanism in this app. If a visual call is
open, change the running picture and look at it.
