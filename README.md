# codex-autofocus

`codex-autofocus` is a small macOS utility that brings the Codex desktop app to
the front when a Codex turn finishes.

It has two parts:

- a command-line helper that Codex runs from a `Stop` hook
- a menu bar app for turning the behavior on or off and repairing the hook setup

The helper is intentionally narrow. It does not read your Codex transcript, send
network requests, or control other apps. When it is enabled, it runs:

```sh
/usr/bin/open -b com.openai.codex
```

Codex runs `Stop` hooks right before it completes a turn. Codex Autofocus
therefore schedules the focus action shortly after the hook starts and then lets
the hook return immediately. That avoids pulling the app forward while Codex is
still settling the final turn output.

Each hook run also appends a short diagnostic line to:

```sh
~/.codex/codex-autofocus/debug.log
```

The log records timing, hook event metadata, thread and turn ids when Codex
provides them, and the result of the later focus command. It deliberately avoids
writing prompt text or assistant message text.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer for building from source
- Codex hooks enabled in Codex

## Install

### Homebrew

Homebrew is the easiest install path once the tap is available:

```sh
brew tap jonasjancarik/tap
brew install codex-autofocus
codex-autofocus install --binary "$(brew --prefix codex-autofocus)/bin/codex-autofocus"
```

Start the menu bar app with:

```sh
codex-autofocus-menu
```

The first command installs the helper and menu app. The `codex-autofocus install`
command registers the Codex hook. Codex may still ask you to approve that hook
before it runs.

### From Source

From the project directory:

```sh
scripts/install.sh
```

The installer builds the helper, copies it to `~/.codex/bin/codex-autofocus`,
and registers a managed `Stop` hook in `~/.codex/hooks.json`.

The installed hook looks like this:

```sh
'/Users/janca/.codex/bin/codex-autofocus' --hook --managed-by codex-autofocus
```

The `--managed-by codex-autofocus` marker is important. It lets this project find
and update only its own hook while leaving hooks from other tools alone.

If an older experimental `notify = codex-autofocus` setup is present, the
installer migrates away from it and restores the previous notifier when it can.

## Approve The Hook

Codex asks you to review new or changed hooks before it runs them. That is a
security step: hooks can run outside the sandbox.

After installing, open Codex's hook review UI and trust the Codex Autofocus
`Stop` hook. The menu bar app shows `Approve hook in Codex` until Codex has
recorded that trust.

There is also a manual option: `Advanced > Trust Installed Hook...`.
Use it only if you want Codex Autofocus to write the hook approval record directly
to `~/.codex/config.toml` instead of approving the hook through Codex's normal
review UI. The app shows a confirmation prompt first, and this is never done
automatically.

## Run The Menu Bar App

```sh
script/build_and_run.sh
```

This builds `dist/Codex Autofocus.app` and launches it as a menu-bar-only app.
The app has no Dock icon.

The bundle can also be built without launching it:

```sh
script/package_app.sh --configuration release
```

The menu is intentionally small:

- current state, such as `On · Hook installed`
- `Turn Autofocus On` or `Turn Autofocus Off`
- `Advanced` repair and file actions
- `Quit Codex Autofocus`

Status refreshes automatically while the app is running. There is no manual
refresh command.

## Turn Autofocus On Or Off

The menu bar app is the easiest way to toggle autofocus.

The command-line helper can do the same thing:

```sh
~/.codex/bin/codex-autofocus enable --binary ~/.codex/bin/codex-autofocus
~/.codex/bin/codex-autofocus disable --binary ~/.codex/bin/codex-autofocus
```

Enable and disable only change Codex Autofocus runtime state. They do not edit
`~/.codex/hooks.json` or `~/.codex/config.toml`.

## Check Status

```sh
~/.codex/bin/codex-autofocus status --binary ~/.codex/bin/codex-autofocus
```

Status reports whether autofocus is enabled, whether the managed hook is
registered, which hook command is installed, and whether any setup issue needs
attention.

## Uninstall The Hook

```sh
scripts/uninstall.sh
```

This removes only hooks marked `--managed-by codex-autofocus` from
`~/.codex/hooks.json`. It does not remove unrelated hooks.

## Development

Useful commands:

```sh
swift build
swift test
swift run codex-autofocus --help
scripts/smoke.sh
```

`scripts/smoke.sh` removes and re-registers the managed hook, verifies that the
legacy `notify` setup is not active, toggles autofocus off and on, and runs dummy
hook invocations. It leaves the hook registered and autofocus enabled.

Project layout:

- `Sources/CodexAutofocusCore`: shared install, hook, status, and trust logic
- `Sources/CodexAutofocus`: command-line helper
- `Sources/CodexAutofocusMenuBar`: macOS menu bar app
- `Tests/CodexAutofocusCoreTests`: regression tests
- `docs/menu-bar-app.md`: notes on the menu bar app behavior
