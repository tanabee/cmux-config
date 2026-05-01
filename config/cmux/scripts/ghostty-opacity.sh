#!/usr/bin/env bash
# Adjust ghostty background-opacity used by cmux's embedded terminal.
# Usage:
#   ghostty-opacity.sh <+|-> [step]          # single-shot adjust
#   ghostty-opacity.sh hold <+|-> [step]     # start hold loop (key down)
#   ghostty-opacity.sh release               # stop hold loop (key up)
#
# hold モードは coalescing 設計:
#   - ticker  : TICK_INTERVAL ごとに target ファイルを step ずつ進める (cmux は呼ばない)
#   - applier : 最新の target を読んで適用 + cmux 呼び出し。cmux 待ちの間に進んだ
#               中間値はスキップされる (= coalesce) ため cmux 呼び出し回数が間引かれる。
set -euo pipefail

CONFIG="${HOME}/.config/ghostty/config"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
MIN="0.10"
MAX="1.00"
HOLD_LOCK="/tmp/cmux-opacity.hold"
TARGET_FILE="/tmp/cmux-opacity.target"
TICK_INTERVAL="0.02"
APPLIER_IDLE_INTERVAL="0.005"

clamp_step() {
  awk -v c="$1" -v s="$2" -v d="$3" -v lo="$MIN" -v hi="$MAX" '
    BEGIN {
      v = (d=="+") ? c+s : c-s
      if (v < lo) v = lo
      if (v > hi) v = hi
      printf("%.2f", v)
    }'
}

read_current_opacity() {
  local v
  v=$(awk -F'=' '
    /^[[:space:]]*background-opacity[[:space:]]*=/ {
      gsub(/[[:space:]]/,"",$2); print $2; exit
    }' "$CONFIG")
  printf '%s' "${v:-1.00}"
}

write_config() {
  local val="$1"
  if grep -qE '^[[:space:]]*background-opacity[[:space:]]*=' "$CONFIG"; then
    /usr/bin/sed -i '' -E "s|^[[:space:]]*background-opacity[[:space:]]*=.*|background-opacity = ${val}|" "$CONFIG"
  else
    printf '\nbackground-opacity = %s\n' "$val" >> "$CONFIG"
  fi
}

call_cmux() {
  if [[ -x "$CMUX_BIN" ]]; then
    "$CMUX_BIN" reload-config >/dev/null 2>&1 &
    "$CMUX_BIN" refresh-surfaces >/dev/null 2>&1 &
    wait
  fi
}

apply_step() {
  local dir="$1" step="$2"
  [[ -f "$CONFIG" ]] || { echo "ghostty config not found: $CONFIG" >&2; return 1; }
  local current new
  current=$(read_current_opacity)
  new=$(clamp_step "$current" "$step" "$dir")
  [[ "$new" == "$current" ]] && return 0
  write_config "$new"
  call_cmux
}

write_target() {
  local tmp="${TARGET_FILE}.tmp"
  printf '%s' "$1" > "$tmp"
  mv -f "$tmp" "$TARGET_FILE"
}

read_target() {
  cat "$TARGET_FILE" 2>/dev/null
}

ticker_loop() {
  local dir="$1" step="$2"
  local cur new
  while [[ -f "$HOLD_LOCK" ]]; do
    cur=$(read_target)
    [[ -z "$cur" ]] && cur="1.00"
    new=$(clamp_step "$cur" "$step" "$dir")
    [[ "$new" != "$cur" ]] && write_target "$new"
    sleep "$TICK_INTERVAL"
  done
}

applier_loop() {
  local last="$1"
  local target
  while [[ -f "$HOLD_LOCK" ]]; do
    target=$(read_target)
    if [[ -n "$target" && "$target" != "$last" ]]; then
      write_config "$target"
      call_cmux
      last="$target"
    else
      sleep "$APPLIER_IDLE_INTERVAL"
    fi
  done
}

stop_hold() {
  if [[ -f "$HOLD_LOCK" ]]; then
    local pids pid
    pids=$(cat "$HOLD_LOCK" 2>/dev/null || true)
    rm -f "$HOLD_LOCK" "$TARGET_FILE" "${TARGET_FILE}.tmp"
    if [[ -n "${pids:-}" ]]; then
      for pid in $pids; do
        kill "$pid" 2>/dev/null || true
      done
    fi
  fi
}

cmd="${1:-}"
case "$cmd" in
  hold)
    dir="${2:-}"
    step="${3:-0.02}"
    [[ "$dir" == "+" || "$dir" == "-" ]] || { echo "usage: $0 hold <+|-> [step]" >&2; exit 2; }

    stop_hold

    current=$(read_current_opacity)
    write_target "$current"
    : > "$HOLD_LOCK"

    (ticker_loop "$dir" "$step") </dev/null >/dev/null 2>&1 &
    ticker_pid=$!
    disown "$ticker_pid" 2>/dev/null || true

    (applier_loop "$current") </dev/null >/dev/null 2>&1 &
    applier_pid=$!
    disown "$applier_pid" 2>/dev/null || true

    if [[ -f "$HOLD_LOCK" ]]; then
      printf '%s %s' "$ticker_pid" "$applier_pid" > "$HOLD_LOCK"
    else
      kill "$ticker_pid" "$applier_pid" 2>/dev/null || true
    fi
    ;;
  release)
    stop_hold
    ;;
  +|-)
    apply_step "$cmd" "${2:-0.02}"
    ;;
  *)
    echo "usage: $0 <+|-> [step]" >&2
    echo "       $0 hold <+|-> [step]" >&2
    echo "       $0 release" >&2
    exit 2
    ;;
esac
