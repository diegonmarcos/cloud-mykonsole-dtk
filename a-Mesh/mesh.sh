#!/bin/sh
# mesh.sh - WireGuard Mesh VPN Manager
# POSIX-compliant shell script
#
# Usage:
#   mesh              # Show dashboard
#   mesh up           # Start VPN tunnel
#   mesh down         # Stop VPN tunnel
#   mesh status       # Ping all peers (quick)
#   mesh config       # Show wg0.conf
#   mesh path         # Show config file path
#   mesh peers        # Peer topology table
#   mesh --check      # Check dependencies
#   mesh --help       # Show help

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/mesh.json"

# Colors (disable if not a terminal)
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_RED="\033[31m"
    C_GREEN="\033[32m"
    C_YELLOW="\033[33m"
    C_BLUE="\033[34m"
    C_CYAN="\033[36m"
    C_DIM="\033[2m"
else
    C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_DIM=''
fi

# Symbols
OK="${C_GREEN}✓${C_RESET}"
FAIL="${C_RED}✗${C_RESET}"
WARN="${C_YELLOW}!${C_RESET}"
INFO="${C_BLUE}→${C_RESET}"

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

check_deps() {
    printf "${C_BOLD}=== Dependency Check ===${C_RESET}\n\n"

    missing_required=""
    missing_optional=""

    # Required: jq, ip
    printf "${C_BOLD}Required:${C_RESET}\n"
    for dep in jq ip; do
        if command -v "$dep" >/dev/null 2>&1; then
            version=$("$dep" --version 2>&1 | head -1)
            printf "  $OK ${C_GREEN}%-12s${C_RESET} %s\n" "$dep" "$version"
        else
            printf "  $FAIL ${C_RED}%-12s${C_RESET} ${C_DIM}not found${C_RESET}\n" "$dep"
            missing_required="${missing_required}${dep} "
        fi
    done

    # Optional: wg, nc, systemctl
    printf "\n${C_BOLD}Optional:${C_RESET}\n"
    for dep in wg nc systemctl; do
        if command -v "$dep" >/dev/null 2>&1; then
            version=$("$dep" --version 2>&1 | head -1)
            printf "  $OK ${C_GREEN}%-12s${C_RESET} %s\n" "$dep" "$version"
        else
            printf "  $WARN ${C_YELLOW}%-12s${C_RESET} ${C_DIM}not found${C_RESET}\n" "$dep"
            missing_optional="${missing_optional}${dep} "
        fi
    done

    if [ -n "$missing_required" ]; then
        printf "\n$FAIL ${C_RED}Missing required: ${missing_required}${C_RESET}\n"
        return 1
    else
        printf "\n$OK ${C_GREEN}All required dependencies installed${C_RESET}\n"
        return 0
    fi
}

# =============================================================================
# CONFIG PARSER (reads mesh.json via jq)
# =============================================================================

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        printf "$FAIL ${C_RED}Config not found: $CONFIG_FILE${C_RESET}\n"
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        printf "$FAIL ${C_RED}jq is required but not installed${C_RESET}\n"
        exit 1
    fi

    WG_ADDRESS=$(jq -r '.interface.address' "$CONFIG_FILE")
    WG_CONFIG_DIR=$(jq -r '.interface.config_dir' "$CONFIG_FILE" | sed "s|^~|$HOME|")
    WG_CONFIG_FILE=$(jq -r '.interface.config_file' "$CONFIG_FILE")
    WG_TUNNEL=$(jq -r '.interface.tunnel_name' "$CONFIG_FILE")
    WG_CONF="$WG_CONFIG_DIR/$WG_CONFIG_FILE"

    PEER_COUNT=$(jq '.peers | length' "$CONFIG_FILE")
}

# =============================================================================
# BACKEND DETECTION
# =============================================================================

# Detect whether systemd manages the wg interface or we use wg-quick
detect_backend() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files "wireguard-${WG_TUNNEL}.service" >/dev/null 2>&1; then
            BACKEND="systemd"
            BACKEND_UNIT="wireguard-${WG_TUNNEL}.service"
            return
        fi
    fi
    BACKEND="wg-quick"
    BACKEND_UNIT=""
}

