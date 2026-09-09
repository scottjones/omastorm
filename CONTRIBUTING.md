# Contributing

Report bugs and propose work in [GitHub issues](https://github.com/wesleygrimes/omastorm/issues).
Include reproduction steps, expected behavior, and the logs described in the
[README](README.md#troubleshooting). Track pending work in issues and projects;
discuss new features there before implementation.

## Develop

Read [README.md](README.md) for the app and [DESIGN.md](DESIGN.md) for product
rules. [docs/protocol.md](docs/protocol.md) defines the engine/client contract;
[engine/README.md](engine/README.md) maps the backend.

Use an Omarchy desktop with Quickshell and OpenGL, `qt6-shadertools`, and
`socat`. Install [mise](https://mise.jdx.dev), then from a checkout:

```sh
mise install
mise setup
mise start
```

Setup checks desktop dependencies, downloads verified fixtures, and builds the
engine. Rust comes from mise; use `mise exec -- cargo …` for Cargo commands.
[mise.toml](mise.toml) is the task and toolchain reference (`mise tasks` lists
jobs). For an offline archived scan:

```sh
OMASTORM_ARCHIVE=data/raw/KTLX20130520_201643_V06.gz mise start
```

The daemon is shared and outlives windows. Launch replaces a stale build and
open clients reconnect. Use `mise stop` to end it, never `kill`. Close only
Quickshell instances you launched; a windowless process left after closing is
a leak to investigate.

`mise start` loads this checkout's `ui/` in a window. The bar still uses the
installed plugin under `~/.config/omarchy/plugins/com.omastorm.radar` unless
you point it here:

```sh
mise plugin-link
```

That replaces the install directory with a symlink to this checkout (the
previous clone is kept beside it), restarts the Omarchy shell, and
enables the bar widget.
After that, `mise start`, `mise restart`, and `mise onboard` also restart the
shell so the popover matches this tree (a symlink skips the plugin file
watcher, and `rescanPlugins` keeps the old QML). `mise onboard`'s empty weather
and state files apply only to the window; the popover keeps its usual place
files. `mise plugin-unlink` restores the clone. A tty launch prints the qml path,
live vs archive, whether the bar is linked, and which config/state/place
files apply. `mise restart` stops the daemon first so a check or capture
leftover is not reused. `mise onboard` starts the window with no weather file
and no remembered view, so the location picker shows.

## Verify and submit

Keep each change scoped to one issue. Run `mise check` before every commit;
it uses scratch daemons and leaves the shared daemon alone. Cargo runs
first, then the Rust tests run alongside the UI checks, which proceed in two
lanes. Scratch and logs live under `target/check/`, never `/tmp`; the daemons
and runtime files go on every exit, and the logs stay until the next run.
The checks read `target/debug/`, so leave `CARGO_TARGET_DIR` unset.

For shader, sampling, or camera changes, also run `mise check --gpu` and
`bash scripts/capture-review.sh`, inspect the images in `review/`, and include
captures with the review. The rendering test replays the shader's sampling
rule in Rust; update both when changing that rule. Rebuild changed radar or
tile shaders with `bash scripts/build-shader.sh` and commit their `.qsb` files.
The GPU checks need a desktop OpenGL context; software Qt Quick is unsupported.
If the environment cannot run a required check, report that explicitly.

Open a pull request linking the issue, explaining the resulting behavior and
why it changed, and noting verification. Keep commits small, with a body that
explains why; omit co-author and tool trailers. Update the relevant docs when
behavior changes. Document current behavior, not implementation history.

Maintainers: [release instructions](docs/RELEASING.md).
