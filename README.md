# mrt2-au3

Fork of the [Magenta RealTime 2](https://github.com/magenta/magenta-realtime) AUv3 plugin, extracted to this repo root with upstream kept as a git submodule.

<img width="900"  alt="Screenshot" src="https://github.com/user-attachments/assets/02ec66c3-545c-4c82-9a84-fb90d8806b51" />


## Layout

```
mrt2-au3/
├── magenta-realtime/     # upstream submodule (core + shared examples/common)
├── MagentaRT_AudioUnit.* # AUv3 plugin sources (fork-owned)
├── MagentaRT_AUHostApp.mm
├── react_ui/             # React UI (fork-owned)
├── assets/
└── CMakeLists.txt
```

Shared model-loading code lives in `magenta-realtime/examples/common/`. Inference engine: `magenta-realtime/core/` (`magentart::core`).

Models and resources: `~/Documents/Magenta/magenta-rt-v2/` (see upstream [installation docs](https://github.com/magenta/magenta-realtime/blob/main/docs/installation.md)).

## Prerequisites

- macOS 14+ on Apple Silicon
- Full **Xcode** (Metal compiler required; Command Line Tools alone are not enough)
- Node.js (`brew install node`)
- Python 3.12 + [uv](https://docs.astral.sh/uv/) (for pinned CMake during dev)

```bash
git clone --recurse-submodules https://github.com/audiohacking/mrt2-au3.git
cd mrt2-au3
```

## Releases (no local Xcode required)

Pre-built macOS arm64 builds are attached to [GitHub Releases](https://github.com/audiohacking/mrt2-au3/releases):

| Asset | Use |
|---|---|
| `MRT2-AU3-<version>-macOS-Installer.pkg` | Double-click (or `sudo installer -pkg … -target /`) — installs to `/Applications` and registers the AU |
| `MRT2-AU3-<version>-macOS.dmg` | Drag `MRT2 (AU).app` to Applications |

Models are not included — download separately to `~/Documents/Magenta/magenta-rt-v2/` (see upstream [installation docs](https://github.com/magenta/magenta-realtime/blob/main/docs/installation.md)).

Release builds are ad-hoc signed. After download, clear quarantine and re-sign locally if Gatekeeper blocks launch:

```bash
xattr -cr "/Applications/MRT2 (AU).app"
codesign --force --sign - "$(find "/Applications/MRT2 (AU).app" -name mlx.metallib)"
codesign --force --sign - "/Applications/MRT2 (AU).app"
open "/Applications/MRT2 (AU).app"
```

To cut a release: create a new GitHub release (tag + publish). The [Release workflow](.github/workflows/release.yml) builds on `macos-14` and uploads the `.pkg` and `.dmg`. Use **Actions → Release → Run workflow** to test without publishing.

Build installers locally after `package_mrt2_au`:

```bash
./scripts/build-installer-pkg.sh --version 0.1.0 --sign-app
```

## UI development (no backend compile)

The React UI is a standalone Vite app. You can iterate on layout and colors in the browser without building the AU or MLX backend.

```bash
# From repo root (installs workspace deps on first run)
npm install

cd react_ui
npm run dev
```

Open **http://localhost:62420** in a browser. Edits hot-reload instantly.

To preview inside the plugin UI with the same HMR server:

1. Leave `npm run dev` running in `react_ui/`
2. Open the plugin in Logic (or `open ~/Applications/MRT2\ \(AU\).app`) — the AU detects port `62420` and loads the dev server instead of the bundled `index.html`

Fork accent colors live in `react_ui/src/forkTheme.ts` and `react_ui/src/index.css` (`--fork-accent`). Production builds still use `npm run build` inside `react_ui/` (or the full CMake `deploy_mrt2_au` target, which runs the UI build for you).

## Build locally

Requires full Xcode (Metal compiler). Command Line Tools alone are not enough.

```bash
uv venv --python 3.12 && source .venv/bin/activate
uv pip install "cmake<3.28"

cmake . -B build
cmake --build build --target deploy_mrt2_au -j10
```

Deploys to `~/Applications/MRT2 (AU).app`. Open once to register the AU extension. See [INSTALL.md](INSTALL.md) for DAW setup (48 kHz required).

Package only (for CI or manual distribution):

```bash
cmake --build build --target package_mrt2_au -j10
./scripts/build-installer-pkg.sh --version 0.1.0 --sign-app
# -> release-artifacts/MRT2-AU3-0.1.0-macOS-Installer.pkg
# -> release-artifacts/MRT2-AU3-0.1.0-macOS.dmg
```

Optional debug overlay + disk log:

```bash
cmake . -B build -DMAGENTART_DEBUG_LOG=ON
cmake --build build --target deploy_mrt2_au -j10
```

When enabled, logs appear in the plugin UI and in `mrt_debug.log` under your models folder.

## Updating upstream

```bash
cd magenta-realtime
git fetch origin && git checkout main && git pull
cd ..
git add magenta-realtime && git commit -m "Bump magenta-realtime submodule"
```

## Plugin behavior

See [PLUGIN.md](PLUGIN.md) for state/bank panel semantics and React ↔ native bridge details.
