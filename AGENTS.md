# Working on Omastorm

Read [README.md](README.md), [DESIGN.md](DESIGN.md), and
[CONTRIBUTING.md](CONTRIBUTING.md) before changing the app. Honor the
[engine/client contract](docs/protocol.md); ask before violating these rules.
Use the contribution workflow and its required checks for every commit.

- Track pending work in GitHub issues and projects. Stay within the selected
  task. Do not push unless asked.
- The repository is the installed plugin: everything tracked lands on users'
  disks. Keep generated output, demo media, and working notes out of git;
  compiled `.qsb` shaders are required exceptions. See `.gitignore`.
- Never modify Omarchy or system configuration. Writes belong only in the
  repo, `$XDG_RUNTIME_DIR/omastorm/`, `$XDG_CACHE_HOME/omastorm/`,
  `$XDG_DATA_HOME/omastorm/`, or `~/.config/omastorm/`. Only an explicit run of
  `scripts/install-launcher.sh` may write
  `$XDG_DATA_HOME/applications/omastorm.desktop`.
- Ordinary `run.sh` never downloads. Network access belongs in the engine's
  live mode or explicit setup/install scripts. Plugin `--ensure` may install
  the pinned engine when no checkout debug engine exists. No archived radar
  ships in the binary; use `OMASTORM_ARCHIVE` for development and checks.
- Do not add Python dependencies. Golden files are the decoder's answer key;
  retain their provenance and dates identifying archived scans.
- Follow [docs/RELEASING.md](docs/RELEASING.md) for versions and distribution.
  Never bump the engine pin before its published asset exists and is verified.
- Verify library claims against docs or source. For visual decisions, produce
  and show an offscreen capture.

Omarchy theme files are in
`~/.local/state/omarchy/current/theme/{colors,shell}.toml` (a real directory).
The shell's watching pattern is `/usr/share/omarchy/shell/Commons/Color.qml`.
Read these as references; do not edit them.