# =============================================================================
# TUNNEL STATE
# =============================================================================

# Check if tunnel interface exists
tunnel_is_up() {
    ip link show "$WG_TUNNEL" >/dev/null 2>&1
}

# Get tunnel state as string
tunnel_state() {
    if tunnel_is_up; then
        printf "${C_GREEN}UP${C_RESET}"
    else
        printf "${C_RED}DOWN${C_RESET}"
    fi
}

# Get systemd unit state
systemd_state() {
    if [ "$BACKEND" = "systemd" ]; then
        state=$(systemctl is-active "$BACKEND_UNIT" 2>/dev/null || echo "unknown")
        case "$state" in
            active)   printf "${C_GREEN}active${C_RESET}" ;;
            inactive) printf "${C_DIM}inactive${C_RESET}" ;;
            failed)   printf "${C_RED}failed${C_RESET}" ;;
            *)        printf "${C_DIM}${state}${C_RESET}" ;;
        esac
    else
        printf "${C_DIM}n/a${C_RESET}"
    fi
}

# =============================================================================
# PEER HEALTH CHECK
# =============================================================================

# Check if a peer is reachable via WireGuard IP (nc -z on port 22, 2s timeout)
check_peer() {
    wg_ip="$1"
    name="$2"

    # Skip local peer
    if [ "$name" = "local" ]; then
        printf "${C_DIM}-${C_RESET}"
        return
    fi

    # Must have tunnel up to check peers
    if ! tunnel_is_up; then
        printf "${C_DIM}?${C_RESET}"
        return
    fi

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 2 "$wg_ip" 22 >/dev/null 2>&1; then
            printf "${C_GREEN}UP${C_RESET}"
        else
            printf "${C_RED}DOWN${C_RESET}"
        fi
    else
        # Fallback: ping
        if ping -c 1 -W 2 "$wg_ip" >/dev/null 2>&1; then
            printf "${C_GREEN}UP${C_RESET}"
        else
            printf "${C_RED}DOWN${C_RESET}"
        fi
    fi
}

# =============================================================================
# COMMANDS
# =============================================================================

cmd_up() {
    if tunnel_is_up; then
        printf "$WARN ${C_YELLOW}Tunnel ${WG_TUNNEL} is already up${C_RESET}\n"
        return 0
    fi

    printf "$INFO Starting tunnel ${C_BOLD}${WG_TUNNEL}${C_RESET}...\n"

    if [ "$BACKEND" = "systemd" ]; then
        if sudo systemctl start "$BACKEND_UNIT" 2>&1; then
            printf "$OK ${C_GREEN}Tunnel started (systemd: ${BACKEND_UNIT})${C_RESET}\n"
        else
            printf "$FAIL ${C_RED}Failed to start tunnel${C_RESET}\n"
            return 1
        fi
    else
        if [ ! -f "$WG_CONF" ]; then
            printf "$FAIL ${C_RED}Config not found: ${WG_CONF}${C_RESET}\n"
            return 1
        fi
        if sudo wg-quick up "$WG_CONF" 2>&1; then
            printf "$OK ${C_GREEN}Tunnel started (wg-quick)${C_RESET}\n"
        else
            printf "$FAIL ${C_RED}Failed to start tunnel${C_RESET}\n"
            return 1
        fi
    fi
}

cmd_down() {
    if ! tunnel_is_up; then
        printf "$WARN ${C_YELLOW}Tunnel ${WG_TUNNEL} is already down${C_RESET}\n"
        return 0
    fi

    printf "$INFO Stopping tunnel ${C_BOLD}${WG_TUNNEL}${C_RESET}...\n"

    if [ "$BACKEND" = "systemd" ]; then
        if sudo systemctl stop "$BACKEND_UNIT" 2>&1; then
            printf "$OK ${C_GREEN}Tunnel stopped (systemd)${C_RESET}\n"
        else
            printf "$FAIL ${C_RED}Failed to stop tunnel${C_RESET}\n"
            return 1
        fi
    else
        if sudo wg-quick down "$WG_CONF" 2>&1; then
            printf "$OK ${C_GREEN}Tunnel stopped (wg-quick)${C_RESET}\n"
        else
            printf "$FAIL ${C_RED}Failed to stop tunnel${C_RESET}\n"
            return 1
        fi
    fi
}

