#!/usr/bin/env bash
# Adjust ghostty background-opacity used by cmux's embedded terminal.
# Usage:
#   ghostty-opacity.sh <+|-> [step]          # single-shot adjust
#   ghostty-opacity.sh hold <+|-> [step]     # start hold loop (key down)
#   ghostty-opacity.sh release               # stop hold loop (key up)
set -euo pipefail

CONFIG="${HOME}/.config/ghostty/config"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
MIN="0.10"
MAX="1.00"
HOLD_LOCK="/tmp/cmux-opacity.hold"

apply_step() {
  local dir="$1" step="$2"
  [[ -f "$CONFIG" ]] || { echo "ghostty config not found: $CONFIG" >&2; return 1; }

  local current new
  current=$(awk -F'=' '
    /^[[:space:]]*background-opacity[[:space:]]*=/ {
      gsub(/[[:space:]]/,"",$2); print $2; exit
    }' "$CONFIG")
  current="${current:-1.00}"

  new=$(awk -v c="$current" -v s="$step" -v d="$dir" -v lo="$MIN" -v hi="$MAX" '
    BEGIN {
      v = (d=="+") ? c+s : c-s
      if (v < lo) v = lo
      if (v > hi) v = hi
      printf("%.2f", v)
    }')

  [[ "$new" == "$current" ]] && return 0

  if grep -qE '^[[:space:]]*background-opacity[[:space:]]*=' "$CONFIG"; then
    /usr/bin/sed -i '' -E "s|^[[:space:]]*background-opacity[[:space:]]*=.*|background-opacity = ${new}|" "$CONFIG"
  else
    printf '\nbackground-opacity = %s\n' "$new" >> "$CONFIG"
  fi

  if [[ -x "$CMUX_BIN" ]]; then
    "$CMUX_BIN" reload-config >/dev/null 2>&1 &
    "$CMUX_BIN" refresh-surfaces >/dev/null 2>&1 &
    wait
  fi
}

stop_hold() {
  if [[ -f "$HOLD_LOCK" ]]; then
    local pid
    pid=$(cat "$HOLD_LOCK" 2>/dev/null || true)
    rm -f "$HOLD_LOCK"
    [[ -n "${pid:-}" ]] && kill "$pid" 2>/dev/null || true
  fi
}

cmd="${1:-}"
case "$cmd" in
  hold)
    dir="${2:-}"
    step="${3:-0.05}"
    [[ "$dir" == "+" || "$dir" == "-" ]] || { echo "usage: $0 hold <+|-> [step]" >&2; exit 2; }

    stop_hold

    (
      apply_step "$dir" "$step" || exit 0
      while [[ -f "$HOLD_LOCK" ]]; do
        apply_step "$dir" "$step" || break
      done
    ) </dev/null >/dev/null 2>&1 &
    loop_pid=$!
    echo "$loop_pid" > "$HOLD_LOCK"
    disown "$loop_pid" 2>/dev/null || true
    ;;
  release)
    stop_hold
    ;;
  +|-)
    apply_step "$cmd" "${2:-0.05}"
    ;;
  *)
    echo "usage: $0 <+|-> [step]" >&2
    echo "       $0 hold <+|-> [step]" >&2
    echo "       $0 release" >&2
    exit 2
    ;;
esac
