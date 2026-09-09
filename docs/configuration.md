# Configuration

The UI reads and watches `~/.config/omastorm/config.toml` for deliberate
preferences: an explicit map centre, a locked radar, treatment, the
weak-return floor, and the key map. Remembered camera and the UI radar lock
live in `~/.local/state/omastorm/state.json`, not in this file. Location and
radar commands are described in [protocol.md](protocol.md); treatment and
the weak-return floor stay in the UI. The [README](../README.md#configuration)
has the short version.

`OMASTORM_CONFIG` names another file for checks and captures; a missing file
is no configuration. `OMASTORM_STATE` names another state file; when
`OMASTORM_CONFIG` is set the machine's own state and weather files are not
read unless `OMASTORM_STATE` or `OMASTORM_LOCATION` names one.

```toml
center_lat = 30.332  # with center_lon, the map centre on every launch
center_lon = -81.656
locked_radar = "KJAX"  # pin this station; omit to follow the nearest
treatment = "GLYPHS"   # PIXELS, GLYPHS, or STIPPLE at launch; Glyphs when omitted
weak_floor = 5         # dBZ; measured returns under it draw nothing; false draws them all; 5 when omitted

[keys]                 # Qt key sequences, several separated by spaces; "" unbinds
pan_left = "h Left"
zoom_in = "+ ="
```

- `center_lat` / `center_lon`: both must be set, latitude in ±90 and
  longitude in ±180. They are the map centre on every launch and the place
  RESET returns to. They outrank remembered state and Omarchy's weather
  location. Omit both to restore the last camera, else use weather.json, else
  the location picker. Onboarding, pan, zoom, and the location picker write
  state.json, never these keys. One set without the other, or a value out of
  range, is named in the status slot and ignored.
- `locked_radar`: a station id from `hello.sites`. On launch the window
  selects and locks it without moving the camera. Unlocking or locking in
  the session lasts until relaunch. An id outside the table shows the
  engine's rejection in the status slot. The camera may sit outside that
  radar's coverage; the chrome says `LOCKED · OUTSIDE COVERAGE`. Omit it to
  restore a remembered lock from state.json, otherwise follow the nearest
  radar to the map centre.
- `treatment`: the treatment at launch and whenever the file changes; the
  keys and the chip change it afterwards without writing the file.
  `OMASTORM_STYLE`, set by the capture scripts, outranks it.
- `weak_floor`: the weak-return floor at
  launch and whenever the file changes: a number in the product's units, or
  `false` to draw every measured return; 5 when omitted. The `weak` key
  toggles between off and this floor afterwards without writing the file.
  `OMASTORM_WEAK` (`off` or a number), set by the capture scripts, outranks
  it. Anything else is reported like a bad `treatment` and leaves the default.
- `[keys]`: one entry per action, laid over the defaults in `ui/Keys.js`:
  `search` (`/ s`), `nearest` (`n`), `lock` (`Shift+L`), `home` (`Shift+H`,
  the location picker), `pan_left`
  `pan_down` `pan_up` `pan_right` (`h j k l` and the arrows), `zoom_in`
  (`+ =`), `zoom_out` (`-`), `reset` (`0`, the resolved location), `previous_frame` (`[`),
  `next_frame` (`]`), `play` (`Space`), `oldest` (`Home`), `newest` (`End`),
  `pixels` `glyphs` `stipple` (`1 2 3`), `weak` (`w`), `help` (`?`), `close`
  (`Escape`).
  A value that is not a quoted string, a sequence Qt cannot parse, an
  unknown action, or a key another action already holds leaves that action
  on its default and is named in the status slot (`[KEYS] ZOOM_IN = "FOO":
  FOO IS NOT A KEY`, with a count of any further mistakes) until the file is
  fixed; a bad `treatment`, `weak_floor`, centre, or `locked_radar` is
  reported the same way. `home_site` and `follow` are unused and named if
  present.

## Remembered state

`~/.local/state/omastorm/state.json` is written atomically (a temporary file
renamed into place). It holds the last map centre, span in kilometres, and
the UI radar lock when one is set:

```json
{"lat":30.332,"lon":-81.656,"span":210,"lock":"KJAX","name":"Jacksonville"}
```

Invalid fields are dropped. A missing file is no remembered view.
`OMASTORM_LOCATION` names another weather.json (`name`, `latitude`,
`longitude`, written by the shell's weather panel) for checks; coordinates
outside ±90/±180 are ignored.
