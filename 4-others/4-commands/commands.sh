#!/bin/sh
# Commands module — run quick system commands by index
set -eu

CMDS_DIR="$(cd "$(dirname "$0")" && pwd)"

_idx="${1:-}"
if [ -z "$_idx" ]; then
  echo "Commands (runs locally on this machine):"
  _n=1
  for _f in "$CMDS_DIR"/[0-9]*.sh; do
    _name=$(basename "$_f" .sh | sed 's/^[0-9]*-//')
    printf "  %2d) %s\n" "$_n" "$_name"
    _n=$(( _n + 1 ))
  done
  printf "> "
  read -r _idx
fi
[ -z "$_idx" ] && exit 0

# Find the script by index (01-based filename prefix)
_padded=$(printf '%02d' "$_idx" 2>/dev/null || echo "$_idx")
_script=$(ls "$CMDS_DIR"/${_padded}-*.sh 2>/dev/null | head -1)
if [ -n "$_script" ] && [ -f "$_script" ]; then
  sh "$_script"
else
  echo "Invalid command: $_idx"
fi
