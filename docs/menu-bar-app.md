# Menu Bar App

The menu bar app should stay thin. `CodexAutofocusCore` owns the behavior and the
app only presents controls.

## Shape

- SwiftUI `App` entry point with `MenuBarExtra`.
- LSUIElement app bundle so there is no Dock icon.
- One menu item that toggles autofocus on and off without editing Codex config.
- An icon-only menu bar item with the app name available through accessibility
  and `Quit Codex Autofocus`.
- Secondary repair/debug actions hidden under `Advanced`.
- Status refreshes automatically while the app runs; there is no manual refresh
  menu item.

## Toggle Flow

Enabled:

1. Call `CodexAutofocus.setEnabled(true, binaryPath:)`.
2. Refresh menu state from `CodexAutofocus.status(binaryPath:)`.

Disabled:

1. Call `CodexAutofocus.setEnabled(false, binaryPath:)`.
2. Refresh menu state.

Register Hook:

1. Build or locate the installed `codex-autofocus` helper.
2. Call `CodexAutofocus.install(binaryPath:)`.
3. Refresh menu state.

Remove Hook:

1. Call `CodexAutofocus.uninstall(binaryPath:)`.
2. Refresh menu state.

Trust Installed Hook:

1. Show a warning confirmation explaining that this bypasses Codex's normal hook
   review UI.
2. If confirmed, call `CodexAutofocus.trustInstalledHook(binaryPath:)`.
3. Refresh menu state.

This action is intentionally under `Advanced` and is never part of automatic
install or repair. Normal installs should let Codex ask the user to review new or
modified hooks.

## Packaging Notes

- The helper binary should be bundled into the app or installed into
  `~/.codex/bin/codex-autofocus` by the app on first run.
- Use the stable bundle identifier `com.jonasjancarik.codex-autofocus` unless a
  signing or distribution requirement says otherwise.
- Avoid Apple Events for focusing Codex. `/usr/bin/open -b com.openai.codex`
  avoids TCC automation prompts.