cmd_status() {
    printf "${C_BOLD}=== Peer Connectivity ===${C_RESET}\n\n"

    if ! tunnel_is_up; then
        printf "$WARN ${C_YELLOW}Tunnel is down — start with: mesh up${C_RESET}\n"
        return
    fi

    i=0
    while [ "$i" -lt "$PEER_COUNT" ]; do
        name=$(jq -r ".peers[$i].name" "$CONFIG_FILE")
        wg_ip=$(jq -r ".peers[$i].wg_ip" "$CONFIG_FILE")
        role=$(jq -r ".peers[$i].role" "$CONFIG_FILE")

        status=$(check_peer "$wg_ip" "$name")
        printf "  %-18s %-14s %-28s %b\n" "$name" "$wg_ip" "$role" "$status"
        i=$((i + 1))
    done
}

cmd_config() {
    if [ -f "$WG_CONF" ]; then
        printf "${C_BOLD}=== %s ===${C_RESET}\n\n" "$WG_CONF"
        cat "$WG_CONF"
    else
        printf "$FAIL ${C_RED}Config not found: ${WG_CONF}${C_RESET}\n"
    fi
}

cmd_path() {
    printf "%s\n" "$WG_CONF"
}

cmd_peers() {
    printf "${C_BOLD}=== Peer Topology ===${C_RESET}\n\n"
    printf "  ${C_BOLD}%-18s %-14s %-22s %s${C_RESET}\n" "NAME" "WG IP" "PUBLIC IP" "ROLE"
    printf "  ${C_DIM}──────────────────────────────────────────────────────────────────────────${C_RESET}\n"

    i=0
    while [ "$i" -lt "$PEER_COUNT" ]; do
        name=$(jq -r ".peers[$i].name" "$CONFIG_FILE")
        wg_ip=$(jq -r ".peers[$i].wg_ip" "$CONFIG_FILE")
        pub_ip=$(jq -r ".peers[$i].public_ip" "$CONFIG_FILE")
        role=$(jq -r ".peers[$i].role" "$CONFIG_FILE")

        if [ "$name" = "local" ]; then
            printf "  ${C_CYAN}%-18s${C_RESET} %-14s %-22s %s\n" "$name (you)" "$wg_ip" "$pub_ip" "$role"
        else
            printf "  %-18s %-14s %-22s %s\n" "$name" "$wg_ip" "$pub_ip" "$role"
        fi
        i=$((i + 1))
    done
}

# =============================================================================
# DASHBOARD (no-args default)
# =============================================================================

