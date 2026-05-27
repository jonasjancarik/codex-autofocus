#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
installed_binary="$HOME/.codex/bin/codex-autofocus"

cd "$repo_root"
swift build -c release --product codex-autofocus

mkdir -p "$HOME/.codex/bin"
cp "$repo_root/.build/release/codex-autofocus" "$installed_binary"
chmod 755 "$installed_binary"

"$installed_binary" install --binary "$installed_binary"
