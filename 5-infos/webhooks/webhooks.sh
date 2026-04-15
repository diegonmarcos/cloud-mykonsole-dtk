#!/bin/sh
# DTK Webhooks — bidirectional remote execution bridge via ntfy
# Claude publishes commands to ntfy topic, VM fetches+runs+returns output
#
# Flow:
#   1. Claude writes commands to ntfy topic: dtk-cmd-<hostname>
#   2. User runs: dtk.sh 47  (or: dtk.sh webhooks)
#   3. Script fetches latest command from ntfy, executes it, posts output to dtk-out-<hostname>
#   4. Claude reads output from dtk-out-<hostname>
#
# Modes:
#   once  — fetch one command, run it, post output, exit (default)
#   watch — loop: poll every 5s for new commands, run each, post output
#   post  — post a manual message to the output topic
set -eu

# ntfy internal access — no Authelia. Check health with JSON response (not HTML redirect)
NTFY_BASE=""
for _url in "http://localhost:8090" "http://127.0.0.1:8090" "http://10.0.0.1:8090"; do
  _resp=$(curl -sf -m 2 "$_url/v1/health" 2>/dev/null || echo "")
  case "$_resp" in *healthy*) NTFY_BASE="$_url"; break ;; esac
done
if [ -z "$NTFY_BASE" ]; then
  echo "  ERROR: ntfy not reachable on any internal address"
  echo "  Tried: localhost:8090, 127.0.0.1:8090, 10.0.0.1:8090"
  exit 1
fi
VM_NAME=$(hostname -s 2>/dev/null || echo "unknown")
CMD_TOPIC="dtk-cmd-${VM_NAME}"
OUT_TOPIC="dtk-out-${VM_NAME}"

SUDO="sudo"
[ "$(id -u)" = "0" ] && SUDO=""
command -v sudo >/dev/null 2>&1 || SUDO=""

# ── Helpers ──────────────────────────────────────────────────────

ntfy_fetch() {
  # Fetch latest message from a topic (poll=true = don't wait, since=1h = last hour)
  curl -sf "${NTFY_BASE}/${1}/json?poll=1&since=5m" 2>/dev/null | tail -1
}

ntfy_post() {
  # Post message to a topic, with title
  _topic="$1"; _title="$2"; shift 2
  _body="$*"
  # ntfy has 4096 byte message limit — truncate if needed
  _len=$(printf '%s' "$_body" | wc -c)
  if [ "$_len" -gt 3800 ]; then
    _body="$(printf '%s' "$_body" | head -c 3800)
... [TRUNCATED — ${_len} bytes total]"
  fi
  curl -sf -X POST "${NTFY_BASE}/${_topic}" \
    -H "Title: ${_title}" \
    -H "Tags: dtk,${VM_NAME}" \
    -d "$_body" >/dev/null 2>&1
}

run_command() {
  _cmd="$1"
  echo "  Executing: $_cmd"
  echo "────────────────────────────────────────"
  # Run with sudo -E to preserve PATH, nix paths first to skip docker-capped wrappers
  _FULL_PATH="/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin"
  if [ -n "$SUDO" ]; then
    _output=$(PATH="$_FULL_PATH" $SUDO -E sh -c "$_cmd" 2>&1) || true
  else
    _output=$(PATH="$_FULL_PATH" sh -c "$_cmd" 2>&1) || true
  fi
  echo "$_output"
  echo "────────────────────────────────────────"
  # Post output back
  ntfy_post "$OUT_TOPIC" "${VM_NAME}: command result" "$ ${_cmd}
${_output}"
  echo "  Output posted to ${OUT_TOPIC}"
}

# ── Main ─────────────────────────────────────────────────────────

MODE="${1:-once}"

echo "══════════════════════════════════════════════"
echo "  DTK Webhooks — ${VM_NAME}"
echo "══════════════════════════════════════════════"
echo "  CMD topic: ${CMD_TOPIC}"
echo "  OUT topic: ${OUT_TOPIC}"
echo "  Mode: ${MODE}"
echo ""

case "$MODE" in
  once)
    echo "  Fetching latest command..."
    MSG=$(ntfy_fetch "$CMD_TOPIC")
    if [ -z "$MSG" ]; then
      echo "  No commands in queue (last 5 min)"
      echo "  Waiting for command (60s timeout)..."
      # Wait for a message (long-poll)
      MSG=$(curl -sf "${NTFY_BASE}/${CMD_TOPIC}/json?poll=1&since=5m" 2>/dev/null | tail -1)
      [ -z "$MSG" ] && echo "  Timeout — no command received" && exit 0
    fi
    # Extract message body from JSON
    CMD=$(echo "$MSG" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p' 2>/dev/null || echo "")
    if [ -z "$CMD" ]; then
      # Try python/jq for proper JSON parsing
      if command -v jq >/dev/null 2>&1; then
        CMD=$(echo "$MSG" | jq -r '.message // empty' 2>/dev/null || echo "")
      elif command -v python3 >/dev/null 2>&1; then
        CMD=$(echo "$MSG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))" 2>/dev/null || echo "")
      fi
    fi
    if [ -z "$CMD" ]; then
      echo "  Could not parse command from message"
      echo "  Raw: $MSG"
      exit 1
    fi
    echo "  Command: $CMD"
    echo ""
    run_command "$CMD"
    ;;

  watch)
    echo "  Watching for commands (Ctrl+C to stop)..."
    LAST_ID=""
    while true; do
      MSG=$(ntfy_fetch "$CMD_TOPIC")
      if [ -n "$MSG" ]; then
        # Get message ID to avoid re-running
        MSG_ID=$(echo "$MSG" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' 2>/dev/null || echo "")
        if [ -z "$MSG_ID" ] && command -v jq >/dev/null 2>&1; then
          MSG_ID=$(echo "$MSG" | jq -r '.id // empty' 2>/dev/null || echo "")
        fi
        if [ "$MSG_ID" != "$LAST_ID" ] && [ -n "$MSG_ID" ]; then
          LAST_ID="$MSG_ID"
          CMD=""
          if command -v jq >/dev/null 2>&1; then
            CMD=$(echo "$MSG" | jq -r '.message // empty' 2>/dev/null || echo "")
          else
            CMD=$(echo "$MSG" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p' 2>/dev/null || echo "")
          fi
          if [ -n "$CMD" ]; then
            echo ""
            echo "  [$(date '+%H:%M:%S')] New command received"
            run_command "$CMD"
          fi
        fi
      fi
      sleep 5
    done
    ;;

  post)
    shift
    _msg="${*:-$(hostname -s) webhook ready}"
    ntfy_post "$OUT_TOPIC" "${VM_NAME}: manual" "$_msg"
    echo "  Posted to ${OUT_TOPIC}: $_msg"
    ;;

  *)
    echo "Usage: webhooks.sh [once|watch|post <message>]"
    exit 1
    ;;
esac
