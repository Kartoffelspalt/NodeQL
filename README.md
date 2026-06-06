# NodeQL

NodeQL is a multilingual, desktop-first visual programming platform inspired by Scratch workflows, implemented with original code and assets.

## Current Iteration Scope

This iteration provides a production-oriented foundation with:
- clean architecture folder boundaries
- runtime scheduler core
- block metadata + serialization core
- workspace docking service core
- stage state core
- JSON project model + repository contract
- extension registration contract
- full `gen_l10n` setup for 11 languages (including Arabic RTL)
- baseline tests for runtime, serialization, localization, and workspace logic

## Architecture

```mermaid
flowchart LR
  UI["UI / Shell"] --> FEAT["features/workbench/presentation"]
  FEAT --> DOMAIN["domain models + service contracts"]
  FEAT --> ENGINE["engine runtime/block/workspace/stage"]
  FEAT --> LOC["localization gen_l10n + locale controller"]
  DOMAIN --> DATA["data persistence + project factory"]
  ENGINE --> EXT["extensions contract"]
```

## Folder Structure

- `lib/core`: app bootstrap and theme
- `lib/localization`: locale state + language metadata
- `lib/domain`: business models and repository interfaces
- `lib/data`: persistence and project defaults
- `lib/engine`: runtime, block, workspace, stage, extensions
- `lib/features`: feature-level presentation and state wiring
- `lib/ui`: shell-level entry widgets
- `test`: unit and widget tests per subsystem

## Internationalization

Implemented with Flutter `gen_l10n` + ARB files:
- German (`de`)
- English (`en`)
- French (`fr`)
- Spanish (`es`)
- Italian (`it`)
- Portuguese (`pt`)
- Turkish (`tr`)
- Arabic (`ar`, RTL)
- Japanese (`ja`)
- Korean (`ko`)
- Chinese (`zh`)

All displayed UI texts and block labels are localized via ARB keys.

## Run

```bash
flutter pub get
flutter gen-l10n
flutter test
flutter run -d macos   # or windows/linux
```

## Next TODO Iterations

- implement block drag/drop graph editor + snapping visuals
- runtime coroutine model with deterministic scheduling slices
- stage renderer with costumes/sounds/input events
- autosave, crash recovery, backup versions
- plugin loader and extension discovery
- desktop menus, shortcuts, dockable/resizable panels
- performance profiling for thousands of blocks
