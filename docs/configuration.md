# Configuration

The UI reads and watches `~/.config/omastorm/config.toml` for the home
station, follow flag, treatment, weak-return floor, and key map. Home and
follow settings become engine commands described in [protocol.md](protocol.md);
treatment and the weak-return floor stay in the UI. The
[README](../README.md#configuration) has the short version.

`OMASTORM_CONFIG` names another file for checks and captures; a missing file
is no configuration.

```toml
home_site = "KJAX"   # a station id from hello.sites
follow = true        # the map centre picks the station; omit to leave the shared flag alone
treatment = "GLYPHS" # PIXELS, GLYPHS, or STIPPLE at launch; Glyphs when omitted
weak_floor = 5       # dBZ; measured returns under it draw nothing; false draws them all; 5 when omitted

[keys]               # Qt key sequences, several separated by spaces; "" unbinds
pan_left = "h Left"
zoom_in = "+ ="
```

- `home_site`: when the engine's state first arrives (and again after a
  reconnect, since a restarted daemon starts with no station) the
  window puts the camera on this station's home view and sends
  `select_site`; an id outside the table shows the engine's rejection in the
  status slot. Without it, the home is the station nearest Omarchy's own
  location when `~/.local/state/omarchy/settings/weather.json` (`name`,
  `latitude`, `longitude`, written by the shell's weather panel) has one,
  selected the same way; the header says `HOME · NEAR <name>` or
  `HOME · CONFIG.TOML` while the home station is shown. With neither, the
  window shows whatever the daemon is on, the whole network with no station
  at first, until a pan hands off or a station is chosen. `OMASTORM_LOCATION` names
  another location file; when `OMASTORM_CONFIG` is set the machine's own
  location file is not read unless `OMASTORM_LOCATION` names one, so a check
  or capture with its own config is isolated from the desktop's settings.
- `follow`: sent as the `follow` command at the same moments when it differs
  from the state. An edit to the file applies to the open window at once.
- `treatment`: the treatment at launch and whenever the file changes; the
  keys and the chip change it afterwards without writing the file.
  `OMASTORM_STYLE`, set by the capture scripts, outranks it.
- `weak_floor`: the weak-return floor (DESIGN.md, weak-return floor) at
  launch and whenever the file changes: a number in the product's units, or
  `false` to draw every measured return; 5 when omitted. The `weak` key
  toggles between off and this floor afterwards without writing the file.
  `OMASTORM_WEAK` (`off` or a number), set by the capture scripts, outranks
  it. Anything else is reported like a bad `treatment` and leaves the default.
- `[keys]`: one entry per action, laid over the defaults in `ui/Keys.js`:
  `search` (`/ s`), `nearest` (`n`), `lock` (`Shift+L`), `home` (`Shift+H`), `pan_left`
  `pan_down` `pan_up` `pan_right` (`h j k l` and the arrows), `zoom_in`
  (`+ =`), `zoom_out` (`-`), `reset` (`0`), `previous_frame` (`[`),
  `next_frame` (`]`), `play` (`Space`), `oldest` (`Home`), `newest` (`End`),
  `pixels` `glyphs` `stipple` (`1 2 3`), `weak` (`w`), `help` (`?`), `close`
  (`Escape`).
  A value that is not a quoted string, a sequence Qt cannot parse, an
  unknown action, or a key another action already holds leaves that action
  on its default and is named in the status slot (`[KEYS] ZOOM_IN = "FOO":
  FOO IS NOT A KEY`, with a count of any further mistakes) until the file is
  fixed; a bad `treatment` or `weak_floor` is reported the same way.
