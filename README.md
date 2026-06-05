# mrt2-au3

Fork of the [Magenta RealTime 2](https://github.com/magenta/magenta-realtime) AUv3 plugin, extracted to this repo root with upstream kept as a git submodule.

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

Pre-built macOS arm64 builds are attached to [GitHub Releases](https://github.com/audiohacking/mrt2-au3/releases). Download the zip, extract `MRT2 (AU).app` to `/Applications` or `~/Applications`, then follow [INSTALL.md](INSTALL.md).

Release builds are ad-hoc signed. After download, clear quarantine and re-sign locally:

```bash
xattr -cr "/Applications/MRT2 (AU).app"
codesign --force --sign - "$(find "/Applications/MRT2 (AU).app" -name mlx.metallib)"
codesign --force --sign - "/Applications/MRT2 (AU).app"
open "/Applications/MRT2 (AU).app"
```

To cut a release: create a new GitHub release (tag + publish). The [Release workflow](.github/workflows/release.yml) builds on `macos-14` and uploads `MRT2-AU3-<tag>-macos-arm64.zip`. Use **Actions → Release → Run workflow** to test packaging without publishing.

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
# -> build/MRT2-AU3-macos-arm64.zip
```

Optional debug overlay + disk log:

```bash
cmake . -B build -DMAGENTART_DEBUG_LOG=ON
```

## Updating upstream

```bash
cd magenta-realtime
git fetch origin && git checkout main && git pull
cd ..
git add magenta-realtime && git commit -m "Bump magenta-realtime submodule"
```

## Plugin behavior

See [PLUGIN.md](PLUGIN.md) for state/bank panel semantics and React ↔ native bridge details.
