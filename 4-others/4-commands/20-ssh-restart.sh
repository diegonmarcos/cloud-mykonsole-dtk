#!/bin/sh
# Restart SSH + flush firewall — fixes SSH hanging after reboot
# Handles both sshd (Fedora/Arch) and ssh (Ubuntu/Debian) service names
set -eu

SUDO="sudo"
[ "$(id -u)" = "0" ] && SUDO=""

echo "Flushing iptables..."
$SUDO iptables -F INPUT 2>/dev/null || true
$SUDO iptables -P INPUT ACCEPT 2>/dev/null || true
echo "  iptables flushed (INPUT ACCEPT)"

echo "Restarting SSH daemon..."
if $SUDO systemctl restart sshd 2>/dev/null; then
  echo "  sshd restarted"
elif $SUDO systemctl restart ssh 2>/dev/null; then
  echo "  ssh restarted"
else
  echo "  ERROR: neither sshd nor ssh service found"
fi

echo "Restarting Dropbear (port 2200)..."
$SUDO systemctl restart dropbear 2>/dev/null && echo "  dropbear restarted" || echo "  dropbear not installed (skip)"

echo ""
echo "Listening ports:"
ss -tlnp 2>/dev/null | grep -E ":22 |:2200 " || echo "  (none)"
