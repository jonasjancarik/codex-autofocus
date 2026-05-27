# codex-autofocus

Bring the Codex desktop app to the front when a Codex turn ends.

This starts as a small SwiftPM command-line utility. The core install/uninstall
logic is in a library target so a future menu bar app can toggle the same setting
without reimplementing Codex hook management.

## Install

```sh
scripts/install.sh
```

The installer:

1. builds `codex-autofocus` in release mode,
2. copies it to `~/.codex/bin/codex-autofocus`,
3. registers a managed `Stop` hook in `~/.codex/hooks.json`,
4. enables `features.hooks` in `~/.codex/config.toml` if needed,
5. migrates away from the earlier experimental `notify = codex-autofocus` wrapper
   if it finds one.

The hook command is marked so it can coexist with other Codex hooks:

```sh
'/Users/janca/.codex/bin/codex-autofocus' --hook --managed-by codex-autofocus
```

When Codex invokes the hook, `codex-autofocus` checks its runtime state. If it is
enabled, it runs:

```sh
/usr/bin/open -b com.openai.codex
```

## Enable / Disable

These commands only flip runtime state. They do not edit Codex config or hooks.

```sh
~/.codex/bin/codex-autofocus enable --binary ~/.codex/bin/codex-autofocus
~/.codex/bin/codex-autofocus disable --binary ~/.codex/bin/codex-autofocus
```

## Uninstall Hook

```sh
scripts/uninstall.sh
```

This removes only hooks marked `--managed-by codex-autofocus` from
`~/.codex/hooks.json`. It does not touch unrelated hooks.

## Status

```sh
~/.codex/bin/codex-autofocus status --binary ~/.codex/bin/codex-autofocus
```

## Development

```sh
swift build
swift test
swift run codex-autofocus --help
```

## Smoke Test

```sh
scripts/smoke.sh
```

The smoke test removes and re-registers the managed hook, verifies
`~/.codex/config.toml` no longer points `notify` at `codex-autofocus`, flips the
runtime enabled flag off and on, and runs dummy hook invocations. It leaves the
hook registered and autofocus enabled.

## Future Menu Bar App

The intended next product is a tiny macOS menu bar app with:

- an Enabled/Disabled toggle backed by `CodexAutofocusCore.setEnabled`,
- a status item icon that reflects hook registration and runtime state,
- a “Reveal Config” command for `~/.codex/config.toml`,
- a “Reveal Hooks” command for `~/.codex/hooks.json`,
- LSUIElement packaging so it lives only in the menu bar.

See [docs/menu-bar-app.md](docs/menu-bar-app.md).
