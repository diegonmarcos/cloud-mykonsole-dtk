#!/bin/sh
# Start a tmux session served via ttyd on WireGuard IP (web-accessible terminal)
# Access: http://<wg-ip>:7681 from any device on the WG mesh
set -eu

SESSION="ops"
PORT="${1:-7681}"

# Detect WG IP
WG_IP=$(ip -4 addr show wg0 2>/dev/null | grep -oP 'inet \K[0-9.]+' || echo "0.0.0.0")

# Check if ttyd is available
if ! command -v ttyd >/dev/null 2>&1; then
  echo "ttyd not found — installing..."
  if command -v nix-env >/dev/null 2>&1; then
    nix-env -iA nixpkgs.ttyd 2>/dev/null || true
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y ttyd 2>/dev/null || true
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y ttyd 2>/dev/null || true
  fi
  command -v ttyd >/dev/null 2>&1 || { echo "FATAL: ttyd not available"; exit 1; }
fi

# Create or attach tmux session
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session '$SESSION' already exists"
else
  tmux new-session -d -s "$SESSION"
  echo "Created tmux session '$SESSION'"
fi

# Kill existing ttyd if running on this port
pkill -f "ttyd.*:$PORT" 2>/dev/null || true
sleep 1

# Start ttyd bound to WG IP only (not public)
echo "Starting ttyd on http://${WG_IP}:${PORT}"
ttyd -W -p "$PORT" -i "$WG_IP" tmux attach -t "$SESSION" &
TTYD_PID=$!

echo ""
echo "══════════════════════════════════════════════"
echo "  Web terminal: http://${WG_IP}:${PORT}"
echo "  tmux session: $SESSION"
echo "  ttyd PID: $TTYD_PID"
echo "  Stop: kill $TTYD_PID"
echo "══════════════════════════════════════════════"
