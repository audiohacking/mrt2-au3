# Model loading for Magenta RealTime AUv3 plugins

Portable guide for fork maintainers who ship sandboxed **Magenta RealTime** Audio Unit v3 plugins (instruments or effects built on `magenta-realtime`).

**Reference implementation:** [audiohacking/mrt2-au3](https://github.com/audiohacking/mrt2-au3) — all patterns below are implemented there and can be copied or adapted.

**Design rule:** keep loading policy in **fork-owned** Objective-C++ / React files. Do **not** patch the `magenta-realtime` git submodule; link upstream `MagentaModelManager`, `MagentaModelDownloader`, and `magenta_paths` unchanged.

---

## What this fixes

Without these changes, sandboxed AUv3 plugins commonly show:

| Symptom | Typical cause |
|---------|----------------|
| Onboarding modal every launch | Resources check uses brittle glob / wrong path |
| Folder picker required twice | User picked parent `~/Documents/Magenta` but code lists only that exact folder |
| `localModels` empty while files exist on disk | Model scan does not walk `magenta-rt-v2/models` |
| Works only after re-opening the plugin | Async bootstrap races ahead of first UI state push |
| **Logic Pro crash on first open** | Two threads call `init_assets()` concurrently (SentencePiece SIGSEGV) |

The mrt2-au3 fork addresses all of the above.

---

## Expected on-disk layout

Recommended install tree (matches upstream Magenta docs):

```
~/Documents/Magenta/magenta-rt-v2/
├── models/
│   ├── mrt2_small/
│   │   ├── mrt2_small.mlxfn
│   │   └── mrt2_small_state.safetensors
│   └── mrt2_base/              (optional)
├── resources/
│   ├── musiccoca/              (*.tflite)
│   └── spectrostream/          (*.mlxfn)
└── banks/                      (runtime snapshots)
```

Users may pick **`~/Documents/Magenta`** (parent) in the folder browser. The plugin must resolve that to `magenta-rt-v2/models` and `magenta-rt-v2/resources` automatically.

Override the Magenta root with env var **`MAGENTA_HOME`** (parent of `models/` and `resources/`; see upstream `magenta_paths.cpp`).

---

## Sandbox access model

AU extensions run in App Sandbox. Two mechanisms work together:

| Mechanism | Purpose |
|-----------|---------|
| `com.apple.security.temporary-exception.files.home-relative-path.read-write` → `/Documents/Magenta/` | Read/write the default Magenta tree **without** a security-scoped bookmark |
| `com.apple.security.files.user-selected.read-write` + bookmark | Access user-picked folders outside the entitlement path |

**Critical:** build paths with `NSHomeDirectoryForUser(NSUserName())`, **not** `NSHomeDirectory()`. Entitlement-relative paths must use the real user home, not the sandbox container.

Example entitlements: [Entitlements.plist](https://github.com/audiohacking/mrt2-au3/blob/main/Entitlements.plist).

Verify they are embedded in the `.appex` after build:

```bash
codesign -d --entitlements - "/path/to/YourPlugin.appex"
```

---

## Architecture overview

Model loading splits into three layers. Only the first two are fork-owned.

```
┌─────────────────────────────────────────────────────────────┐
│  React UI (App.tsx)                                         │
│  • Gate ResourceOnboardingModal                             │
│  • ModelSelector / download flow (@magenta-rt/common)       │
└──────────────────────────┬──────────────────────────────────┘
                           │ postMessage / updateState
┌──────────────────────────▼──────────────────────────────────┐
│  View controller + AU subclass (YourPlugin_AudioUnit.mm)    │
│  • MGRT* path helpers                                       │
│  • MRT2BootstrapQueue — serial init_assets + load_model     │
│  • ensureAssetsInitialized (mutex)                          │
│  • connectToAU → autoLoadSavedModelIfNeeded                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  YourModelPaths.{h,mm}  (fork-owned, rename per plugin)     │
│  • Resource + model search path lists                       │
│  • FileManager-based resource validation                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│  magenta-realtime (submodule — do not fork-patch)           │
│  • MagentaModelManager — listLocalModelsInDirectory, etc.   │
│  • MagentaModelDownloader                                   │
│  • magentart::paths — get_models_dir / get_resources_dir    │
│  • MLXEngine::init_assets / load_model                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Fork-owned files to add or adapt

### 1. `YourModelPaths.{h,mm}`

Copy and rename from mrt2-au3:

- [MRT2ModelPaths.h](https://github.com/audiohacking/mrt2-au3/blob/main/MRT2ModelPaths.h)
- [MRT2ModelPaths.mm](https://github.com/audiohacking/mrt2-au3/blob/main/MRT2ModelPaths.mm)

Add the `.mm` to your plugin target in `CMakeLists.txt` (see [CMakeLists.txt](https://github.com/audiohacking/mrt2-au3/blob/main/CMakeLists.txt)).

**Responsibilities:**

| API | Purpose |
|-----|---------|
| `+defaultResourceSearchPaths` | Ordered list of candidate `resources/` directories |
| `+resourcesValidAtPath:` | `NSFileManager` check: `musiccoca/*.tflite` **and** `spectrostream/*.mlxfn` |
| `+sharedResourcesAvailableOnDisk` | `YES` if any candidate path validates |
| `+defaultModelsSearchPaths` | Ordered list of candidate `models/` directories |

**Why not upstream glob?** Older `areSharedResourcesValid`-style checks used glob patterns that fail silently in the sandbox or with slightly different directory layouts. Explicit directory enumeration is reliable.

**Default search order (resources):**

1. `MagentaRT_CustomResourcesPath` (UserDefaults)
2. `~/Documents/Magenta/magenta-rt-v2/resources`
3. `~/Documents/Magenta/resources`
4. `magentart::paths::get_resources_dir()`

**Default search order (models):**

1. Saved folder paths (`MagentaRT_ModelFolderPath`, `DownloadFolderPath`)
2. `~/Documents/Magenta/magenta-rt-v2/models`
3. `~/Documents/Magenta/models`
4. `[MagentaModelManager defaultModelsDirectory]`
5. `magentart::paths::get_models_dir()`

---

### 2. `MGRT*` helpers in the view controller / AU file

Merge the static helpers from [MagentaRT_AudioUnit.mm](https://github.com/audiohacking/mrt2-au3/blob/main/MagentaRT_AudioUnit.mm) (search for `MGRTModelsFolderBookmark` through `MGRTPreferredModelName`). Rename the `MGRT` prefix to match your plugin if desired.

| Helper | Role |
|--------|------|
| `MGRTModelsFolderBookmark` / `MGSRTSaveModelsFolderBookmark` | Read/write dual UserDefaults keys (legacy + canonical) |
| `MGRTModelsSearchCandidates` | Expand a base URL into `models`, `magenta-rt-v2/models`, plus all default paths |
| `MGRTEffectiveModelsDirectoryURL` | First candidate where `listLocalModelsInDirectory` finds `.mlxfn` bundles |
| `MGRTResolveModelsDirectory` | Bookmark resolve + security scope + effective directory |
| `MGRTResolveResourcesPath` | First valid resources dir from search list |
| `MGRTEnsureCustomResourcesPath` | Persist resolved resources path to UserDefaults |
| `MGRTSandboxAwareResourcesPath` | Map user-picked folder → `resources` or `magenta-rt-v2/resources` |
| `MGRTSharedResourcesAvailable` | On-disk validation **or** `au.hasInitializedAssets` |
| `MGRTPreferredModelName` | `LoadedModelName` → `mrt2_small` → first found |

**Bookmark policy:** never delete a saved folder bookmark because a single listing returned zero models. Log, fall through to default search paths, and let the user pick again only from the UI.

---

### 3. Thread-safe asset initialization (required)

`MLXEngine::init_assets()` is **not** re-entrant. Concurrent calls from the main thread and a background queue caused Logic Pro crashes (`EXC_BAD_ACCESS` in SentencePiece during `init_assets`).

**Required pattern in mrt2-au3:**

```objc
// Serial queue — all init_assets + load_model bootstrap work
static dispatch_queue_t MRT2BootstrapQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.yourbrand.yourplugin.bootstrap",
                                      DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}
```

On the AU subclass:

```objc
std::mutex _assetsInitMutex;

- (BOOL)ensureAssetsInitialized {
    std::lock_guard<std::mutex> lock(_assetsInitMutex);
    // resolve resources path → _engine.init_assets(...) once
    // set _modelLoaded; load musiccoca if needed
}
```

**Rules:**

1. **Do not** call `ensureAssetsInitialized` from AU `init`. Defer to bootstrap.
2. Route **all** paths that call `init_assets` or `load_model` through `YourBootstrapQueue()`:
   - `autoLoadSavedModelIfNeeded` → `runAutoLoadBootstrap`
   - `handleSelectModel`, `handleLoadModel`, `handleSelectDownloadFolder`
   - `applyCustomState` async model restore
3. Use `_autoLoadScheduled` to prevent duplicate bootstrap dispatches from `connectToAU`.
4. UI updates (`sendStateUpdate`, bookmark saves) still hop to `dispatch_get_main_queue()`.

See [ensureAssetsInitialized](https://github.com/audiohacking/mrt2-au3/blob/main/MagentaRT_AudioUnit.mm), [runAutoLoadBootstrap](https://github.com/audiohacking/mrt2-au3/blob/main/MagentaRT_AudioUnit.mm), and [MRT2BootstrapQueue](https://github.com/audiohacking/mrt2-au3/blob/main/MagentaRT_AudioUnit.mm).

---

### 4. React UI onboarding gate

If your plugin uses the shared React shell (`ResourceOnboardingModal`, `ModelSelector` from `@magenta-rt/common`), apply the gate from [react_ui/src/App.tsx](https://github.com/audiohacking/mrt2-au3/blob/main/react_ui/src/App.tsx):

```tsx
if (state.resourcesMissing !== undefined) {
  const hasLocalModels = Array.isArray(state.localModels) && state.localModels.length > 0;
  const modelReady = !!state.modelName && state.modelName !== 'No model loaded';
  setResourcesMissing(state.resourcesMissing && !hasLocalModels && !modelReady);
}
```

Native code may send `resourcesMissing: true` on the first tick before async bootstrap finishes. The UI should not block when models are already visible or a model name is set.

---

## Bootstrap sequence (target behavior)

```
AU alloc/init
  └─ log "init_assets deferred" (no engine init here)

WebView loads → React posts uiReady
  └─ connectToAU
       ├─ MGRTEnsureCustomResourcesPath()
       ├─ resourcesMissing = !MGRTSharedResourcesAvailable(au)
       ├─ handleListLocalModels()  → localModels[]
       └─ autoLoadSavedModelIfNeeded()
            └─ dispatch YourBootstrapQueue
                 └─ runAutoLoadBootstrap
                      ├─ ensureAssetsInitialized()   [mutex, once]
                      ├─ try LoadedModelBookmark (AU + UserDefaults)
                      └─ else tryAutoLoadFromModelsDirectory
                           ├─ MGRTResolveModelsDirectory
                           ├─ MGRTPreferredModelName (prefer mrt2_small)
                           └─ loadModelAtPath → modelName, resourcesMissing: false
```

**Success criteria:** with models and resources under `~/Documents/Magenta/magenta-rt-v2/`, the user should **not** need a folder picker on every launch, and Logic should **not** crash when opening the plugin UI.

Manual folder pick (`selectDownloadFolder`) remains for custom locations outside the entitlement path.

---

## NSUserDefaults keys

| Key | Type | Purpose |
|-----|------|---------|
| `DownloadFolderBookmark` | `NSData` | Security-scoped models-folder bookmark (legacy name) |
| `MagentaRT_ModelFolderBookmark` | `NSData` | Same bookmark (canonical) |
| `DownloadFolderPath` | `NSString` | Display path for UI |
| `MagentaRT_ModelFolderPath` | `NSString` | Display path (canonical) |
| `MagentaRT_CustomResourcesPath` | `NSString` | Resolved `resources/` dir passed to `init_assets` |
| `LoadedModelBookmark` | `NSData` | Security-scoped bookmark to selected model folder or `.mlxfn` parent |
| `LoadedModelName` | `NSString` | Last loaded model folder name (e.g. `mrt2_small`) |

**Bookmark APIs:**

- Create: `NSURLBookmarkCreationWithSecurityScope`
- Resolve: `NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI`
- Always pair `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`

---

## Native state pushed to React

| Key | When set |
|-----|----------|
| `localModels` | `handleListLocalModels` after `MGRTResolveModelsDirectory` |
| `resourcesMissing` | `connectToAU`; cleared when models found or `loadModelAtPath` succeeds |
| `modelName` | After successful `load_model` |
| `downloadPath` | Saved folder display path |

`loadModelAtPath` should send `resourcesMissing: false` on success. `handleListLocalModels` should send `resourcesMissing: false` when `modelFiles.count > 0` and `MGRTSharedResourcesAvailable` is true.

---

## Porting checklist

Use this when adding the fix to a new Magenta AU fork (JAM3, mrt2, etc.):

### Fork code

- [ ] Copy/rename `MRT2ModelPaths.{h,mm}` → `YourModelPaths.{h,mm}`
- [ ] Add `.mm` to plugin CMake target
- [ ] Merge `MGRT*` helpers into your `*_AudioUnit.mm`
- [ ] Implement `YourBootstrapQueue`, `_assetsInitMutex`, `ensureAssetsInitialized`
- [ ] Remove `ensureAssetsInitialized` from AU `init`
- [ ] Route all `loadModelAtPath` / `init_assets` callers through bootstrap queue
- [ ] Add `_autoLoadScheduled` guard in view controller
- [ ] Expose `hasInitializedAssets` on AU subclass for `MGRTSharedResourcesAvailable`
- [ ] Apply React onboarding gate in `App.tsx` (if using shared UI)

### Sandbox

- [ ] `Entitlements.plist` includes `/Documents/Magenta/` home-relative exception (if using default path)
- [ ] `user-selected.read-write` for custom folders
- [ ] Re-sign `.appex` after entitlement changes

### Submodule

- [ ] Keep `magenta-realtime` on upstream `main`; update with `git submodule update --remote`
- [ ] Do **not** vendor copies of `MagentaModelManager` into the fork

### Verify

```bash
cmake --build build --target deploy_your_au -j$(sysctl -n hw.ncpu)
auvaltool -v aumu <SUBT> <MANU>
```

---

## Test matrix

| Scenario | Expected |
|----------|----------|
| Fresh install, assets in `~/Documents/Magenta/magenta-rt-v2/` | No onboarding; `mrt2_small` auto-loads |
| User picked `~/Documents/Magenta` once | Bookmark saved; subpaths resolved; no re-prompt |
| Models on external drive | Folder picker once; bookmark persists |
| No models, no resources | Onboarding shown; download flow works |
| Open plugin UI in Logic (first time) | No crash; model loads within ~1–2 s |
| Second plugin window in same session | Same behavior as first |
| Toggle “No Drums” before auto-load finishes | Drumless state preserved after load |

---

## Debugging

### Build with disk logging

```bash
cmake . -B build -DMAGENTART_DEBUG_LOG=ON
cmake --build build --target deploy_mrt2_au -j$(sysctl -n hw.ncpu)
```

Disk log (when models bookmark exists): `~/Documents/Magenta/magenta-rt-v2/models/mrt_debug.log`

Console filters: `MagentaRT_AU`, `MagentaModelManager`, `using models directory`, `using resources at`

### On-disk sanity checks

```bash
ls ~/Documents/Magenta/magenta-rt-v2/models/*/
ls ~/Documents/Magenta/magenta-rt-v2/resources/musiccoca/*.tflite
ls ~/Documents/Magenta/magenta-rt-v2/resources/spectrostream/*.mlxfn
```

### Crashes

Extension crashes: `~/Library/Logs/DiagnosticReports/<your_au>-*.ips`

If the faulting thread shows concurrent `init_assets` / `ensureAssetsInitialized` on different queues, the bootstrap queue + mutex pattern above is missing or incomplete.

---

## Upstream files (link only — do not patch)

| Path in `magenta-realtime` | Role |
|----------------------------|------|
| `examples/common/objc/MagentaModelManager.{h,mm}` | Model listing, folder picker, default paths |
| `examples/common/objc/MagentaModelDownloader.{h,mm}` | Remote model download |
| `examples/common/cpp/magenta_paths.{h,cpp}` | `MAGENTA_HOME`, default dirs |

---

## Related docs

- [INSTALL.md](INSTALL.md) — DAW setup, 48 kHz requirement, `pluginkit` registration
- [README.md](README.md) — build and deploy
- Upstream: [magenta-realtime installation](https://github.com/magenta/magenta-realtime/blob/main/docs/installation.md)