cmd_dashboard() {
    detect_backend

    printf "\n${C_BOLD}=== WireGuard Mesh VPN ===${C_RESET}\n"

    # ── Status ──
    printf "\n  ${C_BOLD}── Status ──${C_RESET}\n\n"
    printf "    Tunnel:  %b" "$(tunnel_state)"
    if [ "$BACKEND" = "systemd" ]; then
        printf "  ${C_DIM}(systemd: ${BACKEND_UNIT})${C_RESET}"
    else
        printf "  ${C_DIM}(wg-quick)${C_RESET}"
    fi
    printf "\n"
    printf "    Local:   ${C_CYAN}%s${C_RESET}\n" "$WG_ADDRESS"

    # ── Peers ──
    printf "\n  ${C_BOLD}── Peers ──${C_RESET}\n\n"
    printf "    ${C_BOLD}%-18s %-14s %-22s %-28s %s${C_RESET}\n" "NAME" "WG IP" "PUBLIC IP" "ROLE" "STATUS"
    printf "    ${C_DIM}──────────────────────────────────────────────────────────────────────────────────${C_RESET}\n"

    i=0
    while [ "$i" -lt "$PEER_COUNT" ]; do
        name=$(jq -r ".peers[$i].name" "$CONFIG_FILE")
        wg_ip=$(jq -r ".peers[$i].wg_ip" "$CONFIG_FILE")
        pub_ip=$(jq -r ".peers[$i].public_ip" "$CONFIG_FILE")
        role=$(jq -r ".peers[$i].role" "$CONFIG_FILE")

        status=$(check_peer "$wg_ip" "$name")

        if [ "$name" = "local" ]; then
            printf "    ${C_CYAN}%-18s${C_RESET} %-14s %-22s %-28s %b\n" "$name (you)" "$wg_ip" "$pub_ip" "$role" "$status"
        else
            printf "    %-18s %-14s %-22s %-28s %b\n" "$name" "$wg_ip" "$pub_ip" "$role" "$status"
        fi
        i=$((i + 1))
    done

    # ── Config ──
    printf "\n  ${C_BOLD}── Config ──${C_RESET}\n\n"
    printf "    File:     ${C_DIM}%s${C_RESET}\n" "$WG_CONF"
    printf "    Backend:  ${C_DIM}%s (%s)${C_RESET}\n" "$BACKEND" \
        "$([ "$BACKEND" = "systemd" ] && echo "$BACKEND_UNIT" || echo "$WG_CONF")"

    # ── Commands ──
    printf "\n  ${C_BOLD}── Commands ──${C_RESET}\n\n"
    printf "    ${C_GREEN}mesh up${C_RESET}         Start VPN tunnel\n"
    printf "    ${C_RED}mesh down${C_RESET}       Stop VPN tunnel\n"
    printf "    ${C_CYAN}mesh status${C_RESET}     Ping all peers (quick)\n"
    printf "    ${C_CYAN}mesh config${C_RESET}     Show wg0.conf\n"
    printf "    ${C_CYAN}mesh path${C_RESET}       Show config file path\n"
    printf "    ${C_CYAN}mesh peers${C_RESET}      Peer topology table\n"
    printf "\n"
}

# =============================================================================
# HELP
# =============================================================================

show_help() {
    printf "${C_BOLD}mesh - WireGuard Mesh VPN Manager${C_RESET}\n\n"

    printf "${C_BOLD}Usage:${C_RESET}\n"
    printf "  mesh              ${C_DIM}# Show dashboard${C_RESET}\n"
    printf "  mesh <command>    ${C_DIM}# Run command${C_RESET}\n"
    printf "  mesh --check      ${C_DIM}# Check dependencies${C_RESET}\n\n"

    printf "${C_BOLD}Commands:${C_RESET}\n"
    printf "  ${C_GREEN}up${C_RESET}          Start VPN tunnel\n"
    printf "  ${C_RED}down${C_RESET}        Stop VPN tunnel\n"
    printf "  ${C_CYAN}status${C_RESET}      Ping all peers (quick health check)\n"
    printf "  ${C_CYAN}config${C_RESET}      Show wg0.conf contents\n"
    printf "  ${C_CYAN}path${C_RESET}        Print config file path\n"
    printf "  ${C_CYAN}peers${C_RESET}       Peer topology table\n\n"

    printf "${C_BOLD}Config:${C_RESET} ${C_DIM}$CONFIG_FILE${C_RESET}\n"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    case "${1:-}" in
        --check|check)
            check_deps
            exit $?
            ;;
        --help|-h|help)
            show_help
            exit 0
            ;;
    esac

    load_config
    detect_backend

    case "${1:-}" in
        up)      cmd_up ;;
        down)    cmd_down ;;
        status)  cmd_status ;;
        config)  cmd_config ;;
        path)    cmd_path ;;
        peers)   cmd_peers ;;
        "")      cmd_dashboard ;;
        *)
            printf "$FAIL ${C_RED}Unknown command: $1${C_RESET}\n\n"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
