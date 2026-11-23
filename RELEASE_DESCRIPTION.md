# NodeQL v0.5.4 — Workspace Navigation, JOIN Labels & Workshop Improvements

This PR updates NodeQL from v0.5.2 to v0.5.4 (`0.5.4+525`), bringing
the improvements developed for v0.5.3 and v0.5.4 into the release branch.
It fixes unintended zooming during trackpad navigation, improves JOIN
labels, and makes workshop editing and validation more reliable.

## Workspace and JOIN nodes

- Two-finger trackpad swipes move the workspace without changing the zoom
  level. Pinch gestures and mouse-wheel zoom remain available.
- Trackpad movement is handled once, avoiding duplicate pan and zoom
  updates.
- JOIN nodes and palette previews use localized, beginner-friendly labels
  in Simple Mode, including “Tabellen verbinden” in German. Advanced Mode
  retains the SQL label `JOIN`.
- Longer JOIN titles and outcome labels wrap within the node.
- The column-connection manager opens beside its selected connection,
  follows workspace navigation, and stays within the available canvas.

## Workshops

- Workshop authoring previews start at the first step without overwriting saved
  learner progress. Returning to editing restores the authoring workspace.
- Workshop files report more precise validation errors, including the
  affected step and field when available.
- Shared Workshop Studio components used by the separate Workshop Admin
  now support searching, filtering, sorting, and copying official templates
  into independent local drafts.
- Incomplete drafts can be saved, and leaving unsaved edits requires
  confirmation.
- Workshop review identifies missing references, incompatible or
  conflicting completion checks, and content that cannot be shared.
- Imports are previewed before saving and receive new workshop IDs.
  Batch imports preserve existing drafts and templates.
- Catalog export supports selecting validated workshops.

## Maintenance

- Updated `go_router` to 18.1.4 and `file_picker` to 13.3.3, including
  their resolved platform dependencies.
- Updated the workflow SDK to Flutter 3.44.9, which fixes framework
  architecture verification with Xcode 27.
- Aligned both dependency lockfiles with the CI SDK and enabled
  `--enforce-lockfile` in CI, translation validation, and release builds.
- Expanded regression coverage for trackpad navigation, JOIN labels,
  workshop libraries, imports, validation, and preview behavior.

## Verification

Checked locally with the workflow's pinned Flutter 3.44.9 / Dart 3.12.2:

- [x] Dependency installation with `--enforce-lockfile` for NodeQL and
  Onboarding Studio.
- [x] Dart formatting checks for `lib`, `test`, and `tool`, plus Onboarding
  Studio.
- [x] `flutter analyze` for both packages: no issues.
- [x] 347 NodeQL tests, 3 browser tests, and 2 Onboarding Studio tests.
- [x] 19 Python release and branch-synchronization tests.
- [x] Translation validation and release version validation.
- [x] Web release build.
- [x] macOS release build with Xcode 27.2.
- [x] GitHub Actions workflow validation with `actionlint`.

The checks above were run locally. Linux/Windows installers and release
publishing are verified by the GitHub-hosted release workflow after merge.

## Risk

Existing NodeQL projects remain compatible. Workshop draft imports create
independent copies with new IDs. Workshop authoring remains part of the
separate Workshop Admin; the public NodeQL entry point is unchanged.
