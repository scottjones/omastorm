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

## Location and map

The camera is a place, not a radar. Resolve the map centre in this order:
explicit `center_lat`/`center_lon` in config.toml, the remembered centre in
state.json, valid coordinates from Omarchy's weather location
(`weather.json`), then the location picker. Explicit coordinates apply on
every launch. Do not fetch at launch to find the user. Do not add GeoClue.

When no location is known, the popover offers “Choose a location,” which
opens a picker in the expanded window. The picker searches GeoNames cities
with population ≥ 5000 in the network envelope (an engine `search_places`
reply, with state/region and country so two Jacksonvilles are distinct)
and accepts numeric latitude/longitude. Map labels stay Natural Earth.
Choosing a location writes state.json, never
config.toml. `Shift+H` and the LOCATION control keep that picker reachable
after onboarding. `0` / RESET returns the camera to the configured centre,
else Omarchy's weather location, else the current centre at the default
span.

Radar selection is independent of the camera: configured `locked_radar`,
else the remembered UI lock, else the nearest radar with automatic
following. `n` releases the lock and selects the nearest radar; the site
picker locks. Neither moves the camera. A configured lock applies on
launch; unlocking or locking in the session lasts until relaunch. Loading
frames and automatic radar hand-offs never move the camera. The view is
restored across close/reopen and kept across expansion and engine
reconnects. A centre outside the locked radar's coverage is allowed; the
chrome says so.

One station's exact sweep at a time.

A station with no frame yet is the map without radar. Show no loading animation.

## Split

The engine fetches, decodes, caches, and rasterizes. The UI is small state
plus GPU textures. Radar values do not enter JSON or QML. Pan and zoom are
uniforms. The engine does not read `config.toml`; the UI sends commands.

New settings are optional, omit means default, and a bad value is named in
the status slot. config.toml holds deliberate preferences. state.json holds
the remembered map centre, zoom, and UI radar lock; write it atomically.
Do not put session restore in config.toml. Do not write Omarchy, Hyprland,
or system configuration.

A product is a texture, legend, units, timestamp, and source from the engine.
Level II is what is drawn.

## Scope

Keep the feature set small. Prefer the weather panel, the theme, and the
engine's state over a parallel mechanism in this app. If a visual call is
open, change the running picture and look at it.
