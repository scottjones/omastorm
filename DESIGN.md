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

## Location, onboarding, and map

Map center and radar source are independent. The center is the place the
user wants to see; the radar supplies one station's exact sweep. Loading a
frame or handing off to another station never moves the camera.

After the plugin ensures the engine is available and starts it, resolve the
map center in this order:

1. Explicit `center_lat` and `center_lon` in `config.toml`.
2. The last center remembered in `state.json`.
3. Valid coordinates from Omarchy's weather location (`weather.json`).
4. A location chosen through Omastorm's location picker.

Only show onboarding when none of the first three sources supplies a valid
center. The popover offers "Choose a location", opening the expanded
window's picker. Offer place search and "Enter coordinates", which reveals
labeled latitude and longitude fields with validation. "Show radar" accepts
the location. No separate setup wizard or settings window is required. Keep
"Choose location…" available after onboarding. Coordinate entry chooses a
view; it does not create a permanent config override or lock a radar.

Reuse Omarchy's location when available without requiring its weather plugin.
Read weather settings only; never write them. Location search is an explicit
user action handled through the engine. Do not use GeoClue or fetch at launch
to discover the user's location.

Resolve the radar separately: an explicit `locked_radar` in config wins,
otherwise restore a remembered radar lock, otherwise choose the station
nearest the map center. A radar lock alone does not supply a map center or
bypass location onboarding. Newly chosen locations start unlocked unless a
configured radar override applies.

Remember center and zoom after movement settles, and remember changes to the
UI radar lock. Unlocked radar selection follows the center using the protocol's
nearest-station hysteresis; do not wait until the center leaves the radar's
rings. Lock pins the source; `n` releases it and selects the nearest station
without moving the camera. Do not persist the automatically selected station.

Closing preserves the view. Reopening restores it, with explicit config
values taking precedence. Expanding the popover preserves its center, zoom,
station, frame, and playback. An engine reconnect restores the necessary
commands without resetting the user's camera. Weather location supplies an
initial view; subsequent weather changes do not overwrite a remembered view.

Explicit coordinates are honored on every launch and do not imply a radar
lock. A configured center far from a locked radar is valid: preserve both,
show the station and lock clearly, and offer "Use nearest radar" and "Go to
selected radar" when that radar's coverage is outside the view. UI navigation
and unlocking can change the active session; explicit config applies again
on launch.

A station with no frame yet is the map without radar. Show no loading animation.
Display one radar station’s sweep at a time.

## Split

The engine fetches, decodes, caches, and rasterizes. The UI is small state
plus GPU textures. Radar values do not enter JSON or QML. Pan and zoom are
uniforms. The engine reads neither `config.toml` nor `state.json`; the UI
resolves preferences and remembered state, then sends commands.

New settings are optional, omit means default, and a bad value is named in
the status slot. Keep deliberate settings in `config.toml` and session restore in `state.json`.
The app never rewrites config because the user pans, zooms, or changes a lock.
See [configuration](docs/configuration.md) for file ownership and precedence.
Do not write Omarchy, Hyprland, or system configuration.

A product is a texture, legend, units, timestamp, and source from the engine.
Level II is what is drawn.

## Scope

Keep the feature set small. Prefer the weather panel, the theme, and the
engine's state over a parallel mechanism in this app. If a visual call is
open, change the running picture and look at it.
