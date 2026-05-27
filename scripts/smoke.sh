#!/bin/zsh
set -euo pipefail

binary="${CODEX_AUTOFOCUS_BINARY:-$HOME/.codex/bin/codex-autofocus}"
config="$HOME/.codex/config.toml"
hooks="$HOME/.codex/hooks.json"
marker="--managed-by codex-autofocus"

if [[ ! -x "$binary" ]]; then
  echo "codex-autofocus is not installed at $binary" >&2
  echo "Run scripts/install.sh first." >&2
  exit 1
fi

expect_status() {
  local expected_enabled="$1"
  local expected_registered="$2"
  local output
  output="$($binary status --binary "$binary")"
  printf '%s\n' "$output"
  if [[ "$output" != "$expected_enabled"$'\n'* ]]; then
    echo "expected enabled state '$expected_enabled'" >&2
    exit 1
  fi
  if ! grep -Fqx "$expected_registered" <<<"$output"; then
    echo "expected registration state '$expected_registered'" >&2
    exit 1
  fi
}

expect_hook() {
  if ! grep -Fq -- "$marker" "$hooks"; then
    echo "expected managed hook marker in $hooks" >&2
    exit 1
  fi
}

expect_no_hook() {
  if [[ -f "$hooks" ]] && grep -Fq -- "$marker" "$hooks"; then
    echo "did not expect managed hook marker in $hooks" >&2
    exit 1
  fi
}

expect_notify_not_wrapped() {
  if grep -Fq "notify = [\"$binary\", \"turn-ended\"]" "$config"; then
    echo "legacy notify wrapper is still installed" >&2
    exit 1
  fi
}

echo "Initial status"
$binary status --binary "$binary"
expect_notify_not_wrapped

echo
echo "Remove hook"
$binary uninstall --binary "$binary"
expect_status disabled "not registered"
expect_no_hook
expect_notify_not_wrapped

echo
echo "Register hook"
$binary install --binary "$binary"
expect_status disabled registered
expect_hook
expect_notify_not_wrapped

echo
echo "Disable runtime"
$binary disable --binary "$binary"
expect_status disabled registered
expect_hook

echo
echo "Dummy disabled hook"
$binary --hook --managed-by codex-autofocus

echo
echo "Enable runtime"
$binary enable --binary "$binary"
expect_status enabled registered
expect_hook

echo
echo "Dummy enabled hook"
$binary --hook --managed-by codex-autofocus

echo
echo "Smoke test passed"
