# README media

The pictures the README shows are not in the repository. The plugin is a full
clone of this repository, so media travels as assets on the plugin's GitHub
Release (`v0.1.0`), and the README links to them by URL.

Regenerate from a working desktop OpenGL session:

```sh
bash scripts/capture-readme.sh   # window-live.png, popover.png (live KTLX)
bash scripts/capture-demo.sh     # omastorm-demo.mp4 and omastorm-preview.gif (live KJAX; SITE=KXXX for another)
```

Both write into this directory, which is ignored except for this file. They
use isolated daemons and change no desktop or system configuration. FFmpeg is
required; the demo also needs Ruby for its temporary harness. Frames are
grabbed as the scene settles, so the video runs a little faster than real
time and is not a latency measurement.

- `omastorm-demo.mp4`: one live take, about 37 s, 1280×720, H.264, no audio:
  the home view, the loop, a pan and zoom to the coast, the three
  treatments, weak returns, the picker switching station, the keys sheet.
- `omastorm-preview.gif`: the home view and the zoom, cut from the video.
- `window-live.png`, `popover.png`: live KTLX with the actual scan time.

Publish with `gh release upload v0.1.0 --clobber docs/media/*` and keep the
README URLs pointing at that tag. `v0.1.0` predates the repo's immutable
releases setting (2026-09-08), so its assets still accept a re-upload; a
release made after that locks its assets at publish, so media for a new tag
has to be uploaded while the release is still a draft.

Radar: NOAA NEXRAD. Map: © OpenStreetMap contributors
([ODbL](https://opendatacommons.org/licenses/odbl/1-0/)); Natural Earth, public
domain.
