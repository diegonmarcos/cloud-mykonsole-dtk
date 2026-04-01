#!/bin/sh
# Emergency memory cleanup — stop swap thrashing on E2 Micros
# Stops all containers, drops caches, kills heavy processes, restarts containers
set -eu

echo "=== EMERGENCY MEMORY CLEANUP ==="
echo "Before:"
free -m

# 1. Stop all containers (biggest RAM consumer)
echo ""
echo "[1/4] Stopping all containers..."
sudo docker stop $(sudo docker ps -q 2>/dev/null) 2>/dev/null || true

# 2. Drop kernel caches
echo "[2/4] Dropping caches..."
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'

# 3. Kill any stuck docker pull / nix processes
echo "[3/4] Killing stuck pulls/builds..."
sudo pkill -f 'docker pull' 2>/dev/null || true
sudo pkill -f 'nix-store' 2>/dev/null || true
sudo pkill -f 'nix-build' 2>/dev/null || true

# 4. Wait for swap to drain
echo "[4/4] Waiting for swap drain..."
sleep 5

echo ""
echo "After:"
free -m

echo ""
echo "Containers stopped. To restart: sudo bash /opt/scripts/container-control-init.sh"
