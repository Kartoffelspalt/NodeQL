# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Development Commands

- **Install dependencies**: `flutter pub get`
- **Generate localization**: `flutter gen-l10n` (required after adding/modifying ARB files)
- **Run tests**: `flutter test`
- **Run a single test**: `flutter test test/<filename>_test.dart` or `flutter test --name="test description"`
- **Run the app**: `flutter run -d macos` (or `-d windows`, `-d linux`, `-d chrome`, etc.)
- **Analyze code**: `flutter analyze`
- **Format code**: `flutter format lib/ test/`

## Project Structure & Architecture

The project follows a clean architecture with distinct layers:

### Core Layers
- `lib/core`: App bootstrap (`scratchql_app.dart`) and theme (`theme_controller.dart`, `app_theme.dart`)
- `lib/localization`: Locale state (`locale_controller.dart`) and language metadata (`supported_languages.dart`)
- `lib/domain`: Business models (`block_models.dart`, `project_models.dart`) and repository interfaces (`project_repository.dart`)
- `lib/data`: Persistence implementation (`json_project_repository.dart`) and project factory (`default_project_factory.dart`)
- `lib/engine`: Runtime systems:
  - Runtime scheduler (`runtime_scheduler.dart`, `runtime_models.dart`)
  - Block system (`block_node.dart`, `block_registry.dart`, `block_ast.dart`, `default_block_catalog.dart`)
  - Workspace (`workspace_docking_service.dart`, `workspace_models.dart`)
  - Stage (`stage_state.dart`)
  - Extensions contract (`extension_contract.dart`)
  - Broadcast bus (`runtime_broadcast_bus.dart`)
- `lib/features`: Feature-level presentation and state wiring (workbench):
  - Presentation: `workbench_page.dart`, `workbench_state.dart`, `stage_controller.dart`
  - Engine integration: `engine/` subdirectory with SQL mode, runtime coordinator, workspace engine, stage engine, etc.
  - Compilation: `script_compiler.dart`, `sql_compiler.dart`
  - Styling: `scratch_style.dart`
- `lib/ui`: Shell-level entry widgets (`workbench_shell.dart`)
- `lib/main.dart`: Application entry point

### Key Architectural Notes
- **State Management**: Uses Flutter Riverpod (`flutter_riverpod`) for dependency injection and state management.
- **Localization**: Full `gen_l10n` setup with ARB files for 11 languages (including Arabic RTL). All UI texts and block labels are localized via ARB keys.
- **Routing**: Uses `go_router` for navigation.
- **Block System**: Block definitions are serialized/deserialized via JSON; block metadata and serialization core exists in `lib/engine/block/`.
- **Project Model**: JSON-based project model with repository contract in `lib/data/` and `lib/domain/`.
- **Extensions**: Extension registration contract defined in `lib/engine/extensions/extension_contract.dart`.

## Internationalization

- ARB files are located in `lib/l10n/` (source) and generated under `lib/localization/generated/`.
- Supported languages: de, en, fr, es, it, pt, tr, ar (RTL), ja, ko, zh.
- To add a new language: add ARB file in `lib/l10n/`, run `flutter gen-l10n`, and update `supported_languages.dart` if needed.

## Testing

- Unit and widget tests are located in the `test/` directory, mirroring the subsystem structure.
- Baseline tests exist for runtime, serialization, localization, and workspace logic.
- Run specific test suites: `flutter test test/<subsystem>/`

## Common Tasks

- **Adding a new block**: 
  1. Define block metadata in `lib/engine/block/default_block_catalog.dart` or create a new block file.
  2. Add localization keys in ARB files (`app_localizations_en.arb`, etc.) and run `flutter gen-l10n`.
  3. Ensure block implements required interfaces from `lib/engine/block/block_node.dart`.
- **Modifying UI/localized text**: Edit the relevant ARB file and run `flutter gen-l10n`.
- **Updating dependencies**: Modify `pubspec.yaml` then run `flutter pub get`.
- **Platform-specific adjustments**: Platform folders (`android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/`) contain native project configurations.
