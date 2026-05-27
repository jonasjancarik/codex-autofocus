#!/bin/zsh
set -euo pipefail

installed_binary="$HOME/.codex/bin/codex-autofocus"

if [[ ! -x "$installed_binary" ]]; then
  echo "codex-autofocus is not installed at $installed_binary" >&2
  exit 1
fi

"$installed_binary" uninstall --binary "$installed_binary"
