#!/bin/bash
# cloud-connect.sh - Cloud Connect: Unified Dashboard
# Combines: Git Manager + FUSE Mounts + Rclone Sync + Servers + Webservers
# Author: Diego Nepomuceno Marcos
# Version: 2.0
#
# Usage:
#   ./cloud-connect.sh              # Launch dashboard
#   ./cloud-connect.sh <command>    # CLI mode
#   ./cloud-connect.sh --help       # Show help

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/cloud-connect.json"

# Sync state files
SYNC_JOBS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/rclone_manager/sync_jobs.json"
SYNC_RULES_FILE=""  # set from config
SYNC_LOG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rclone_manager/logs"

# =============================================================================
# 256-COLOR SCHEME
# =============================================================================

if [ -t 1 ]; then
    RST="\033[0m"
    BLD="\033[1m"
    DIM="\033[2m"
    # Section accent colors (256-color)
    C_HEAD="\033[38;5;255m"     # header: bright white
    C_MESH="\033[38;5;44m"      # A) MESH: teal
    C_GIT="\033[38;5;77m"       # B) GIT: green
    C_DRIVE="\033[38;5;220m"    # C) DRIVES: gold
    C_SYNC="\033[38;5;177m"     # D) SYNC: magenta
    C_SRVR="\033[38;5;69m"      # E) SERVERS: blue
    C_WEB="\033[38;5;208m"      # F) WEBSERVER: orange
    # Status colors
    C_OK="\033[38;5;77m"        # green
    C_WARN="\033[38;5;220m"     # yellow
    C_ERR="\033[38;5;196m"      # red
    C_INFO="\033[38;5;75m"      # cyan
    C_DIM="\033[38;5;240m"      # gray
    C_ALERT="\033[38;5;203m"    # alert red
    # Gauge gradient
    C_G1="\033[38;5;34m"        # 0-25%
    C_G2="\033[38;5;76m"        # 25-50%
    C_G3="\033[38;5;220m"       # 50-75%
    C_G4="\033[38;5;196m"       # 75-100%
    # Sparkline
    C_SP="\033[38;5;44m"
    # Background for header
    BG_HEAD="\033[48;5;235m"
else
    RST='' BLD='' DIM=''
    C_HEAD='' C_MESH='' C_GIT='' C_DRIVE='' C_SYNC='' C_SRVR='' C_WEB=''
    C_OK='' C_WARN='' C_ERR='' C_INFO='' C_DIM='' C_ALERT=''
    C_G1='' C_G2='' C_G3='' C_G4='' C_SP='' BG_HEAD=''
fi

# =============================================================================
# SYMBOLS
# =============================================================================

S_RUN="◉"
S_STOP="○"
S_OK="✓"
S_FAIL="✗"
S_WARN="⚠"
S_DOT="●"
S_PLAY="▶"
S_ARR="→"
S_ARBI="↔"
S_ARRL="←"

# =============================================================================
# LOAD CONFIG
# =============================================================================

_jq() { jq "$@" "$CONFIG_FILE" 2>/dev/null; }

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        printf "${C_ERR}Config not found: %s${RST}\n" "$CONFIG_FILE" >&2
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf "${C_ERR}jq is required${RST}\n" >&2
        exit 1
    fi

    GIT_WORKDIR=$(_jq -r '.settings.git_workdir')
    MOUNT_DIR=$(_jq -r '.settings.mount_dir')
    SYNC_DIR=$(_jq -r '.settings.sync_dir')
    RCLONE_OPTS=$(_jq -r '.settings.rclone_opts')
    RCLONE_SYNC_OPTS=$(_jq -r '.settings.rclone_sync_opts')
    MERGE_STRATEGY=$(_jq -r '.settings.merge_strategy')
    LOG_FILE_NAME=$(_jq -r '.settings.log_file')
    LOG_FILE="$MOUNT_DIR/$LOG_FILE_NAME"

    SYNC_RULES_FILE="$SYNC_DIR/sync.json"

    # Ensure dirs
    mkdir -p "$MOUNT_DIR" "$SYNC_DIR" "$SYNC_LOG_DIR" "$(dirname "$SYNC_JOBS_FILE")"
    [ ! -f "$SYNC_JOBS_FILE" ] && echo "[]" > "$SYNC_JOBS_FILE"
    [ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

    # Rotate log if > 1MB
    if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        touch "$LOG_FILE"
    fi
}

log_msg() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"; }
log_err() { printf "[%s] ERROR: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"; }

# =============================================================================
# GAUGE BAR RENDERING
# =============================================================================

# Smooth gauge: gauge_bar <current> <max> <width> <label>
# Uses Unicode fractional blocks: ▏▎▍▌▋▊▉█
gauge_bar() {
    local cur=$1 max=$2 width=${3:-16} label=${4:-""}
    local blocks="▏▎▍▌▋▊▉█"
    local pct=0
    [ "$max" -gt 0 ] 2>/dev/null && pct=$(( cur * 100 / max ))
    [ "$pct" -gt 100 ] && pct=100

    # Pick color by percentage
    local gc="$C_G1"
    [ "$pct" -ge 25 ] && gc="$C_G2"
    [ "$pct" -ge 50 ] && gc="$C_G3"
    [ "$pct" -ge 75 ] && gc="$C_G4"

    local filled_8ths=$(( pct * width * 8 / 100 ))
    local full=$(( filled_8ths / 8 ))
    local frac=$(( filled_8ths % 8 ))
    local empty=$(( width - full - (frac > 0 ? 1 : 0) ))

    local bar=""
    local i=0
    while [ "$i" -lt "$full" ]; do bar="${bar}█"; i=$((i+1)); done
    if [ "$frac" -gt 0 ]; then
        # Extract fractional character (UTF-8 multibyte)
        local fc
        fc=$(printf '%s' "$blocks" | awk -v n="$frac" 'BEGIN{FS=""}{print $n}')
        bar="${bar}${fc}"
    fi
    i=0
    while [ "$i" -lt "$empty" ]; do bar="${bar}░"; i=$((i+1)); done

    if [ -n "$label" ]; then
        printf "%b%s%b %3d%% %s" "$gc" "$bar" "$RST" "$pct" "$label"
    else
        printf "%b%s%b %3d%%" "$gc" "$bar" "$RST" "$pct"
    fi
}

# =============================================================================
# SPARKLINE
# =============================================================================

# sparkline <space-separated-values> (0-8 scale)
sparkline() {
    local chars="▁▂▃▄▅▆▇█"
    local vals="$1"
    local max=1
    for v in $vals; do [ "$v" -gt "$max" ] 2>/dev/null && max=$v; done
    local out=""
    for v in $vals; do
        local idx=1
        [ "$max" -gt 0 ] 2>/dev/null && idx=$(( v * 7 / max + 1 ))
        [ "$idx" -gt 8 ] && idx=8
        [ "$idx" -lt 1 ] && idx=1
        local c
        c=$(printf '%s' "$chars" | awk -v n="$idx" 'BEGIN{FS=""}{print $n}')
        out="${out}${c}"
    done
    printf "%b%s%b" "$C_SP" "$out" "$RST"
}

# =============================================================================
# UTILITY: is_mounted, rclone_remote_exists
# =============================================================================

is_mounted() { mountpoint -q "$1" 2>/dev/null; }

rclone_remote_exists() {
    rclone listremotes 2>/dev/null | grep -q "^${1}:$"
}

# =============================================================================
# A) MESH - Data Collection
# =============================================================================

# Get VM SSH reachability (fast ssh check)
vm_is_reachable() {
    local alias=$1
    timeout 3 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes "$alias" exit 2>/dev/null
}

# Get phone status via KDE Connect
phone_status() {
    local dev_id
    dev_id=$(_jq -r '.mesh.phone.device_id')
    [ -z "$dev_id" ] || [ "$dev_id" = "null" ] && echo "unconfigured" && return

    if ! command -v kdeconnect-cli >/dev/null 2>&1; then
        echo "no-kdeconnect"
        return
    fi

    if kdeconnect-cli -a --id-only 2>/dev/null | grep -q "$dev_id"; then
        if command -v qdbus >/dev/null 2>&1; then
            local mounted
            mounted=$(qdbus org.kde.kdeconnect "/modules/kdeconnect/devices/$dev_id/sftp" \
                org.kde.kdeconnect.device.sftp.isMounted 2>/dev/null || echo "false")
            [ "$mounted" = "true" ] && echo "mounted" || echo "reachable"
        else
            echo "reachable"
        fi
    else
        echo "offline"
    fi
}

phone_battery() {
    local dev_id
    dev_id=$(_jq -r '.mesh.phone.device_id')
    [ -z "$dev_id" ] || [ "$dev_id" = "null" ] && echo "?" && return
    if command -v qdbus >/dev/null 2>&1; then
        qdbus org.kde.kdeconnect "/modules/kdeconnect/devices/$dev_id/battery" \
            org.kde.kdeconnect.device.battery.charge 2>/dev/null || echo "?"
    else
        echo "?"
    fi
}

# =============================================================================
# A) MESH - Rendering
# =============================================================================

render_mesh() {
    local vm_count
    vm_count=$(_jq '.mesh.vms | length')

    # Topology line
    printf "  "
    local i=0
    while [ "$i" -lt "$vm_count" ]; do
        local wg_ip alias_name
        wg_ip=$(_jq -r ".mesh.vms[$i].wg_ip")
        alias_name=$(_jq -r ".mesh.vms[$i].alias")
        if [ "$i" -gt 0 ]; then printf " ${C_DIM}────${RST} "; fi
        printf "%b%s%b" "$C_MESH" "$wg_ip" "$RST"
        i=$((i+1))
    done
    printf "\n  "
    i=0
    while [ "$i" -lt "$vm_count" ]; do
        local alias_name
        alias_name=$(_jq -r ".mesh.vms[$i].alias")
        if [ "$i" -gt 0 ]; then printf "       "; fi
        printf "%-13s" "$alias_name"
        i=$((i+1))
    done
    printf "\n\n"

    # VM Table header
    printf "  ${BLD}%-17s %-7s %-12s %-18s %5s %4s %4s %5s  Services${RST}\n" \
        "VM" "State" "WG IP" "Public IP" "Up" "CPU" "RAM" "Svcs"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    # VM rows
    i=0
    while [ "$i" -lt "$vm_count" ]; do
        local name alias_name wg_ip pub_ip
        name=$(_jq -r ".mesh.vms[$i].name")
        alias_name=$(_jq -r ".mesh.vms[$i].alias")
        wg_ip=$(_jq -r ".mesh.vms[$i].wg_ip")
        pub_ip=$(_jq -r ".mesh.vms[$i].public_ip")

        # Collect service names
        local svc_total
        svc_total=$(_jq ".mesh.vms[$i].services | length")

        # Check reachability via SSH alias — single SSH call for all metrics
        local state state_sym state_color up_str cpu_str ram_str svc_run
        if vm_is_reachable "$alias_name" 2>/dev/null; then
            state="RUN"
            state_sym="$S_RUN"
            state_color="$C_OK"
            # Single SSH call: uptime_seconds|cpu_pct|ram_pct
            local metrics
            metrics=$(ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes "$alias_name" \
                'printf "%s|" "$(awk "{print int(\$1)}" /proc/uptime 2>/dev/null || echo 0)"; \
                 printf "%s|" "$(top -bn1 2>/dev/null | awk "/Cpu/{printf \"%d\", 100-\$8}" || echo "?")"; \
                 free 2>/dev/null | awk "/Mem:/{printf \"%d\", \$3/\$2*100}" || echo "?"' 2>/dev/null || echo "0|?|?")
            local up_secs cpu_pct ram_pct
            up_secs=$(echo "$metrics" | cut -d'|' -f1)
            cpu_pct=$(echo "$metrics" | cut -d'|' -f2)
            ram_pct=$(echo "$metrics" | cut -d'|' -f3)
            # Format uptime
            if [ "$up_secs" -gt 86400 ] 2>/dev/null; then
                up_str="$((up_secs / 86400))d"
            elif [ "$up_secs" -gt 3600 ] 2>/dev/null; then
                up_str="$((up_secs / 3600))h"
            elif [ "$up_secs" -gt 0 ] 2>/dev/null; then
                up_str="$((up_secs / 60))m"
            else
                up_str="?"
            fi
            cpu_str="${cpu_pct}%"
            ram_str="${ram_pct}%"
            svc_run="$svc_total"
        else
            state="STOP"
            state_sym="$S_STOP"
            state_color="$C_DIM"
            up_str="—"
            cpu_str="—"
            ram_str="—"
            svc_run="0"
        fi

        printf "  %-17s %b%s %-4s%b %-12s %-18s %5s %4s %4s %s/%s  " \
            "$name" "$state_color" "$state_sym" "$state" "$RST" \
            "$wg_ip" "$pub_ip" "$up_str" "$cpu_str" "$ram_str" "$svc_run" "$svc_total"

        # Services inline
        local s=0
        while [ "$s" -lt "$svc_total" ]; do
            local svc_name
            svc_name=$(_jq -r ".mesh.vms[$i].services[$s]")
            local short="${svc_name:0:6}"
            if [ "$state" = "RUN" ]; then
                printf "%b%s%b%s " "$C_OK" "$S_RUN" "$RST" "$short"
            else
                printf "%b%s%b%s " "$C_DIM" "$S_STOP" "$RST" "$short"
            fi
            s=$((s+1))
        done
        printf "\n"
        i=$((i+1))
    done

    # LOCAL PC
    printf "\n  ${BLD}%-17s %-16s %-17s %5s %4s %-12s  Disk${RST}\n" \
        "LOCAL" "OS" "Kernel" "Up" "CPU" "RAM"
    printf "  ${C_DIM}"
    w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local hostname_str os_str kernel_str up_local cpu_local ram_used_g ram_total_g disk_used disk_total
    hostname_str="${HM_PROFILE:-$(hostname 2>/dev/null || echo 'unknown')}"
    os_str=$(grep -oP '(?<=PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null | head -c16 || echo "Linux")
    kernel_str=$(uname -r | head -c17)
    # Uptime from /proc/uptime (seconds)
    local up_secs_local
    up_secs_local=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
    if [ "$up_secs_local" -gt 86400 ] 2>/dev/null; then
        up_local="$((up_secs_local / 86400))d"
    elif [ "$up_secs_local" -gt 3600 ] 2>/dev/null; then
        up_local="$((up_secs_local / 3600))h"
    else
        up_local="$((up_secs_local / 60))m"
    fi
    cpu_local=$(top -bn1 2>/dev/null | grep 'Cpu' | awk '{printf "%d%%", 100-$8}' || echo "?")
    ram_used_g=$(free -g 2>/dev/null | awk '/Mem:/{print $3}' || echo 0)
    ram_total_g=$(free -g 2>/dev/null | awk '/Mem:/{print $2}' || echo 1)
    disk_used=$(df -BG /home 2>/dev/null | awk 'NR==2{gsub("G","",$3); print $3}' || echo 0)
    disk_total=$(df -BG /home 2>/dev/null | awk 'NR==2{gsub("G","",$2); print $2}' || echo 1)

    printf "  %-17s %-16s %-17s %5s %4s %dG/%dG  " \
        "$hostname_str" "$os_str" "$kernel_str" "$up_local" "$cpu_local" \
        "$ram_used_g" "$ram_total_g"
    gauge_bar "$disk_used" "$disk_total" 18 "${disk_used}G/${disk_total}G"
    printf "\n"

    # PHONE
    local phone_name phone_stat phone_bat
    phone_name=$(_jq -r '.mesh.phone.name // "none"')
    if [ "$phone_name" != "none" ] && [ "$phone_name" != "null" ]; then
        printf "\n  ${BLD}%-17s %-16s %-10s %-14s Connection${RST}\n" \
            "PHONE" "Device" "Battery" "Storage"
        printf "  ${C_DIM}"
        w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
        printf "${RST}\n"

        phone_stat=$(phone_status)
        phone_bat=$(phone_battery)
        local bat_str="?"
        if [ "$phone_bat" != "?" ] && [ "$phone_bat" -gt 0 ] 2>/dev/null; then
            bat_str=$(gauge_bar "$phone_bat" 100 8 "${phone_bat}%")
        fi

        local conn_str
        case "$phone_stat" in
            mounted)    conn_str="${C_OK}${S_RUN} KDE Connect${RST}" ;;
            reachable)  conn_str="${C_WARN}${S_STOP} reachable${RST}" ;;
            offline)    conn_str="${C_DIM}${S_STOP} offline${RST}" ;;
            *)          conn_str="${C_DIM}${S_STOP} $phone_stat${RST}" ;;
        esac

        printf "  %-17s %-16s %-10b %-14s %b\n" \
            "$phone_name" "Galaxy S21" "$bat_str" "?/128 GB" "$conn_str"
    fi
}

# =============================================================================
# B) GIT - Data Collection & Rendering
# =============================================================================

git_check_cloned()     { [ -d "$1/.git" ]; }
git_dirty_count()      { git -C "$1" status --porcelain 2>/dev/null | wc -l | tr -d ' '; }
git_stash_count()      { git -C "$1" stash list 2>/dev/null | wc -l | tr -d ' '; }
git_unpulled()         { git -C "$1" rev-parse @{u} >/dev/null 2>&1 && git -C "$1" log ..@{u} --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "?"; }
git_unpushed()         { git -C "$1" rev-parse @{u} >/dev/null 2>&1 && git -C "$1" log @{u}.. --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "?"; }
git_branch()           { git -C "$1" branch --show-current 2>/dev/null || echo "?"; }
git_branch_count()     { git -C "$1" branch --list 2>/dev/null | wc -l | tr -d ' '; }
git_tag_count()        { git -C "$1" tag -l 2>/dev/null | wc -l | tr -d ' '; }
git_remote_url()       { git -C "$1" remote get-url origin 2>/dev/null || echo "none"; }
git_auth_type()        {
    local url; url=$(git -C "$1" remote get-url origin 2>/dev/null || echo "")
    case "$url" in
        git@*|ssh://*)   echo "SSH" ;;
        https://*|http://*) echo "HTTP" ;;
        "")              echo "—" ;;
        *)               echo "?" ;;
    esac
}
git_remote_name()      { git -C "$1" remote 2>/dev/null | head -1 || echo "none"; }
git_tracking_branch()  { git -C "$1" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "none"; }
git_has_submodules()   { [ -f "$1/.gitmodules" ] && echo "yes" || echo "no"; }
git_hook_count()       { ls "$1/.git/hooks/"* 2>/dev/null | grep -cv '\.sample$' || echo 0; }
git_last_fetch_age()   {
    local fetch_head="$1/.git/FETCH_HEAD"
    [ ! -f "$fetch_head" ] && echo "never" && return
    local ts; ts=$(stat -c %Y "$fetch_head" 2>/dev/null || stat -f %m "$fetch_head" 2>/dev/null || echo 0)
    local now; now=$(date +%s)
    local diff=$(( now - ts ))
    if [ "$diff" -lt 60 ]; then echo "${diff}s"
    elif [ "$diff" -lt 3600 ]; then echo "$(( diff / 60 ))m"
    elif [ "$diff" -lt 86400 ]; then echo "$(( diff / 3600 ))h"
    else echo "$(( diff / 86400 ))d"
    fi
}
git_last_commit_msg()  { git -C "$1" log -1 --pretty=format:'%s' 2>/dev/null | head -c20; }

git_last_commit_age() {
    local ts
    ts=$(git -C "$1" log -1 --pretty=format:'%ct' 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    local diff=$(( now - ts ))
    if [ "$diff" -lt 3600 ]; then
        echo "$(( diff / 60 ))m"
    elif [ "$diff" -lt 86400 ]; then
        echo "$(( diff / 3600 ))h"
    else
        echo "$(( diff / 86400 ))d"
    fi
}

git_ci_status() {
    local dir=$1
    [ ! -d "$dir/.git" ] && echo "-" && return
    command -v gh >/dev/null 2>&1 || { echo "?"; return; }
    local url
    url=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
    [ -z "$url" ] && echo "?" && return
    local repo
    repo=$(echo "$url" | sed 's/.*github.com[:/]\([^/]*\/[^.]*\).*/\1/')
    local conclusion
    conclusion=$(gh run list --repo "$repo" --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null || echo "")
    case "$conclusion" in
        success)   echo "$S_OK" ;;
        failure)   echo "$S_FAIL" ;;
        cancelled) echo "$S_STOP" ;;
        "")        echo "-" ;;
        *)         echo "?" ;;
    esac
}

git_repo_size() {
    local dir=$1
    du -sm "$dir" 2>/dev/null | awk '{printf "%dM", $1}' || echo "?"
}

git_activity_sparkline() {
    local dir=$1
    # Commits per week for last 8 weeks
    local vals=""
    local w=7
    while [ "$w" -ge 0 ]; do
        local since="$((w+1)) weeks ago"
        local until="$w weeks ago"
        local cnt
        cnt=$(git -C "$dir" log --oneline --since="$since" --until="$until" 2>/dev/null | wc -l | tr -d ' ')
        vals="$vals $cnt"
        w=$((w-1))
    done
    sparkline "$vals"
}

render_git() {
    # Row 1: main info — Row 2: remote URL + extra details (indented)
    # Cols: Repo=20 Branch=10 Auth=5 Local=13 Remote=13 CI=3 Stsh=3 Br=3 Age=4 Size=5 Spark=9 Commit=rest
    printf "  ${BLD}%-20s %-10s %-5s %-13s %-13s %-3s %-3s %-3s %-4s %-5s %-9s %s${RST}\n" \
        "Repo" "Branch" "Auth" "Local" "Remote" "CI" "Sth" "Br" "Age" "Size" "Activity" "Last Commit"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local repos
    repos=$(_jq -r '(.git.public_repos // {} | keys[]) , (.git.private_repos // {} | keys[])')

    local not_cloned=""
    local dirty_total=0 pull_total=0 push_total=0 ssh_total=0 http_total=0

    while IFS= read -r repo_name; do
        [ -z "$repo_name" ] && continue
        local dir="$GIT_WORKDIR/$repo_name"

        if ! git_check_cloned "$dir"; then
            not_cloned="$not_cloned $repo_name"
            continue
        fi

        local branch dirty stash pull push ci age size commit_msg
        local auth branches remote_url tracking last_fetch tags submods
        branch=$(git_branch "$dir")
        dirty=$(git_dirty_count "$dir")
        stash=$(git_stash_count "$dir")
        pull=$(git_unpulled "$dir")
        push=$(git_unpushed "$dir")
        ci=$(git_ci_status "$dir")
        age=$(git_last_commit_age "$dir")
        size=$(git_repo_size "$dir")
        commit_msg=$(git_last_commit_msg "$dir")
        auth=$(git_auth_type "$dir")
        branches=$(git_branch_count "$dir")
        remote_url=$(git_remote_url "$dir")
        tracking=$(git_tracking_branch "$dir")
        last_fetch=$(git_last_fetch_age "$dir")
        tags=$(git_tag_count "$dir")
        submods=$(git_has_submodules "$dir")

        # Accumulate totals
        [ "$dirty" -gt 0 ] 2>/dev/null && dirty_total=$((dirty_total + 1))
        [ "$pull" -gt 0 ] 2>/dev/null && pull_total=$((pull_total + pull))
        [ "$push" -gt 0 ] 2>/dev/null && push_total=$((push_total + push))
        [ "$auth" = "SSH" ] && ssh_total=$((ssh_total + 1))
        [ "$auth" = "HTTP" ] && http_total=$((http_total + 1))

        # AUTH — pad then color
        local auth_color
        case "$auth" in
            SSH)  auth_color="$C_OK" ;;
            HTTP) auth_color="$C_WARN" ;;
            *)    auth_color="$C_DIM" ;;
        esac
        local auth_padded; auth_padded=$(printf "%-5s" "$auth")
        local auth_f="${auth_color}${auth_padded}${RST}"

        # LOCAL STATUS — pad then color
        local local_plain local_color
        if [ "$dirty" -gt 0 ] 2>/dev/null; then
            local_plain="Dirty [$dirty]"; local_color="$C_WARN"
        elif [ "$push" = "?" ]; then
            local_plain="No Remote"; local_color="$C_ERR"
        elif [ "$push" -gt 0 ] 2>/dev/null; then
            local_plain="$push Unpushed"; local_color="$C_WARN"
        else
            local_plain="OK"; local_color="$C_OK"
        fi
        local local_padded; local_padded=$(printf "%-13s" "$local_plain")
        local local_f="${local_color}${local_padded}${RST}"

        # REMOTE STATUS — pad then color
        local remote_plain remote_color
        if [ "$pull" = "?" ]; then
            remote_plain="Not Checked"; remote_color="$C_DIM"
        elif [ "$pull" -gt 0 ] 2>/dev/null; then
            remote_plain="$pull To Pull"; remote_color="$C_INFO"
        else
            remote_plain="Up to Date"; remote_color="$C_OK"
        fi
        local remote_padded; remote_padded=$(printf "%-13s" "$remote_plain")
        local remote_f="${remote_color}${remote_padded}${RST}"

        # Stash — pad then color
        local stash_plain stash_color
        if [ "$stash" -gt 0 ] 2>/dev/null; then
            stash_plain="$stash"; stash_color="$C_WARN"
        else
            stash_plain="·"; stash_color="$C_DIM"
        fi
        local stash_padded; stash_padded=$(printf "%-3s" "$stash_plain")
        local stash_f="${stash_color}${stash_padded}${RST}"

        # Branches — pad then color
        local br_padded; br_padded=$(printf "%-3s" "$branches")
        local br_f
        [ "$branches" -gt 1 ] 2>/dev/null && br_f="${C_INFO}${br_padded}${RST}" || br_f="${C_DIM}${br_padded}${RST}"

        # CI — pad then color
        local ci_plain ci_color
        case "$ci" in
            "$S_OK")   ci_plain="${S_OK}"; ci_color="$C_OK" ;;
            "$S_FAIL") ci_plain="${S_FAIL}"; ci_color="$C_ERR" ;;
            "-")       ci_plain="—"; ci_color="$C_DIM" ;;
            *)         ci_plain="?"; ci_color="$C_DIM" ;;
        esac
        local ci_padded; ci_padded=$(printf "%-3s" "$ci_plain")
        local ci_f="${ci_color}${ci_padded}${RST}"

        # Activity sparkline
        local spark
        spark=$(git_activity_sparkline "$dir")

        # Row 1: main info
        printf "  %-20s %-10s %b%b%b%b%b%b%-4s %-5s %b  %s\n" \
            "$repo_name" "$branch" \
            "$auth_f" "$local_f" "$remote_f" "$ci_f" "$stash_f" "$br_f" \
            "$age" "$size" "$spark" "$commit_msg"

        # Row 2: remote URL + tracking + last fetch + tags + submodules
        local url_short; url_short=$(echo "$remote_url" | sed 's|git@github.com:|gh:|;s|https://github.com/|gh:|;s|\.git$||')
        local extra=""
        [ "$tags" -gt 0 ] 2>/dev/null && extra="${extra} ${C_DIM}tags:${RST}${C_INFO}${tags}${RST}"
        [ "$submods" = "yes" ] && extra="${extra} ${C_WARN}submodules${RST}"
        printf "  ${C_DIM}%-20s %s  track:%-20s fetch:%s%b${RST}\n" \
            "" "$url_short" "$tracking" "$last_fetch" "$extra"
    done <<< "$repos"

    # Summary totals
    local total_repos; total_repos=$(echo "$repos" | grep -c '.' || echo 0)
    local cloned; cloned=$((total_repos - $(echo "$not_cloned" | wc -w)))
    printf "\n  ${C_DIM}Total: %s repos | %s cloned | " "$total_repos" "$cloned"
    printf "auth: ${RST}${C_OK}%s SSH${RST}${C_DIM} / ${RST}${C_WARN}%s HTTP${RST}${C_DIM} | " "$ssh_total" "$http_total"
    [ "$dirty_total" -gt 0 ] && printf "${C_WARN}%s dirty${RST}${C_DIM}" "$dirty_total" || printf "0 dirty"
    printf " | "
    [ "$pull_total" -gt 0 ] && printf "${C_INFO}%s to pull${RST}${C_DIM}" "$pull_total" || printf "0 to pull"
    printf " | "
    [ "$push_total" -gt 0 ] && printf "${C_WARN}%s to push${RST}" "$push_total" || printf "0 to push"
    printf "${RST}\n"

    # Not cloned line
    if [ -n "$not_cloned" ]; then
        printf "  ${C_DIM}NOT CLONED %s${RST}\n" "$(echo "$not_cloned" | sed 's/ / · /g')"
    fi
}

# =============================================================================
# B) GIT - Actions
# =============================================================================

git_get_repos() { _jq -r '(.git.public_repos // {} | keys[]) , (.git.private_repos // {} | keys[])'; }
git_get_url() {
    local name=$1
    local url
    url=$(_jq -r ".git.public_repos.\"$name\" // .git.private_repos.\"$name\" // empty")
    echo "$url"
}

_git_auto_fix_errors() {
    local dir="$1" output="$2"
    # Filename too long: auto-enable longpaths
    if echo "$output" | grep -qi "filename too long\|file name too long"; then
        printf "    ${C_WARN}Auto-fix: enabling core.longpaths${RST}\n"
        git -C "$dir" config core.longpaths true
    fi
    # Symlink errors: auto-disable symlinks
    if echo "$output" | grep -qi "unable to create symlink\|symlink.*not supported"; then
        printf "    ${C_WARN}Auto-fix: disabling core.symlinks${RST}\n"
        git -C "$dir" config core.symlinks false
    fi
    # Failed merge: abort
    if [ -f "$dir/.git/MERGE_HEAD" ]; then
        printf "    ${C_WARN}Auto-fix: aborting failed merge${RST}\n"
        git -C "$dir" merge --abort 2>/dev/null || true
    fi
}

git_cmd_sync() {
    printf "\n${BLD}=== Syncing All Repos ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        if [ ! -d "$dir/.git" ]; then
            printf "${C_INFO}${S_ARR}${RST} Cloning %s...\n" "$name"
            local url; url=$(git_get_url "$name")
            [ -n "$url" ] && git clone "$url" "$dir" 2>&1 || printf "${C_ERR}Clone failed${RST}\n"
            continue
        fi
        printf "${C_INFO}${S_ARR}${RST} Syncing ${BLD}%s${RST}...\n" "$name"
        # Auto-commit before pull
        if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
            git -C "$dir" add -A && git -C "$dir" commit -q -m "sync: auto-commit" 2>/dev/null || true
        fi
        git -C "$dir" fetch -q 2>/dev/null || true
        local pull_out
        pull_out=$(git -C "$dir" pull --no-rebase --strategy-option="$MERGE_STRATEGY" -q 2>&1) || {
            printf "    ${C_ERR}Pull error${RST}\n"
            _git_auto_fix_errors "$dir" "$pull_out"
        }
        git -C "$dir" push -q 2>&1 || true
        printf "${C_OK}${S_OK}${RST} Done\n"
    done <<< "$(git_get_repos)"
}

git_cmd_pull() {
    printf "\n${BLD}=== Pulling All Repos ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}${S_ARR}${RST} Pulling %s..." "$name"
        # Auto-commit before pull (like gcl.sh) instead of just stashing
        if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
            printf " ${C_WARN}[auto-commit]${RST}"
            git -C "$dir" add -A && git -C "$dir" commit -q -m "auto-commit before pull" 2>/dev/null || true
        fi
        local pull_out
        pull_out=$(git -C "$dir" pull --no-rebase --strategy-option="$MERGE_STRATEGY" -q 2>&1)
        if [ $? -eq 0 ]; then
            printf " ${C_OK}${S_OK}${RST}\n"
        else
            printf " ${C_ERR}${S_FAIL}${RST}\n"
            _git_auto_fix_errors "$dir" "$pull_out"
        fi
    done <<< "$(git_get_repos)"
}

git_cmd_commit() {
    printf "\n${BLD}=== Committing All Repos ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
            printf "${C_INFO}${S_ARR}${RST} Committing %s..." "$name"
            git -C "$dir" add -A && git -C "$dir" commit -m "auto-commit" 2>/dev/null && \
                printf " ${C_OK}${S_OK}${RST}\n" || printf " ${C_WARN}nothing${RST}\n"
        fi
    done <<< "$(git_get_repos)"
}

git_cmd_push() {
    printf "\n${BLD}=== Pushing All Repos ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}${S_ARR}${RST} Pushing %s..." "$name"
        git -C "$dir" push -q 2>&1 && printf " ${C_OK}${S_OK}${RST}\n" || printf " ${C_ERR}${S_FAIL}${RST}\n"
    done <<< "$(git_get_repos)"
}

git_cmd_fetch() {
    printf "\n${BLD}=== Fetching All Repos (parallel) ===${RST}\n\n"
    local pids="" names=""
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}${S_ARR}${RST} Fetching %s...\n" "$name"
        git -C "$dir" fetch -q 2>/dev/null &
        pids="$pids $!"
        names="$names $name"
    done <<< "$(git_get_repos)"

    # Wait for all fetches and report results
    local i=1
    for pid in $pids; do
        local rname
        rname=$(echo "$names" | cut -d' ' -f$((i+1)))
        if wait "$pid" 2>/dev/null; then
            printf "  ${C_OK}${S_OK}${RST} %s\n" "$rname"
        else
            printf "  ${C_ERR}${S_FAIL}${RST} %s\n" "$rname"
        fi
        i=$((i+1))
    done
    printf "\n${C_OK}${S_OK}${RST} All fetches complete\n"
}

git_cmd_fetch_status() {
    printf "\n${BLD}=== Fetch + Status ===${RST}\n\n"
    # Parallel fetch
    local pids=""
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        git -C "$dir" fetch -q 2>/dev/null &
        pids="$pids $!"
    done <<< "$(git_get_repos)"

    printf "${C_INFO}Fetching %d repos...${RST}" "$(echo "$pids" | wc -w)"
    for pid in $pids; do wait "$pid" 2>/dev/null; done
    printf " ${C_OK}done${RST}\n\n"

    # Render with accurate pull counts
    render_git
}

git_cmd_untracked() {
    printf "\n${BLD}=== Untracked Files ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local files
        files=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)
        if [ -n "$files" ]; then
            printf "${C_INFO}%s:${RST}\n" "$name"
            echo "$files" | while read -r f; do printf "  ${C_WARN}+ %s${RST}\n" "$f"; done
            echo ""
        fi
    done <<< "$(git_get_repos)"
}

git_cmd_unstaged() {
    printf "\n${BLD}=== Unstaged Changes ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local files
        files=$(git -C "$dir" diff --name-only 2>/dev/null)
        if [ -n "$files" ]; then
            printf "${C_INFO}%s:${RST}\n" "$name"
            echo "$files" | while read -r f; do printf "  ${C_WARN}M %s${RST}\n" "$f"; done
            echo ""
        fi
    done <<< "$(git_get_repos)"
}

git_cmd_ignored() {
    printf "\n${BLD}=== Ignored Files ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local cnt
        cnt=$(git -C "$dir" ls-files --others --ignored --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        [ "$cnt" -gt 0 ] && printf "${C_INFO}%s:${RST} ${C_DIM}%s files${RST}\n" "$name" "$cnt"
    done <<< "$(git_get_repos)"
}

git_cmd_clone_menu() {
    local repos uncloned_arr=()
    repos=$(git_get_repos)
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        [ ! -d "$GIT_WORKDIR/$name/.git" ] && uncloned_arr+=("$name")
    done <<< "$repos"

    if [ "${#uncloned_arr[@]}" -eq 0 ]; then
        printf "${C_OK}All repos cloned.${RST}\n"
        return
    fi

    # Selection state: 0=deselected, 1=selected
    local count=${#uncloned_arr[@]}
    local selected=()
    local i
    for (( i=0; i<count; i++ )); do selected+=("0"); done

    while true; do
        printf "\n${BLD}━━━ Clone Menu (toggle with number, Enter to clone) ━━━${RST}\n\n"
        for (( i=0; i<count; i++ )); do
            local marker="[ ]"
            [ "${selected[$i]}" = "1" ] && marker="${C_OK}[x]${RST}"
            printf "  %b %s${RST}  %s\n" "$marker" "${C_INFO}$((i+1))${RST})" "${uncloned_arr[$i]}"
        done

        printf "\n  ${C_INFO}a${RST}) Select all  ${C_INFO}n${RST}) Select none  ${C_DIM}0${RST}) Cancel  ${C_OK}Enter${RST}) Clone selected\n"
        printf "${BLD}Choice:${RST} "
        read -r choice

        case "$choice" in
            0) return ;;
            a|A) for (( i=0; i<count; i++ )); do selected[$i]="1"; done ;;
            n|N) for (( i=0; i<count; i++ )); do selected[$i]="0"; done ;;
            "")
                # Clone all selected
                local any=false
                for (( i=0; i<count; i++ )); do
                    if [ "${selected[$i]}" = "1" ]; then
                        any=true
                        local url; url=$(git_get_url "${uncloned_arr[$i]}")
                        printf "${C_INFO}${S_ARR}${RST} Cloning %s...\n" "${uncloned_arr[$i]}"
                        git clone "$url" "$GIT_WORKDIR/${uncloned_arr[$i]}" 2>&1 || true
                    fi
                done
                [ "$any" = "false" ] && printf "${C_WARN}Nothing selected${RST}\n"
                return
                ;;
            *)
                # Toggle number
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                    local idx=$((choice-1))
                    if [ "${selected[$idx]}" = "0" ]; then
                        selected[$idx]="1"
                    else
                        selected[$idx]="0"
                    fi
                else
                    printf "${C_ERR}Invalid choice${RST}\n"
                fi
                ;;
        esac
    done
}

git_cmd_dirty() {
    printf "\n${BLD}=== Repos Needing Attention ===${RST}\n\n"
    printf "  ${BLD}%-17s %-9s %5s %4s %4s  Issue${RST}\n" "Repo" "Branch" "Dirty" "Pull" "Push"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 80 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local found=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue

        local dirty pull push issues=""
        dirty=$(git_dirty_count "$dir")
        pull=$(git_unpulled "$dir")
        push=$(git_unpushed "$dir")

        [ "$dirty" -gt 0 ] 2>/dev/null && issues="${issues}${C_WARN}dirty${RST} "
        [ "$pull" != "?" ] && [ "$pull" -gt 0 ] 2>/dev/null && issues="${issues}${C_INFO}behind${RST} "
        [ "$push" != "?" ] && [ "$push" -gt 0 ] 2>/dev/null && issues="${issues}${C_WARN}ahead${RST} "

        [ -z "$issues" ] && continue

        found=1
        local branch; branch=$(git_branch "$dir")
        printf "  %-17s %-9s %5s %4s %4s  %b\n" \
            "$name" "$branch" "$dirty" "$pull" "$push" "$issues"
    done <<< "$(git_get_repos)"

    [ "$found" -eq 0 ] && printf "  ${C_OK}${S_OK} All repos clean${RST}\n"
}

git_toggle_merge() {
    if [ "$MERGE_STRATEGY" = "theirs" ]; then
        MERGE_STRATEGY="ours"
        printf "${C_OK}${S_OK}${RST} Merge strategy: ${C_WARN}Local wins${RST}\n"
    else
        MERGE_STRATEGY="theirs"
        printf "${C_OK}${S_OK}${RST} Merge strategy: ${C_INFO}Server wins${RST}\n"
    fi
    local tmp; tmp=$(mktemp)
    jq --arg v "$MERGE_STRATEGY" '.settings.merge_strategy = $v' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
}

git_cmd_remotes() {
    printf "\n${BLD}=== Git Remotes (all repos) ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}%s:${RST}\n" "$name"
        git -C "$dir" remote -v 2>/dev/null | while read -r line; do
            printf "  ${C_DIM}%s${RST}\n" "$line"
        done
        echo ""
    done <<< "$(git_get_repos)"
}

git_cmd_branches() {
    printf "\n${BLD}=== Git Branches (all repos) ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local current; current=$(git_branch "$dir")
        local count; count=$(git_branch_count "$dir")
        printf "${C_INFO}%s${RST} (${C_DIM}%s branches, current: ${RST}${C_OK}%s${RST}${C_DIM})${RST}\n" "$name" "$count" "$current"
        git -C "$dir" branch -a 2>/dev/null | while read -r line; do
            if echo "$line" | grep -q '^\*'; then
                printf "  ${C_OK}%s${RST}\n" "$line"
            else
                printf "  ${C_DIM}%s${RST}\n" "$line"
            fi
        done
        echo ""
    done <<< "$(git_get_repos)"
}

git_cmd_tags() {
    printf "\n${BLD}=== Git Tags (all repos) ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local count; count=$(git_tag_count "$dir")
        [ "$count" -eq 0 ] && continue
        printf "${C_INFO}%s${RST} (${C_DIM}%s tags${RST})\n" "$name" "$count"
        git -C "$dir" tag -l 2>/dev/null | while read -r tag; do
            printf "  ${C_WARN}%s${RST}\n" "$tag"
        done
        echo ""
    done <<< "$(git_get_repos)"
}

git_cmd_log() {
    printf "\n${BLD}=== Git Log (last 10 commits per repo) ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}%s:${RST}\n" "$name"
        git -C "$dir" log --oneline --graph --decorate -10 2>/dev/null | while read -r line; do
            printf "  ${C_DIM}%s${RST}\n" "$line"
        done
        echo ""
    done <<< "$(git_get_repos)"
}

git_cmd_stash_list() {
    printf "\n${BLD}=== Git Stashes (all repos) ===${RST}\n\n"
    local found=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local count; count=$(git_stash_count "$dir")
        [ "$count" -eq 0 ] && continue
        found=1
        printf "${C_INFO}%s${RST} (${C_WARN}%s stashes${RST})\n" "$name" "$count"
        git -C "$dir" stash list 2>/dev/null | while read -r line; do
            printf "  ${C_DIM}%s${RST}\n" "$line"
        done
        echo ""
    done <<< "$(git_get_repos)"
    [ "$found" -eq 0 ] && printf "  ${C_OK}${S_OK} No stashes${RST}\n"
}

git_cmd_diff() {
    printf "\n${BLD}=== Git Diff (unstaged changes) ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        local dirty; dirty=$(git_dirty_count "$dir")
        [ "$dirty" -eq 0 ] && continue
        printf "${C_INFO}%s:${RST}\n" "$name"
        git -C "$dir" diff --stat 2>/dev/null
        echo ""
    done <<< "$(git_get_repos)"
}

git_cmd_gc() {
    printf "\n${BLD}=== Git Garbage Collection (all repos) ===${RST}\n\n"
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}${S_ARR}${RST} Running gc on %s...\n" "$name"
        git -C "$dir" gc --auto 2>&1 | while read -r line; do
            printf "  ${C_DIM}%s${RST}\n" "$line"
        done
    done <<< "$(git_get_repos)"
    printf "\n${C_OK}${S_OK}${RST} Done\n"
}

git_cmd_prune() {
    printf "\n${BLD}=== Git Prune (remove unreachable objects) ===${RST}\n\n"
    printf "${C_WARN}This will run 'git remote prune origin' + 'git prune' on all repos.${RST}\n"
    printf "Continue? [y/N] "
    read -r confirm
    case "$confirm" in
        [Yy]*) ;;
        *) printf "${C_DIM}Cancelled${RST}\n"; return ;;
    esac
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local dir="$GIT_WORKDIR/$name"
        [ ! -d "$dir/.git" ] && continue
        printf "${C_INFO}${S_ARR}${RST} Pruning %s...\n" "$name"
        git -C "$dir" remote prune origin 2>&1 | while read -r line; do
            printf "  ${C_DIM}%s${RST}\n" "$line"
        done
        git -C "$dir" prune 2>&1 | while read -r line; do
            printf "  ${C_DIM}%s${RST}\n" "$line"
        done
    done <<< "$(git_get_repos)"
    printf "\n${C_OK}${S_OK}${RST} Done\n"
}

# =============================================================================
# C) DRIVES - Rendering & Actions
# =============================================================================

render_drives() {
    # Cloud Drives
    printf "  ${BLD}%-17s %-27s %-7s %-16s %-8s Mount${RST}\n" \
        "CLOUD DRIVES" "Account" "State" "Usage" "Quota"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local drive_count
    drive_count=$(_jq '.drives | length')
    local d=0
    while [ "$d" -lt "$drive_count" ]; do
        local dname dacct dremote
        dname=$(_jq -r ".drives[$d].name")
        dacct=$(_jq -r ".drives[$d].account // \"\"")
        dremote=$(_jq -r ".drives[$d].remote")

        local dstate mount_path
        mount_path="$MOUNT_DIR/$dname"
        if is_mounted "$mount_path"; then
            dstate="${C_OK}${S_DOT} ON${RST}"
            # Try to get usage
            local usage
            usage=$(rclone about "${dremote}:" --json 2>/dev/null || echo "{}")
            local used_b free_b total_b
            used_b=$(echo "$usage" | jq -r '.used // 0' 2>/dev/null || echo 0)
            total_b=$(echo "$usage" | jq -r '.total // 0' 2>/dev/null || echo 0)
            local used_g=$((used_b / 1073741824))
            local total_g=$((total_b / 1073741824))
            [ "$total_g" -eq 0 ] && total_g=15  # default gdrive quota

            printf "  %-17s %-27s %b  " "$dname" "$dacct" "$dstate"
            gauge_bar "$used_g" "$total_g" 12 "${used_g}G/${total_g}G"
            printf "    %s\n" "$mount_path"
        else
            dstate="${C_DIM}${S_STOP} OFF${RST}"
            printf "  %-17s %-27s %b  ${C_DIM}—${RST}\n" "$dname" "$dacct" "$dstate"
        fi
        d=$((d+1))
    done

    # VM FUSE Mounts
    printf "\n  ${BLD}%-17s %-16s %-28s %-4s  Mount Base${RST}\n" \
        "VM FUSE MOUNTS" "Remote" "Subdirs" "Bar"
    printf "  ${C_DIM}"
    w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local vm_count
    vm_count=$(_jq '.mesh.vms | length')
    local v=0
    while [ "$v" -lt "$vm_count" ]; do
        local vname vremote valias
        vname=$(_jq -r ".mesh.vms[$v].name")
        valias=$(_jq -r ".mesh.vms[$v].alias")
        vremote="sftp://$valias"

        local mounted_count=0 total_subs=0 subdir_str=""
        for sub in sys home docker mnt; do
            total_subs=$((total_subs + 1))
            if is_mounted "$MOUNT_DIR/$vname/$sub"; then
                mounted_count=$((mounted_count + 1))
                subdir_str="${subdir_str}${C_OK}${sub}${S_DOT}${RST} "
            else
                subdir_str="${subdir_str}${C_DIM}${sub}${S_STOP}${RST} "
            fi
        done

        # Mount bar
        local bar_str=""
        local b=0
        while [ "$b" -lt "$total_subs" ]; do
            if [ "$b" -lt "$mounted_count" ]; then
                bar_str="${bar_str}${C_OK}█${RST}"
            else
                bar_str="${bar_str}${C_DIM}░${RST}"
            fi
            b=$((b+1))
        done

        local mount_base=""
        [ "$mounted_count" -gt 0 ] && mount_base="$MOUNT_DIR/$vname/"

        printf "  %-17s %-16s %b  %b  %s\n" \
            "$vname" "$vremote" "$subdir_str" "$bar_str" "$mount_base"
        v=$((v+1))
    done

    # Container symlinks
    if [ -d "$MOUNT_DIR" ]; then
        local symlink_count=0
        local symlink_list=""
        while IFS= read -r link; do
            [ -z "$link" ] && continue
            symlink_count=$((symlink_count + 1))
            local lname; lname=$(basename "$link")
            local ltarget; ltarget=$(readlink -f "$link" 2>/dev/null || echo "?")
            symlink_list="${symlink_list}${lname}:${ltarget}\n"
        done < <(find "$MOUNT_DIR" -maxdepth 1 -type l 2>/dev/null)
        if [ "$symlink_count" -gt 0 ]; then
            printf "\n  ${C_DIM}Container symlinks: %d${RST}" "$symlink_count"
            printf '%b' "$symlink_list" | while IFS=: read -r sn st; do
                [ -z "$sn" ] && continue
                printf " ${C_DIM}[%s]${RST}" "$sn"
            done
            printf "\n"
        fi
    fi
}

# Drive mount/unmount actions
mount_rclone_path() {
    local remote=$1 remote_path=$2 mountpoint=$3
    is_mounted "$mountpoint" && { printf "${C_WARN}Already mounted: %s${RST}\n" "$mountpoint"; return 0; }
    if ! rclone_remote_exists "$remote"; then
        printf "${C_ERR}Remote '%s' not configured${RST}\n" "$remote"
        return 1
    fi
    mkdir -p "$mountpoint"
    # shellcheck disable=SC2086
    nohup rclone mount "${remote}:${remote_path}" "$mountpoint" $RCLONE_OPTS >/dev/null 2>&1 &
    local tries=0
    while [ "$tries" -lt 10 ]; do
        sleep 0.5
        is_mounted "$mountpoint" && { printf "${C_OK}[+]${RST} Mounted %s\n" "$mountpoint"; log_msg "Mounted $mountpoint"; return 0; }
        tries=$((tries+1))
    done
    printf "${C_ERR}[-] Failed: %s${RST}\n" "$mountpoint"
    log_err "Mount failed: $mountpoint"
    return 1
}

mount_vm() {
    local name=$1 remote=$2
    printf "${C_INFO}[+]${RST} Mounting %s...\n" "$name"
    mount_rclone_path "$remote" "/" "$MOUNT_DIR/$name/sys" || true
    mount_rclone_path "$remote" "/home" "$MOUNT_DIR/$name/home" || true
    mount_rclone_path "$remote" "/var/lib/docker/volumes" "$MOUNT_DIR/$name/docker" || true
    mount_rclone_path "$remote" "/mnt" "$MOUNT_DIR/$name/mnt" || true
}

unmount_vm() {
    local name=$1
    for sub in sys home docker mnt; do
        if is_mounted "$MOUNT_DIR/$name/$sub"; then
            fusermount -uz "$MOUNT_DIR/$name/$sub" 2>/dev/null
            printf "${C_OK}[+]${RST} Unmounted %s/%s\n" "$name" "$sub"
        fi
    done
}

mount_drive() {
    local name=$1 remote=$2
    mount_rclone_path "$remote" "/" "$MOUNT_DIR/$name" || true
}

unmount_drive() {
    local name=$1
    if is_mounted "$MOUNT_DIR/$name"; then
        fusermount -uz "$MOUNT_DIR/$name" 2>/dev/null
        printf "${C_OK}[+]${RST} Unmounted %s\n" "$name"
    fi
}

mount_phone() {
    local dev_id phone_name sftp_base
    dev_id=$(_jq -r '.mesh.phone.device_id')
    phone_name=$(_jq -r '.mesh.phone.name')
    sftp_base=$(_jq -r '.mesh.phone.sftp_base')
    [ -z "$dev_id" ] || [ "$dev_id" = "null" ] && { printf "${C_ERR}Phone not configured${RST}\n"; return 1; }
    command -v kdeconnect-cli >/dev/null 2>&1 || { printf "${C_ERR}kdeconnect-cli not found${RST}\n"; return 1; }
    command -v qdbus >/dev/null 2>&1 || { printf "${C_ERR}qdbus not found${RST}\n"; return 1; }
    printf "${C_INFO}[+]${RST} Mounting phone...\n"
    qdbus org.kde.kdeconnect "/modules/kdeconnect/devices/$dev_id/sftp" \
        org.kde.kdeconnect.device.sftp.mount 2>/dev/null
    sleep 1
    rm -f "$MOUNT_DIR/$phone_name" 2>/dev/null
    ln -sf "$sftp_base" "$MOUNT_DIR/$phone_name"
    printf "${C_OK}[+]${RST} Mounted: %s/%s\n" "$MOUNT_DIR" "$phone_name"
}

unmount_phone() {
    local dev_id phone_name
    dev_id=$(_jq -r '.mesh.phone.device_id')
    phone_name=$(_jq -r '.mesh.phone.name')
    if command -v qdbus >/dev/null 2>&1 && [ -n "$dev_id" ] && [ "$dev_id" != "null" ]; then
        qdbus org.kde.kdeconnect "/modules/kdeconnect/devices/$dev_id/sftp" \
            org.kde.kdeconnect.device.sftp.unmount 2>/dev/null || true
    fi
    rm -f "$MOUNT_DIR/$phone_name" 2>/dev/null
    printf "${C_OK}[+]${RST} Phone unmounted\n"
}

# Numbered mount/unmount helpers
select_and_mount_vm() {
    printf "\n${BLD}Select VM to mount:${RST}\n"
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local i=0
    while [ "$i" -lt "$vm_count" ]; do
        local name; name=$(_jq -r ".mesh.vms[$i].name")
        printf "  ${C_INFO}%d${RST}) %s\n" "$((i+1))" "$name"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return
    local idx=$((ch-1))
    local name; name=$(_jq -r ".mesh.vms[$idx].name // empty")
    local remote; remote=$(_jq -r ".mesh.vms[$idx].remote // empty")
    [ -n "$name" ] && mount_vm "$name" "$remote"
}

select_and_unmount_vm() {
    printf "\n${BLD}Select VM to unmount:${RST}\n"
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local i=0
    while [ "$i" -lt "$vm_count" ]; do
        local name; name=$(_jq -r ".mesh.vms[$i].name")
        printf "  ${C_INFO}%d${RST}) %s\n" "$((i+1))" "$name"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return
    local idx=$((ch-1))
    local name; name=$(_jq -r ".mesh.vms[$idx].name // empty")
    [ -n "$name" ] && unmount_vm "$name"
}

select_and_mount_drive() {
    printf "\n${BLD}Select Drive to mount:${RST}\n"
    local d_count; d_count=$(_jq '.drives | length')
    local i=0
    while [ "$i" -lt "$d_count" ]; do
        local name; name=$(_jq -r ".drives[$i].name")
        printf "  ${C_INFO}%d${RST}) %s\n" "$((i+1))" "$name"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return
    local idx=$((ch-1))
    local name; name=$(_jq -r ".drives[$idx].name // empty")
    local remote; remote=$(_jq -r ".drives[$idx].remote // empty")
    [ -n "$name" ] && mount_drive "$name" "$remote"
}

select_and_unmount_drive() {
    printf "\n${BLD}Select Drive to unmount:${RST}\n"
    local d_count; d_count=$(_jq '.drives | length')
    local i=0
    while [ "$i" -lt "$d_count" ]; do
        local name; name=$(_jq -r ".drives[$i].name")
        printf "  ${C_INFO}%d${RST}) %s\n" "$((i+1))" "$name"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return
    local idx=$((ch-1))
    local name; name=$(_jq -r ".drives[$idx].name // empty")
    [ -n "$name" ] && unmount_drive "$name"
}

# =============================================================================
# C) DRIVES - OCI Flex Control
# =============================================================================

flex_action() {
    local action=$1  # start|stop|reset|status
    local flex_idx=$2  # vm index in config

    local instance_id region name
    instance_id=$(_jq -r ".mesh.vms[$flex_idx].oci_flex.instance_id // empty")
    region=$(_jq -r ".mesh.vms[$flex_idx].oci_flex.region // empty")
    name=$(_jq -r ".mesh.vms[$flex_idx].name")

    if [ -z "$instance_id" ]; then
        printf "${C_ERR}No OCI flex config for %s${RST}\n" "$name"
        return 1
    fi

    if ! command -v oci >/dev/null 2>&1; then
        printf "${C_ERR}oci CLI not found${RST}\n"
        return 1
    fi

    case "$action" in
        status)
            printf "${C_INFO}[i]${RST} Checking %s...\n" "$name"
            local state
            state=$(SUPPRESS_LABEL_WARNING=True oci compute instance get \
                --instance-id "$instance_id" --region "$region" \
                --query 'data."lifecycle-state"' --raw-output 2>/dev/null || echo "UNKNOWN")
            case "$state" in
                RUNNING) printf "  ${C_OK}${S_RUN}${RST} %s: %s\n" "$name" "$state" ;;
                STOPPED) printf "  ${C_ERR}${S_STOP}${RST} %s: %s\n" "$name" "$state" ;;
                *)       printf "  ${C_WARN}?${RST} %s: %s\n" "$name" "$state" ;;
            esac
            ;;
        start)
            printf "${C_INFO}[+]${RST} Starting %s...\n" "$name"
            SUPPRESS_LABEL_WARNING=True oci compute instance action \
                --instance-id "$instance_id" --region "$region" --action START >/dev/null 2>&1 && \
                printf "${C_OK}${S_OK}${RST} Start command sent\n" || \
                printf "${C_ERR}${S_FAIL}${RST} Failed\n"
            ;;
        stop)
            printf "${C_INFO}[-]${RST} Stopping %s...\n" "$name"
            unmount_vm "$name"
            SUPPRESS_LABEL_WARNING=True oci compute instance action \
                --instance-id "$instance_id" --region "$region" --action STOP >/dev/null 2>&1 && \
                printf "${C_OK}${S_OK}${RST} Stop command sent\n" || \
                printf "${C_ERR}${S_FAIL}${RST} Failed\n"
            ;;
        reset)
            printf "${C_WARN}[!]${RST} Resetting %s...\n" "$name"
            unmount_vm "$name"
            SUPPRESS_LABEL_WARNING=True oci compute instance action \
                --instance-id "$instance_id" --region "$region" --action RESET >/dev/null 2>&1 && \
                printf "${C_OK}${S_OK}${RST} Reset command sent\n" || \
                printf "${C_ERR}${S_FAIL}${RST} Failed\n"
            ;;
    esac
}

# Find flex VM indices
get_flex_indices() {
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local i=0
    while [ "$i" -lt "$vm_count" ]; do
        local has_flex; has_flex=$(_jq ".mesh.vms[$i].oci_flex // null")
        [ "$has_flex" != "null" ] && echo "$i"
        i=$((i+1))
    done
}

flex_select_and_action() {
    local action=$1
    local indices; indices=$(get_flex_indices)
    if [ -z "$indices" ]; then
        printf "${C_WARN}No OCI Flex VMs configured${RST}\n"
        return
    fi

    local count; count=$(echo "$indices" | wc -l)
    if [ "$count" -eq 1 ]; then
        flex_action "$action" "$indices"
    else
        printf "\n${BLD}Select Flex VM:${RST}\n"
        local n=1
        for idx in $indices; do
            local name; name=$(_jq -r ".mesh.vms[$idx].name")
            printf "  ${C_INFO}%d${RST}) %s\n" "$n" "$name"
            n=$((n+1))
        done
        printf "${BLD}Choice:${RST} "
        read -r ch
        local target; target=$(echo "$indices" | sed -n "${ch}p")
        [ -n "$target" ] && flex_action "$action" "$target"
    fi
}

# =============================================================================
# D) SYNC - Data Collection & Rendering
# =============================================================================

sync_list_rules() {
    [ ! -f "$SYNC_RULES_FILE" ] && echo "[]" && return
    jq '[.[] | select(has("name") and (.name | startswith("_") | not))]' "$SYNC_RULES_FILE" 2>/dev/null || echo "[]"
}

# --- Sync helpers ---

sync_save_rules() {
    local rules="$1"
    # Preserve schema/comment entries
    local schema="[]"
    if [ -f "$SYNC_RULES_FILE" ]; then
        schema=$(jq '[.[] | select(has("_comment") or has("_schema"))]' "$SYNC_RULES_FILE" 2>/dev/null || echo "[]")
    fi
    echo "$schema $rules" | jq -s 'add' > "$SYNC_RULES_FILE"
}

sync_get_rule() {
    local name="$1"
    sync_list_rules | jq -r ".[] | select(.name == \"$name\")"
}

generate_job_id() {
    echo "job_$(date '+%Y%m%d_%H%M%S')_$$"
}

sync_list_jobs() {
    if [ ! -s "$SYNC_JOBS_FILE" ] || [ "$(cat "$SYNC_JOBS_FILE")" = "[]" ]; then
        echo "[]"
        return
    fi
    cat "$SYNC_JOBS_FILE"
}

# --- Group 3: Job Tracking ---

sync_add_job() {
    local job_id="$1" name="$2" source="$3" dest="$4" sync_type="$5" pid="$6" log_file="$7"
    local now; now=$(date -Iseconds)
    local new_job
    new_job=$(printf '{"job_id":"%s","name":"%s","source":"%s","dest":"%s","sync_type":"%s","status":"running","started":"%s","ended":null,"pid":%s,"log_file":"%s"}' \
        "$job_id" "$name" "$source" "$dest" "$sync_type" "$now" "$pid" "$log_file")
    local jobs; jobs=$(sync_list_jobs)
    jobs=$(echo "$jobs" | jq '. | if length > 19 then .[-19:] else . end')
    echo "$jobs" | jq ". + [$new_job]" > "$SYNC_JOBS_FILE"
}

sync_update_job() {
    local job_id="$1" status="$2"
    local now; now=$(date -Iseconds)
    local jobs; jobs=$(sync_list_jobs)
    echo "$jobs" | jq \
        "(.[] | select(.job_id == \"$job_id\") | .status) = \"$status\" |
         (.[] | select(.job_id == \"$job_id\") | .ended) = \"$now\"" > "$SYNC_JOBS_FILE"
}

sync_clear_completed() {
    local jobs; jobs=$(sync_list_jobs)
    local running; running=$(echo "$jobs" | jq '[.[] | select(.status == "running")]')
    local removed=$(( $(echo "$jobs" | jq 'length') - $(echo "$running" | jq 'length') ))
    echo "$running" > "$SYNC_JOBS_FILE"
    printf "${C_OK}${S_OK}${RST} Cleared %d completed jobs\n" "$removed"
}

sync_update_last_run() {
    local name="$1"
    local now; now=$(date -Iseconds)
    local rules; rules=$(sync_list_rules)
    local updated; updated=$(echo "$rules" | jq "(.[] | select(.name == \"$name\") | .last_run) = \"$now\"")
    sync_save_rules "$updated"
}

# --- Group 1: Sync Engine ---

sync_one_way() {
    local source="$1" dest="$2" dry_run="${3:-false}" delete="${4:-true}"

    local cmd="rclone"
    if [ "$delete" = "true" ]; then
        cmd="$cmd sync"
    else
        cmd="$cmd copy"
    fi

    cmd="$cmd '$source' '$dest' $RCLONE_SYNC_OPTS --verbose --progress"
    [ "$dry_run" = "true" ] && cmd="$cmd --dry-run"

    printf "\n${C_INFO}${BLD}Sync: %s ${S_ARR} %s${RST}\n" "$source" "$dest"
    [ "$dry_run" = "true" ] && printf "${C_WARN}DRY RUN - No changes will be made${RST}\n"

    log_msg "Running: $cmd"
    if eval $cmd; then
        log_msg "Sync completed: $source -> $dest"
        return 0
    else
        log_err "Sync failed: $source -> $dest"
        return 1
    fi
}

sync_bisync() {
    local path1="$1" path2="$2" dry_run="${3:-false}" resync="${4:-false}" conflict_resolve="${5:-newer}"

    local bisync_cache="$HOME/.cache/rclone/bisync"
    [ ! -d "$bisync_cache" ] && resync="true"

    local cmd="rclone bisync '$path1' '$path2' $RCLONE_SYNC_OPTS --verbose"
    [ "$resync" = "true" ] && cmd="$cmd --resync"
    [ "$dry_run" = "true" ] && cmd="$cmd --dry-run"
    [ "$conflict_resolve" = "path1" ] || [ "$conflict_resolve" = "path2" ] && cmd="$cmd --conflict-resolve $conflict_resolve"

    printf "\n${C_INFO}${BLD}Bisync: %s ${S_ARBI} %s${RST}\n" "$path1" "$path2"
    [ "$resync" = "true" ] && printf "${C_WARN}Using --resync (first time or forced)${RST}\n"
    [ "$dry_run" = "true" ] && printf "${C_WARN}DRY RUN - No changes will be made${RST}\n"

    log_msg "Running: $cmd"
    if eval $cmd; then
        log_msg "Bisync completed: $path1 <-> $path2"
        return 0
    else
        log_err "Bisync failed: $path1 <-> $path2"
        return 1
    fi
}

sync_run_rule() {
    local name="$1" dry_run="${2:-false}"

    local rule; rule=$(sync_get_rule "$name")
    if [ -z "$rule" ]; then
        printf "${C_ERR}Rule '%s' not found${RST}\n" "$name"
        return 1
    fi

    local local_path remote sync_type conflict_resolve delete_extra
    local_path=$(echo "$rule" | jq -r '.local_path')
    remote=$(echo "$rule" | jq -r '.remote')
    sync_type=$(echo "$rule" | jq -r '.sync_type')
    conflict_resolve=$(echo "$rule" | jq -r '.conflict_resolve')
    delete_extra=$(echo "$rule" | jq -r '.delete_extra')

    printf "\n${BLD}=== Running rule: %s ===${RST}\n" "$name"
    printf "  Type: %s  Source: %s  Dest: %s\n" "$sync_type" "$local_path" "$remote"

    mkdir -p "$local_path" 2>/dev/null || true

    local success=false
    case "$sync_type" in
        bisync)
            sync_bisync "$remote" "$local_path" "$dry_run" "false" "$conflict_resolve" && success=true ;;
        sync_to_remote)
            sync_one_way "$local_path" "$remote" "$dry_run" "$delete_extra" && success=true ;;
        sync_to_local)
            sync_one_way "$remote" "$local_path" "$dry_run" "$delete_extra" && success=true ;;
        local_to_local|local_bisync)
            mkdir -p "$remote" 2>/dev/null || true
            if [ "$sync_type" = "local_bisync" ]; then
                sync_bisync "$local_path" "$remote" "$dry_run" "false" "$conflict_resolve" && success=true
            else
                sync_one_way "$local_path" "$remote" "$dry_run" "$delete_extra" && success=true
            fi ;;
    esac

    if [ "$success" = "true" ] && [ "$dry_run" = "false" ]; then
        sync_update_last_run "$name"
    fi

    [ "$success" = "true" ] && return 0 || return 1
}

sync_run_rule_background() {
    local name="$1" resync="${2:-false}"

    local rule; rule=$(sync_get_rule "$name")
    if [ -z "$rule" ]; then
        printf "${C_ERR}Rule '%s' not found${RST}\n" "$name"
        return 1
    fi

    local local_path remote sync_type conflict_resolve delete_extra
    local_path=$(echo "$rule" | jq -r '.local_path')
    remote=$(echo "$rule" | jq -r '.remote')
    sync_type=$(echo "$rule" | jq -r '.sync_type')
    conflict_resolve=$(echo "$rule" | jq -r '.conflict_resolve')
    delete_extra=$(echo "$rule" | jq -r '.delete_extra')

    mkdir -p "$local_path" 2>/dev/null || true
    { [ "$sync_type" = "local_to_local" ] || [ "$sync_type" = "local_bisync" ]; } && mkdir -p "$remote" 2>/dev/null || true

    local job_id; job_id=$(generate_job_id)
    local job_log="$SYNC_LOG_DIR/${job_id}.log"

    local source dest
    case "$sync_type" in
        bisync)         source="$remote"; dest="$local_path" ;;
        sync_to_remote) source="$local_path"; dest="$remote" ;;
        sync_to_local)  source="$remote"; dest="$local_path" ;;
        *)              source="$local_path"; dest="$remote" ;;
    esac

    local cmd
    case "$sync_type" in
        bisync|local_bisync)
            cmd="rclone bisync '$source' '$dest' $RCLONE_SYNC_OPTS -v --stats 3s --stats-log-level NOTICE"
            [ "$resync" = "true" ] && cmd="$cmd --resync"
            { [ "$conflict_resolve" = "path1" ] || [ "$conflict_resolve" = "path2" ]; } && cmd="$cmd --conflict-resolve $conflict_resolve"
            ;;
        *)
            if [ "$delete_extra" = "true" ]; then
                cmd="rclone sync '$source' '$dest' $RCLONE_SYNC_OPTS -v --stats 3s --stats-log-level NOTICE"
            else
                cmd="rclone copy '$source' '$dest' $RCLONE_SYNC_OPTS -v --stats 3s --stats-log-level NOTICE"
            fi ;;
    esac

    log_msg "Starting background job: $cmd"
    eval "$cmd" > "$job_log" 2>&1 &
    local pid=$!

    sync_add_job "$job_id" "$name" "$source" "$dest" "$sync_type" "$pid" "$job_log"

    log_msg "Started background sync: $name (PID: $pid)"
    printf "${C_OK}${S_OK}${RST} Started: %s (PID: %s, Job: %s)\n" "$name" "$pid" "$job_id"
    printf "  Log: %s\n" "$job_log"
}

sync_get_running_jobs() {
    [ ! -f "$SYNC_JOBS_FILE" ] && echo "[]" && return
    local jobs; jobs=$(cat "$SYNC_JOBS_FILE")
    local result="[]"
    while IFS= read -r job; do
        [ -z "$job" ] && continue
        local status pid
        status=$(echo "$job" | jq -r '.status')
        pid=$(echo "$job" | jq -r '.pid')
        if [ "$status" = "running" ] && kill -0 "$pid" 2>/dev/null; then
            result=$(echo "$result" | jq ". + [$job]")
        fi
    done < <(echo "$jobs" | jq -c '.[]' 2>/dev/null)
    echo "$result"
}

_sync_job_progress() {
    local log_file="$1"
    if [ ! -f "$log_file" ]; then
        echo "Starting..."
        return
    fi
    local percent transferred speed eta errors result=""
    percent=$(grep -oP '\d+%' "$log_file" 2>/dev/null | tail -1)
    transferred=$(grep -oP 'Transferred:\s+\K[^,]+' "$log_file" 2>/dev/null | tail -1)
    speed=$(grep -oP '\d+\.?\d*\s*[KMG]?i?B/s' "$log_file" 2>/dev/null | tail -1)
    eta=$(grep -oP 'ETA\s+\K\S+' "$log_file" 2>/dev/null | tail -1)
    errors=$(grep -c "ERROR" "$log_file" 2>/dev/null || echo 0)
    [ -n "$percent" ] && result="$percent"
    [ -n "$transferred" ] && result="$result | $transferred"
    [ -n "$speed" ] && result="$result | $speed"
    [ -n "$eta" ] && [ "$eta" != "-" ] && result="$result | ETA: $eta"
    [ "$errors" -gt 0 ] && result="$result | Err:$errors"
    if [ -n "$result" ]; then
        echo "$result"
    else
        local lines; lines=$(wc -l < "$log_file" 2>/dev/null || echo 0)
        echo "Processing... ($lines log lines)"
    fi
}

sync_get_completed_jobs() {
    [ ! -f "$SYNC_JOBS_FILE" ] && echo "[]" && return
    local jobs; jobs=$(cat "$SYNC_JOBS_FILE")
    echo "$jobs" | jq -c '[.[] | select(.status != "running")] | .[-5:]' 2>/dev/null || echo "[]"
}

sync_run_rule_interactive() {
    local rules; rules=$(sync_list_rules)
    local count; count=$(echo "$rules" | jq 'length')
    [ "$count" -eq 0 ] && { printf "${C_DIM}No rules configured${RST}\n"; return; }

    printf "\n${BLD}Select rule to run:${RST}\n"
    local i=0
    echo "$rules" | jq -c '.[]' | while IFS= read -r r; do
        local nm; nm=$(echo "$r" | jq -r '.name')
        local en; en=$(echo "$r" | jq -r '.enabled')
        local icon="${C_OK}${S_DOT}${RST}"
        [ "$en" != "true" ] && icon="${C_DIM}${S_STOP}${RST}"
        printf "  %b %d) %s\n" "$icon" "$i" "$nm"
        i=$((i+1))
    done

    printf "${BLD}Rule # (or name):${RST} "
    read -r sel
    [ -z "$sel" ] && return

    local name=""
    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        name=$(echo "$rules" | jq -r ".[$sel].name // empty")
    else
        name="$sel"
    fi
    [ -z "$name" ] && { printf "${C_ERR}Invalid selection${RST}\n"; return; }

    printf "Run mode: ${C_INFO}1${RST}) Background  ${C_INFO}2${RST}) Foreground  ${C_INFO}3${RST}) Dry run  [1]: "
    read -r mode
    mode="${mode:-1}"
    case "$mode" in
        1) sync_run_rule_background "$name" ;;
        2) sync_run_rule "$name" "false" ;;
        3) sync_run_rule "$name" "true" ;;
    esac
}

sync_run_rule_cli() {
    local name="$1"
    [ -z "$name" ] && { printf "${C_ERR}Usage: cloud-connect.sh sync-run-rule NAME [--dry-run] [--background]${RST}\n"; return 1; }
    shift
    local dry_run="false" background="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run="true" ;;
            --background|-bg) background="true" ;;
        esac
        shift
    done
    if [ "$background" = "true" ]; then
        sync_run_rule_background "$name"
    else
        sync_run_rule "$name" "$dry_run"
    fi
}

sync_list_cli() {
    local rules; rules=$(sync_list_rules)
    local count; count=$(echo "$rules" | jq 'length')
    [ "$count" -eq 0 ] && { printf "${C_DIM}No rules configured${RST}\n"; return; }

    printf "\n${BLD}━━━ Sync Rules ━━━${RST}\n\n"
    local i=1
    echo "$rules" | jq -c '.[]' | while IFS= read -r rule; do
        local name sync_type enabled local_path remote last_run
        name=$(echo "$rule" | jq -r '.name')
        sync_type=$(echo "$rule" | jq -r '.sync_type')
        enabled=$(echo "$rule" | jq -r '.enabled')
        local_path=$(echo "$rule" | jq -r '.local_path')
        remote=$(echo "$rule" | jq -r '.remote')
        last_run=$(echo "$rule" | jq -r '.last_run // "never"')
        [ "$last_run" != "never" ] && [ "$last_run" != "null" ] && last_run="${last_run:0:16}"
        [ "$last_run" = "null" ] && last_run="never"

        local icon status_icon
        case "$sync_type" in
            bisync|local_bisync) icon="$S_ARBI" ;;
            sync_to_remote|local_to_local) icon="$S_ARR" ;;
            sync_to_local) icon="$S_ARRL" ;;
            *) icon="?" ;;
        esac

        if [ "$enabled" = "true" ]; then
            status_icon="${C_OK}${S_DOT}${RST}"
        else
            status_icon="${C_DIM}${S_STOP}${RST}"
        fi

        printf "%2d. %b %s\n" "$i" "$status_icon" "$name"
        printf "    ${C_DIM}%s %s %s${RST}\n" "$local_path" "$icon" "$remote"
        printf "    ${C_DIM}Type: %s | Last: %s${RST}\n\n" "$sync_type" "$last_run"
        i=$((i+1))
    done
}

render_sync() {
    # Configured Remotes
    printf "  ${BLD}%-17s %-30s State${RST}\n" "REMOTES" "Name"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    if command -v rclone >/dev/null 2>&1; then
        local remotes; remotes=$(rclone listremotes 2>/dev/null | sed 's/:$//')
        if [ -n "$remotes" ]; then
            echo "$remotes" | while read -r remote; do
                printf "  ${C_OK}${S_DOT}${RST}  %-30s ${C_OK}configured${RST}\n" "$remote"
            done
        else
            printf "  ${C_DIM}No remotes configured${RST}\n"
        fi
    else
        printf "  ${C_DIM}rclone not installed${RST}\n"
    fi
    printf "\n"

    # Rules table with count summary
    local rules; rules=$(sync_list_rules)
    local rule_count; rule_count=$(echo "$rules" | jq 'length')
    local enabled_cnt; enabled_cnt=$(echo "$rules" | jq '[.[] | select(.enabled == true)] | length')
    local disabled_cnt=$((rule_count - enabled_cnt))

    printf "  ${BLD}%-17s %-4s %-7s %-30s %-26s %-9s Last Run${RST}" \
        "RULES" "Type" "Enabled" "Remote Path" "Local Path" "Conflicts"
    printf "  ${C_DIM}(%s total, ${RST}${C_OK}%s on${RST}${C_DIM}, %s off)${RST}\n" \
        "$rule_count" "$enabled_cnt" "$disabled_cnt"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    if [ "$rule_count" -gt 0 ]; then
        echo "$rules" | jq -c '.[]' | while IFS= read -r rule; do
            local name sync_type enabled remote local_path conflict last_run
            name=$(echo "$rule" | jq -r '.name')
            sync_type=$(echo "$rule" | jq -r '.sync_type')
            enabled=$(echo "$rule" | jq -r '.enabled')
            remote=$(echo "$rule" | jq -r '.remote')
            local_path=$(echo "$rule" | jq -r '.local_path')
            conflict=$(echo "$rule" | jq -r '.conflict_resolve // "newer"')
            last_run=$(echo "$rule" | jq -r '.last_run // "never"')
            [ "$last_run" != "never" ] && [ "$last_run" != "null" ] && last_run="${last_run:0:16}"
            [ "$last_run" = "null" ] && last_run="never"

            local icon en_str
            case "$sync_type" in
                bisync|local_bisync) icon="$S_ARBI" ;;
                sync_to_remote|local_to_local) icon="$S_ARR" ;;
                sync_to_local) icon="$S_ARRL" ;;
                *) icon="?" ;;
            esac

            if [ "$enabled" = "true" ]; then
                en_str="${C_OK}ON${RST}"
            else
                en_str="${C_DIM}OFF${RST}"
            fi

            # Shorten paths
            local r_short="${remote:0:30}"
            local l_short
            l_short=$(echo "$local_path" | sed "s|$HOME|~|")
            l_short="${l_short:0:26}"

            printf "  %-17s  %s   %b%5s  %-30s %-26s %-9s %s\n" \
                "$name" "$icon" "$en_str" "" "$r_short" "$l_short" "$conflict" "$last_run"
        done
    else
        printf "  ${C_DIM}No sync rules configured${RST}\n"
    fi

    # Active jobs with rich progress
    local running; running=$(sync_get_running_jobs)
    local run_count; run_count=$(echo "$running" | jq 'length')

    if [ "$run_count" -gt 0 ]; then
        printf "\n  ${BLD}%-17s %-8s %-11s %-17s Progress${RST}\n" \
            "ACTIVE JOBS" "PID" "Elapsed" "Rule"
        printf "  ${C_DIM}"
        w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
        printf "${RST}\n"

        echo "$running" | jq -c '.[]' | while IFS= read -r job; do
            local jname jpid jstarted jlog
            jname=$(echo "$job" | jq -r '.name')
            jpid=$(echo "$job" | jq -r '.pid')
            jstarted=$(echo "$job" | jq -r '.started')
            jlog=$(echo "$job" | jq -r '.log_file')

            local start_epoch now_epoch elapsed mins secs
            start_epoch=$(date -d "$jstarted" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            elapsed=$((now_epoch - start_epoch))
            mins=$((elapsed / 60))
            secs=$((elapsed % 60))

            local pct_str
            pct_str=$(_sync_job_progress "$jlog")

            printf "  ${C_OK}${S_PLAY}${RST} running        %-8s %02d:%02d:%02d   %-17s %s\n" \
                "$jpid" "$((elapsed/3600))" "$mins" "$secs" "$jname" "$pct_str"
        done
    fi

    # Completed/failed jobs (last 5)
    local completed; completed=$(sync_get_completed_jobs)
    local comp_count; comp_count=$(echo "$completed" | jq 'length')
    if [ "$comp_count" -gt 0 ]; then
        printf "\n  ${C_DIM}Recent:${RST}\n"
        echo "$completed" | jq -c '.[]' | while IFS= read -r job; do
            local jname jstatus jended
            jname=$(echo "$job" | jq -r '.name')
            jstatus=$(echo "$job" | jq -r '.status')
            jended=$(echo "$job" | jq -r '.ended // ""')
            [ -n "$jended" ] && jended="${jended:0:16}"
            case "$jstatus" in
                completed) printf "  ${C_OK}${S_OK}${RST} %s ${C_DIM}(%s)${RST}\n" "$jname" "$jended" ;;
                failed)    printf "  ${C_ERR}${S_FAIL}${RST} %s ${C_DIM}(%s)${RST}\n" "$jname" "$jended" ;;
                cancelled) printf "  ${C_WARN}${S_WARN}${RST} %s ${C_DIM}(%s)${RST}\n" "$jname" "$jended" ;;
            esac
        done
    fi
}

sync_run_all() {
    local rules; rules=$(sync_list_rules)
    local enabled; enabled=$(echo "$rules" | jq -c '.[] | select(.enabled == true)')

    if [ -z "$enabled" ]; then
        printf "${C_DIM}No enabled sync rules${RST}\n"
        return
    fi

    printf "\n${BLD}=== Running All Enabled Sync Rules ===${RST}\n\n"

    printf "Run mode: ${C_INFO}1${RST}) Background  ${C_INFO}2${RST}) Foreground  ${C_INFO}3${RST}) Dry run  [1]: "
    read -r mode
    mode="${mode:-1}"

    echo "$enabled" | while IFS= read -r rule; do
        local name; name=$(echo "$rule" | jq -r '.name')
        case "$mode" in
            1) sync_run_rule_background "$name" ;;
            2) sync_run_rule "$name" "false" ;;
            3) sync_run_rule "$name" "true" ;;
        esac
    done
}

sync_edit_rules() {
    if [ -f "$SYNC_RULES_FILE" ]; then
        "${EDITOR:-vim}" "$SYNC_RULES_FILE"
    else
        printf "${C_WARN}No rules file: %s${RST}\n" "$SYNC_RULES_FILE"
    fi
}

sync_show_jobs() {
    local running; running=$(sync_get_running_jobs)
    local count; count=$(echo "$running" | jq 'length')
    if [ "$count" -eq 0 ]; then
        printf "${C_DIM}No running jobs${RST}\n"
        return
    fi
    echo "$running" | jq -c '.[]' | while IFS= read -r job; do
        local name pid; name=$(echo "$job" | jq -r '.name'); pid=$(echo "$job" | jq -r '.pid')
        printf "  ${C_OK}${S_PLAY}${RST} %s (PID: %s)\n" "$name" "$pid"
    done
}

sync_cancel_job() {
    local running; running=$(sync_get_running_jobs)
    local count; count=$(echo "$running" | jq 'length')
    [ "$count" -eq 0 ] && { printf "${C_DIM}No running jobs${RST}\n"; return; }
    sync_show_jobs
    printf "${BLD}Enter PID to cancel:${RST} "
    read -r pid
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        printf "${C_OK}${S_OK}${RST} Cancelled PID %s\n" "$pid"
    else
        printf "${C_ERR}PID not found or not running${RST}\n"
    fi
}

sync_kill_all() {
    local running; running=$(sync_get_running_jobs)
    echo "$running" | jq -r '.[].pid' | while read -r pid; do
        kill -TERM "$pid" 2>/dev/null && printf "${C_OK}${S_OK}${RST} Killed %s\n" "$pid"
    done
}

# =============================================================================
# D) SYNC - Rule Management (Group 2)
# =============================================================================

sync_add_rule() {
    local name="$1" local_path="$2" remote="$3" sync_type="$4"
    local conflict_resolve="${5:-newer}" delete_extra="${6:-true}"

    if [ -n "$(sync_get_rule "$name")" ]; then
        printf "${C_ERR}Rule '%s' already exists${RST}\n" "$name"
        return 1
    fi

    local now; now=$(date -Iseconds)
    local new_rule
    new_rule=$(printf '{"name":"%s","local_path":"%s","remote":"%s","sync_type":"%s","conflict_resolve":"%s","delete_extra":%s,"enabled":true,"last_run":null,"created":"%s"}' \
        "$name" "$local_path" "$remote" "$sync_type" "$conflict_resolve" "$delete_extra" "$now")

    local rules; rules=$(sync_list_rules)
    local updated; updated=$(echo "$rules" | jq ". + [$new_rule]")
    sync_save_rules "$updated"
    printf "${C_OK}${S_OK}${RST} Rule '%s' added\n" "$name"
    log_msg "Added sync rule: $name"
}

sync_delete_rule() {
    local rules; rules=$(sync_list_rules)
    local count; count=$(echo "$rules" | jq 'length')
    [ "$count" -eq 0 ] && { printf "${C_DIM}No rules to delete${RST}\n"; return; }

    printf "\n${BLD}Select rule to delete:${RST}\n"
    local i=0
    while [ "$i" -lt "$count" ]; do
        local name; name=$(echo "$rules" | jq -r ".[$i].name")
        printf "  ${C_INFO}%d${RST}) %s\n" "$((i+1))" "$name"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return

    local idx=$((ch-1))
    local name; name=$(echo "$rules" | jq -r ".[$idx].name // empty")
    [ -z "$name" ] && { printf "${C_ERR}Invalid choice${RST}\n"; return; }

    printf "${C_WARN}Delete rule '%s'? [y/N]:${RST} " "$name"
    read -r confirm
    case "$confirm" in
        [Yy]*)
            local updated; updated=$(echo "$rules" | jq "del(.[] | select(.name == \"$name\"))")
            sync_save_rules "$updated"
            printf "${C_OK}${S_OK}${RST} Deleted rule '%s'\n" "$name"
            log_msg "Deleted sync rule: $name"
            ;;
        *) printf "${C_DIM}Cancelled${RST}\n" ;;
    esac
}

sync_toggle_rule() {
    local rules; rules=$(sync_list_rules)
    local count; count=$(echo "$rules" | jq 'length')
    [ "$count" -eq 0 ] && { printf "${C_DIM}No rules to toggle${RST}\n"; return; }

    printf "\n${BLD}Select rule to toggle:${RST}\n"
    local i=0
    while [ "$i" -lt "$count" ]; do
        local name enabled
        name=$(echo "$rules" | jq -r ".[$i].name")
        enabled=$(echo "$rules" | jq -r ".[$i].enabled")
        local state_str
        [ "$enabled" = "true" ] && state_str="${C_OK}ON${RST}" || state_str="${C_DIM}OFF${RST}"
        printf "  ${C_INFO}%d${RST}) %-20s %b\n" "$((i+1))" "$name" "$state_str"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return

    local idx=$((ch-1))
    local name; name=$(echo "$rules" | jq -r ".[$idx].name // empty")
    [ -z "$name" ] && { printf "${C_ERR}Invalid choice${RST}\n"; return; }

    local current; current=$(echo "$rules" | jq -r ".[$idx].enabled")
    local new_state="true"
    [ "$current" = "true" ] && new_state="false"

    local updated; updated=$(echo "$rules" | jq "(.[] | select(.name == \"$name\") | .enabled) = $new_state")
    sync_save_rules "$updated"
    if [ "$new_state" = "true" ]; then
        printf "${C_OK}${S_OK}${RST} Enabled '%s'\n" "$name"
    else
        printf "${C_WARN}${S_STOP}${RST} Disabled '%s'\n" "$name"
    fi
}

_sync_select_remote_menu() {
    local remotes; remotes=$(rclone listremotes 2>/dev/null | sed 's/:$//')
    if [ -z "$remotes" ]; then
        printf "${C_ERR}No rclone remotes configured. Run 'rclone config' first.${RST}\n"
        return 1
    fi

    printf "\n${BLD}Select Remote:${RST}\n"
    local i=1
    echo "$remotes" | while IFS= read -r r; do
        printf "  ${C_INFO}%d${RST}) %s\n" "$i" "$r"
        i=$((i+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return 1
    echo "$remotes" | sed -n "${ch}p"
}

_sync_select_type_menu() {
    local include_local="${1:-false}"

    printf "\n${BLD}Select Sync Type:${RST}\n"
    printf "  ${C_INFO}1${RST}) Bisync (%s) - Two-way sync\n" "$S_ARBI"
    printf "  ${C_INFO}2${RST}) Sync to Remote (%s) - Local overwrites remote\n" "$S_ARR"
    printf "  ${C_INFO}3${RST}) Sync to Local (%s) - Remote overwrites local\n" "$S_ARRL"
    [ "$include_local" = "true" ] && printf "  ${C_INFO}4${RST}) Local to Local - Sync between local folders\n"
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice [1]:${RST} "
    read -r ch
    ch="${ch:-1}"

    case "$ch" in
        1) echo "bisync" ;;
        2) echo "sync_to_remote" ;;
        3) echo "sync_to_local" ;;
        4) [ "$include_local" = "true" ] && echo "local_to_local" || return 1 ;;
        0) return 1 ;;
        *) return 1 ;;
    esac
}

sync_add_rule_wizard() {
    printf "\n${BLD}━━━ Add New Sync Rule ━━━${RST}\n\n"

    printf "${BLD}Rule name:${RST} "
    read -r name
    [ -z "$name" ] && { printf "${C_ERR}Name is required${RST}\n"; return 1; }

    if [ -n "$(sync_get_rule "$name")" ]; then
        printf "${C_ERR}Rule '%s' already exists${RST}\n" "$name"
        return 1
    fi

    printf "\n${BLD}Rule type:${RST}\n"
    printf "  ${C_INFO}1${RST}) Remote sync (local ${S_ARBI} cloud)\n"
    printf "  ${C_INFO}2${RST}) Local sync (local ${S_ARBI} local)\n"
    printf "${BLD}Choice [1]:${RST} "
    read -r rule_type
    rule_type="${rule_type:-1}"

    local local_path remote sync_type conflict_resolve delete_extra

    if [ "$rule_type" = "2" ]; then
        printf "\n${BLD}Source folder path:${RST} "
        read -r local_path
        [ -z "$local_path" ] && { printf "${C_ERR}Source path required${RST}\n"; return 1; }

        printf "${BLD}Destination folder path:${RST} "
        read -r remote
        [ -z "$remote" ] && { printf "${C_ERR}Destination path required${RST}\n"; return 1; }

        printf "\n${BLD}Sync direction:${RST}\n"
        printf "  ${C_INFO}1${RST}) One-way (source ${S_ARR} dest, with deletions)\n"
        printf "  ${C_INFO}2${RST}) One-way copy (no deletions)\n"
        printf "  ${C_INFO}3${RST}) Bisync (${S_ARBI} two-way)\n"
        printf "${BLD}Choice [1]:${RST} "
        read -r dir_choice
        dir_choice="${dir_choice:-1}"

        case "$dir_choice" in
            1) sync_type="local_to_local"; delete_extra="true" ;;
            2) sync_type="local_to_local"; delete_extra="false" ;;
            3) sync_type="local_bisync"; delete_extra="true" ;;
            *) sync_type="local_to_local"; delete_extra="true" ;;
        esac

        conflict_resolve="newer"
        if [ "$sync_type" = "local_bisync" ]; then
            printf "\n${BLD}Conflict resolution:${RST}\n"
            printf "  ${C_INFO}1${RST}) newer (default)\n"
            printf "  ${C_INFO}2${RST}) larger\n"
            printf "  ${C_INFO}3${RST}) path1 (source wins)\n"
            printf "  ${C_INFO}4${RST}) path2 (dest wins)\n"
            printf "${BLD}Choice [1]:${RST} "
            read -r cr_choice
            case "$cr_choice" in
                2) conflict_resolve="larger" ;;
                3) conflict_resolve="path1" ;;
                4) conflict_resolve="path2" ;;
                *) conflict_resolve="newer" ;;
            esac
        fi
    else
        local remote_name; remote_name=$(_sync_select_remote_menu)
        [ -z "$remote_name" ] && return 1

        printf "\n${BLD}Remote path (empty for root):${RST} "
        read -r remote_path
        remote="${remote_name}:${remote_path}"

        printf "${BLD}Local path [%s]:${RST} " "$HOME/Documents/Gdrive_Syncs"
        read -r local_path
        local_path="${local_path:-$HOME/Documents/Gdrive_Syncs}"

        sync_type=$(_sync_select_type_menu)
        [ -z "$sync_type" ] && return 1

        delete_extra="true"
        conflict_resolve="newer"

        if [ "$sync_type" = "bisync" ]; then
            printf "\n${BLD}Conflict resolution:${RST}\n"
            printf "  ${C_INFO}1${RST}) newer (default)\n"
            printf "  ${C_INFO}2${RST}) larger\n"
            printf "  ${C_INFO}3${RST}) path1 (remote wins)\n"
            printf "  ${C_INFO}4${RST}) path2 (local wins)\n"
            printf "${BLD}Choice [1]:${RST} "
            read -r cr_choice
            case "$cr_choice" in
                2) conflict_resolve="larger" ;;
                3) conflict_resolve="path1" ;;
                4) conflict_resolve="path2" ;;
                *) conflict_resolve="newer" ;;
            esac
        fi
    fi

    sync_add_rule "$name" "$local_path" "$remote" "$sync_type" "$conflict_resolve" "$delete_extra"
}

sync_quick_menu() {
    printf "\n${BLD}━━━ Quick Sync ━━━${RST}\n\n"

    local sync_type; sync_type=$(_sync_select_type_menu "true")
    [ -z "$sync_type" ] && return 1

    local source dest

    if [ "$sync_type" = "local_to_local" ]; then
        printf "\n${BLD}Source folder:${RST} "
        read -r source
        [ -z "$source" ] && { printf "${C_ERR}Source required${RST}\n"; return 1; }

        printf "${BLD}Destination folder:${RST} "
        read -r dest
        [ -z "$dest" ] && { printf "${C_ERR}Destination required${RST}\n"; return 1; }
    else
        local remote_name; remote_name=$(_sync_select_remote_menu)
        [ -z "$remote_name" ] && return 1

        printf "\n${BLD}Remote path (empty for root):${RST} "
        read -r remote_path
        local remote="${remote_name}:${remote_path}"

        printf "${BLD}Local path [%s]:${RST} " "$HOME/Documents/Gdrive_Syncs"
        read -r local_path
        local_path="${local_path:-$HOME/Documents/Gdrive_Syncs}"

        case "$sync_type" in
            bisync)         source="$remote"; dest="$local_path" ;;
            sync_to_remote) source="$local_path"; dest="$remote" ;;
            sync_to_local)  source="$remote"; dest="$local_path" ;;
        esac
    fi

    printf "\n${BLD}Run mode:${RST}\n"
    printf "  ${C_INFO}1${RST}) Background (returns to menu)\n"
    printf "  ${C_INFO}2${RST}) Foreground (wait for completion)\n"
    printf "  ${C_INFO}3${RST}) Dry run (preview only)\n"
    printf "${BLD}Choice [1]:${RST} "
    read -r mode
    mode="${mode:-1}"

    case "$mode" in
        1)
            local job_id; job_id=$(generate_job_id)
            local job_log="$SYNC_LOG_DIR/${job_id}.log"
            local cmd
            case "$sync_type" in
                bisync|local_bisync) cmd="rclone bisync '$source' '$dest' $RCLONE_SYNC_OPTS -v --stats 3s" ;;
                *) cmd="rclone sync '$source' '$dest' $RCLONE_SYNC_OPTS -v --stats 3s" ;;
            esac
            eval "$cmd" > "$job_log" 2>&1 &
            local pid=$!
            sync_add_job "$job_id" "Quick Sync" "$source" "$dest" "$sync_type" "$pid" "$job_log"
            printf "${C_OK}${S_OK}${RST} Started background sync (PID: %s, Job: %s)\n" "$pid" "$job_id"
            ;;
        2)
            case "$sync_type" in
                bisync|local_bisync) sync_bisync "$source" "$dest" "false" ;;
                *) sync_one_way "$source" "$dest" "false" ;;
            esac
            ;;
        3)
            case "$sync_type" in
                bisync|local_bisync) sync_bisync "$source" "$dest" "true" ;;
                *) sync_one_way "$source" "$dest" "true" ;;
            esac
            ;;
    esac
}

# =============================================================================
# D) SYNC - Ad-hoc CLI & Extra Commands
# =============================================================================

# Ad-hoc one-way sync from CLI: cloud-connect.sh sync-to SRC DEST [--dry-run] [--background]
sync_adhoc() {
    local source="$1" dest="$2"
    [ -z "$source" ] || [ -z "$dest" ] && {
        printf "${C_ERR}Usage: cloud-connect.sh sync-to SOURCE DEST [--dry-run] [--background]${RST}\n"
        return 1
    }
    shift 2
    local dry_run="false" background="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run="true" ;;
            --background|-bg) background="true" ;;
        esac
        shift
    done

    if [ "$background" = "true" ]; then
        local job_id; job_id=$(generate_job_id)
        local job_log="$SYNC_LOG_DIR/${job_id}.log"
        local cmd="rclone sync '$source' '$dest' $RCLONE_SYNC_OPTS -v --stats 3s --stats-log-level NOTICE"
        [ "$dry_run" = "true" ] && cmd="$cmd --dry-run"
        log_msg "Running adhoc sync: $cmd"
        eval "$cmd" > "$job_log" 2>&1 &
        local pid=$!
        sync_add_job "$job_id" "adhoc-sync" "$source" "$dest" "sync" "$pid" "$job_log"
        printf "${C_OK}${S_OK}${RST} Started adhoc sync (PID: %s, Job: %s)\n" "$pid" "$job_id"
        printf "  Log: %s\n" "$job_log"
    else
        sync_one_way "$source" "$dest" "$dry_run" "true"
    fi
}

# Ad-hoc bisync from CLI: cloud-connect.sh bisync-to P1 P2 [--dry-run] [--resync] [--background]
bisync_adhoc() {
    local p1="$1" p2="$2"
    [ -z "$p1" ] || [ -z "$p2" ] && {
        printf "${C_ERR}Usage: cloud-connect.sh bisync-to PATH1 PATH2 [--dry-run] [--resync] [--background]${RST}\n"
        return 1
    }
    shift 2
    local dry_run="false" resync="false" background="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run="true" ;;
            --resync) resync="true" ;;
            --background|-bg) background="true" ;;
        esac
        shift
    done

    if [ "$background" = "true" ]; then
        local job_id; job_id=$(generate_job_id)
        local job_log="$SYNC_LOG_DIR/${job_id}.log"
        local cmd="rclone bisync '$p1' '$p2' $RCLONE_SYNC_OPTS -v --stats 3s --stats-log-level NOTICE"
        [ "$resync" = "true" ] && cmd="$cmd --resync"
        [ "$dry_run" = "true" ] && cmd="$cmd --dry-run"
        log_msg "Running adhoc bisync: $cmd"
        eval "$cmd" > "$job_log" 2>&1 &
        local pid=$!
        sync_add_job "$job_id" "adhoc-bisync" "$p1" "$p2" "bisync" "$pid" "$job_log"
        printf "${C_OK}${S_OK}${RST} Started adhoc bisync (PID: %s, Job: %s)\n" "$pid" "$job_id"
        printf "  Log: %s\n" "$job_log"
    else
        sync_bisync "$p1" "$p2" "$dry_run" "$resync"
    fi
}

# Run all enabled in background (non-interactive, no prompt)
sync_run_all_bg() {
    local rules; rules=$(sync_list_rules)
    local enabled; enabled=$(echo "$rules" | jq -c '.[] | select(.enabled == true)')

    if [ -z "$enabled" ]; then
        printf "${C_DIM}No enabled sync rules${RST}\n"
        return
    fi

    printf "\n${BLD}=== Running All Enabled Rules (Background) ===${RST}\n\n"
    local success=0 failed=0
    echo "$enabled" | while IFS= read -r rule; do
        local name; name=$(echo "$rule" | jq -r '.name')
        sync_run_rule_background "$name" && success=$((success+1)) || failed=$((failed+1))
    done
    printf "\n${C_OK}${S_OK}${RST} All rules launched in background\n"
}

# Cancel by job ID (non-interactive CLI)
sync_cancel_by_id() {
    local job_id="$1"
    [ -z "$job_id" ] && { printf "${C_ERR}Usage: cloud-connect.sh sync-cancel-id JOB_ID${RST}\n"; return 1; }
    local jobs; jobs=$(cat "$SYNC_JOBS_FILE" 2>/dev/null || echo "[]")
    local pid; pid=$(echo "$jobs" | jq -r ".[] | select(.job_id == \"$job_id\") | .pid")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        sync_update_job "$job_id" "cancelled"
        printf "${C_OK}${S_OK}${RST} Cancelled job %s (PID: %s)\n" "$job_id" "$pid"
    else
        printf "${C_ERR}Job not found or not running: %s${RST}\n" "$job_id"
    fi
}

# Full sync status display (remotes + rules + jobs + log)
sync_full_status() {
    printf "\n${BLD}━━━ Sync Status ━━━${RST}\n\n"

    # Configured Remotes
    printf "  ${C_INFO}${BLD}Configured Remotes${RST}\n"
    printf "  ${C_DIM}────────────────────────────────────────────────${RST}\n"
    if command -v rclone >/dev/null 2>&1; then
        local remotes; remotes=$(rclone listremotes 2>/dev/null | sed 's/:$//')
        if [ -n "$remotes" ]; then
            echo "$remotes" | while read -r r; do
                printf "  ${C_OK}${S_DOT}${RST} %s\n" "$r"
            done
        else
            printf "  ${C_DIM}No remotes configured${RST}\n"
        fi
    else
        printf "  ${C_DIM}rclone not installed${RST}\n"
    fi

    # Rules summary
    local rules; rules=$(sync_list_rules)
    local total; total=$(echo "$rules" | jq 'length')
    local enabled; enabled=$(echo "$rules" | jq '[.[] | select(.enabled == true)] | length')
    local disabled; disabled=$((total - enabled))
    printf "\n  ${C_SYNC}${BLD}Sync Rules${RST}\n"
    printf "  ${C_DIM}────────────────────────────────────────────────${RST}\n"
    printf "  Total: %s | ${C_OK}Enabled: %s${RST} | ${C_DIM}Disabled: %s${RST}\n\n" "$total" "$enabled" "$disabled"

    # Render full sync table
    render_sync

    # Jobs summary
    local running; running=$(sync_get_running_jobs)
    local run_count; run_count=$(echo "$running" | jq 'length')
    printf "\n  ${C_SYNC}${BLD}Background Jobs${RST}: "
    if [ "$run_count" -gt 0 ]; then
        printf "${C_OK}%s running${RST}\n" "$run_count"
    else
        printf "${C_DIM}none${RST}\n"
    fi

    printf "\n"
    view_log
}

# Restore symlinks (from gcl.sh)
restore_symlinks() {
    local script="$SCRIPT_DIR/restore-spec-symlinks.sh"
    if [ ! -f "$script" ]; then
        printf "${C_WARN}No restore-spec-symlinks.sh found in %s${RST}\n" "$SCRIPT_DIR"
        printf "${C_DIM}This script restores 0.spec symlinks in the git workdir${RST}\n"
        return 1
    fi
    printf "${BLD}=== Restoring Spec Symlinks ===${RST}\n\n"
    bash "$script" "$GIT_WORKDIR"
}

# Config-set CLI: cloud-connect.sh config-set KEY VALUE
config_set() {
    local key="$1" value="$2"
    if [ -z "$key" ] || [ -z "$value" ]; then
        printf "${C_ERR}Usage: cloud-connect.sh config-set KEY VALUE${RST}\n\n"
        printf "${BLD}Available keys:${RST}\n"
        printf "  git_workdir       Git working directory\n"
        printf "  mount_dir         Mount base directory\n"
        printf "  sync_dir          Sync rules directory\n"
        printf "  rclone_opts       Rclone mount options\n"
        printf "  rclone_sync_opts  Rclone sync options\n"
        printf "  log_file          Log file name\n"
        printf "  merge_strategy    Git merge strategy (ours/theirs)\n\n"
        printf "${BLD}Current values:${RST}\n"
        printf "  git_workdir       = %s\n" "$GIT_WORKDIR"
        printf "  mount_dir         = %s\n" "$MOUNT_DIR"
        printf "  sync_dir          = %s\n" "$SYNC_DIR"
        printf "  rclone_opts       = %s\n" "$RCLONE_OPTS"
        printf "  rclone_sync_opts  = %s\n" "$RCLONE_SYNC_OPTS"
        printf "  log_file          = %s\n" "$LOG_FILE_NAME"
        printf "  merge_strategy    = %s\n" "$MERGE_STRATEGY"
        return 1
    fi
    case "$key" in
        git_workdir|mount_dir|sync_dir|rclone_opts|rclone_sync_opts|log_file|merge_strategy)
            update_setting "$key" "$value"
            printf "${C_OK}${S_OK}${RST} %s = %s\n" "$key" "$value"
            ;;
        *)
            printf "${C_ERR}Unknown setting: %s${RST}\n" "$key"
            printf "${C_DIM}Valid keys: git_workdir, mount_dir, sync_dir, rclone_opts, rclone_sync_opts, log_file, merge_strategy${RST}\n"
            return 1
            ;;
    esac
}

# =============================================================================
# CONFIG & SYSTEM MANAGEMENT (Group 4)
# =============================================================================

update_setting() {
    local key="$1" value="$2"
    local tmp; tmp=$(mktemp)
    jq --arg k "$key" --arg v "$value" '.settings[$k] = $v' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    log_msg "Setting updated: $key = $value"
}

settings_menu() {
    printf "\n${BLD}━━━ Settings ━━━${RST}\n\n"
    printf "  ${C_INFO}1${RST}  Git workdir:     ${C_OK}%s${RST}\n" "$GIT_WORKDIR"
    printf "  ${C_INFO}2${RST}  Mount directory:  ${C_OK}%s${RST}\n" "$MOUNT_DIR"
    printf "  ${C_INFO}3${RST}  Sync directory:   ${C_OK}%s${RST}\n" "$SYNC_DIR"
    printf "  ${C_INFO}4${RST}  Rclone mount opts:${C_OK}%s${RST}\n" "$RCLONE_OPTS"
    printf "  ${C_INFO}5${RST}  Rclone sync opts: ${C_OK}%s${RST}\n" "$RCLONE_SYNC_OPTS"
    printf "  ${C_INFO}6${RST}  Log file:         ${C_OK}%s${RST}\n" "$LOG_FILE_NAME"
    printf "  ${C_INFO}7${RST}  Merge strategy:   ${C_OK}%s${RST}\n" "$MERGE_STRATEGY"
    printf "\n"
    printf "  ${C_DIM}e${RST}  Edit config JSON  ${C_DIM}(%s)${RST}\n" "$CONFIG_FILE"
    printf "  ${C_DIM}0${RST}  Back\n"
    printf "\n${BLD}Choice:${RST} "
    read -r choice

    case "$choice" in
        1) edit_workdir ;;
        2)
            printf "\n${BLD}New mount directory:${RST} "
            read -r new_dir
            if [ -n "$new_dir" ]; then
                new_dir=$(eval echo "$new_dir")
                [ ! -d "$new_dir" ] && { printf "Create? [y/N] "; read -r c; case "$c" in [Yy]*) mkdir -p "$new_dir" ;; *) return ;; esac; }
                update_setting "mount_dir" "$new_dir"
                printf "${C_OK}${S_OK}${RST} Mount directory updated. Restart to apply.\n"
            fi ;;
        3)
            printf "\n${BLD}New sync directory:${RST} "
            read -r new_dir
            if [ -n "$new_dir" ]; then
                new_dir=$(eval echo "$new_dir")
                [ ! -d "$new_dir" ] && mkdir -p "$new_dir"
                update_setting "sync_dir" "$new_dir"
                printf "${C_OK}${S_OK}${RST} Sync directory updated. Restart to apply.\n"
            fi ;;
        4)
            printf "\n${BLD}Current:${RST} %s\n" "$RCLONE_OPTS"
            printf "${C_DIM}Common: --vfs-cache-mode off|minimal|writes|full${RST}\n"
            printf "${BLD}New rclone mount options:${RST} "
            read -r new_opts
            [ -n "$new_opts" ] && { update_setting "rclone_opts" "$new_opts"; printf "${C_OK}${S_OK}${RST} Updated. Restart to apply.\n"; }
            ;;
        5)
            printf "\n${BLD}Current:${RST} %s\n" "$RCLONE_SYNC_OPTS"
            printf "${BLD}New rclone sync options:${RST} "
            read -r new_opts
            [ -n "$new_opts" ] && { update_setting "rclone_sync_opts" "$new_opts"; printf "${C_OK}${S_OK}${RST} Updated. Restart to apply.\n"; }
            ;;
        6)
            printf "\n${BLD}New log file name:${RST} "
            read -r new_log
            [ -n "$new_log" ] && { update_setting "log_file" "$new_log"; printf "${C_OK}${S_OK}${RST} Updated. Restart to apply.\n"; }
            ;;
        7) git_toggle_merge ;;
        e|E) "${EDITOR:-vim}" "$CONFIG_FILE" ;;
        0) return ;;
        *) printf "${C_ERR}Invalid choice${RST}\n" ;;
    esac
}

create_rclone_remote() {
    local remote="$1" remote_type="$2"

    printf "\n${BLD}Creating rclone remote: %s${RST}\n" "$remote"

    case "$remote_type" in
        drive)
            printf "${C_WARN}This will open a browser for Google OAuth.${RST}\n"
            printf "Press Enter to continue or Ctrl+C to cancel..."
            read -r _
            rclone config create "$remote" drive scope=drive
            if rclone_remote_exists "$remote"; then
                printf "${C_OK}${S_OK}${RST} Remote '%s' created\n" "$remote"
                log_msg "Remote created: $remote"
                return 0
            else
                printf "${C_ERR}${S_FAIL}${RST} Failed to create '%s'\n" "$remote"
                return 1
            fi ;;
        sftp)
            printf "${BLD}SSH host:${RST} "
            read -r ssh_host
            printf "${BLD}SSH user:${RST} "
            read -r ssh_user
            printf "${BLD}SSH key path (empty for password):${RST} "
            read -r ssh_key
            if [ -n "$ssh_key" ]; then
                rclone config create "$remote" sftp host="$ssh_host" user="$ssh_user" key_file="$ssh_key"
            else
                rclone config create "$remote" sftp host="$ssh_host" user="$ssh_user"
            fi
            if rclone_remote_exists "$remote"; then
                printf "${C_OK}${S_OK}${RST} Remote '%s' created\n" "$remote"
                log_msg "Remote created: $remote"
                return 0
            else
                printf "${C_ERR}${S_FAIL}${RST} Failed to create '%s'\n" "$remote"
                return 1
            fi ;;
        *)
            printf "${C_ERR}Unknown remote type: %s${RST}\n" "$remote_type"
            return 1 ;;
    esac
}

prompt_create_remote() {
    local remote="$1"
    local remote_type
    case "$remote" in
        Gdrive_*) remote_type="drive" ;;
        OCI_*|GCP_*) remote_type="sftp" ;;
        *) remote_type="sftp" ;;
    esac

    printf "\n${C_WARN}Remote '%s' is not configured.${RST}\n" "$remote"
    printf "Create it now? [y/N] "
    read -r answer
    case "$answer" in
        [Yy]*) create_rclone_remote "$remote" "$remote_type"; return $? ;;
        *) printf "${C_DIM}Skipped${RST}\n"; return 1 ;;
    esac
}

configure_remote_menu() {
    printf "\n${BLD}━━━ Configure Rclone Remotes ━━━${RST}\n\n"
    printf "${C_DIM}Current remotes: %s${RST}\n\n" "$(rclone listremotes 2>/dev/null | tr '\n' ' ')"

    # Show drives status
    printf "  ${C_DRIVE}Drives:${RST}\n"
    local drive_count; drive_count=$(_jq '.drives | length')
    local d=0
    while [ "$d" -lt "$drive_count" ]; do
        local dremote; dremote=$(_jq -r ".drives[$d].remote")
        if rclone_remote_exists "$dremote"; then
            printf "    ${C_OK}${S_OK}${RST} %s (configured)\n" "$dremote"
        else
            printf "    ${C_ERR}${S_FAIL}${RST} %s (missing)\n" "$dremote"
        fi
        d=$((d+1))
    done

    # Show VMs status
    printf "\n  ${C_MESH}VMs (SFTP):${RST}\n"
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local v=0
    while [ "$v" -lt "$vm_count" ]; do
        local vremote; vremote=$(_jq -r ".mesh.vms[$v].remote")
        if rclone_remote_exists "$vremote"; then
            printf "    ${C_OK}${S_OK}${RST} %s (configured)\n" "$vremote"
        else
            printf "    ${C_ERR}${S_FAIL}${RST} %s (missing)\n" "$vremote"
        fi
        v=$((v+1))
    done

    printf "\n${BLD}Options:${RST}\n"
    # Build dynamic menu from config
    local idx=1
    local menu_items=""

    d=0
    while [ "$d" -lt "$drive_count" ]; do
        local dn; dn=$(_jq -r ".drives[$d].remote")
        printf "  ${C_INFO}%d${RST}) %s ${C_DIM}(drive)${RST}\n" "$idx" "$dn"
        menu_items="${menu_items}${idx}:drive:${dn}\n"
        idx=$((idx+1))
        d=$((d+1))
    done
    v=0
    while [ "$v" -lt "$vm_count" ]; do
        local vn; vn=$(_jq -r ".mesh.vms[$v].remote")
        printf "  ${C_INFO}%d${RST}) %s ${C_DIM}(sftp)${RST}\n" "$idx" "$vn"
        menu_items="${menu_items}${idx}:sftp:${vn}\n"
        idx=$((idx+1))
        v=$((v+1))
    done
    printf "  ${C_INFO}c${RST}) Custom remote\n"
    printf "  ${C_INFO}t${RST}) Run rclone config TUI\n"
    printf "  ${C_DIM}0${RST}) Cancel\n"
    printf "${BLD}Choice:${RST} "
    read -r ch

    case "$ch" in
        0) return ;;
        c|C)
            printf "${BLD}Remote name:${RST} "
            read -r rname
            printf "${BLD}Type (drive/sftp):${RST} "
            read -r rtype
            create_rclone_remote "$rname" "$rtype" ;;
        t|T) rclone config ;;
        *)
            local entry; entry=$(printf '%b' "$menu_items" | grep "^${ch}:")
            if [ -n "$entry" ]; then
                local rtype rname
                rtype=$(echo "$entry" | cut -d: -f2)
                rname=$(echo "$entry" | cut -d: -f3)
                create_rclone_remote "$rname" "$rtype"
            else
                printf "${C_ERR}Invalid choice${RST}\n"
            fi ;;
    esac
}

_detect_distro() {
    if [ -f /etc/os-release ]; then
        local id; id=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
        echo "$id"
    else
        echo "unknown"
    fi
}

_get_pkg_cmd() {
    local distro; distro=$(_detect_distro)
    case "$distro" in
        nixos)          echo "nix-env -iA nixpkgs." ;;
        arch|manjaro)   echo "sudo pacman -S --noconfirm " ;;
        debian|ubuntu|pop) echo "sudo apt install -y " ;;
        fedora)         echo "sudo dnf install -y " ;;
        alpine)         echo "sudo apk add " ;;
        *)              echo "" ;;
    esac
}

_dep_version() {
    local dep="$1"
    case "$dep" in
        git)              git --version 2>/dev/null | awk '{print $3}' ;;
        jq)               jq --version 2>/dev/null | sed 's/^jq-//' ;;
        rclone)           rclone version 2>/dev/null | head -1 | awk '{print $2}' ;;
        fusermount)       fusermount --version 2>/dev/null | awk '{print $NF}' ;;
        gh)               gh --version 2>/dev/null | head -1 | awk '{print $3}' ;;
        oci)              oci --version 2>/dev/null | awk '{print $3}' ;;
        gcloud)           gcloud --version 2>/dev/null | head -1 | awk '{print $NF}' ;;
        kdeconnect-cli)   kdeconnect-cli --version 2>/dev/null | awk '{print $NF}' ;;
        qdbus)            echo "system" ;;
        *)                echo "?" ;;
    esac
}

_dep_pkg_name() {
    local dep="$1" distro="$2"
    # Distro-specific package name mapping
    case "$dep" in
        fusermount)
            case "$distro" in
                nixos)          echo "fuse3" ;;
                arch|manjaro)   echo "fuse3" ;;
                debian|ubuntu|pop) echo "fuse3" ;;
                fedora)         echo "fuse3" ;;
                *)              echo "fuse3" ;;
            esac ;;
        kdeconnect-cli)
            case "$distro" in
                nixos)          echo "kdeconnect" ;;
                arch|manjaro)   echo "kdeconnect" ;;
                debian|ubuntu|pop) echo "kdeconnect" ;;
                *)              echo "kdeconnect" ;;
            esac ;;
        qdbus)
            case "$distro" in
                nixos)          echo "qt5.qttools" ;;
                arch|manjaro)   echo "qt5-tools" ;;
                debian|ubuntu|pop) echo "qttools5-dev-tools" ;;
                *)              echo "qdbus" ;;
            esac ;;
        gh)
            case "$distro" in
                nixos)          echo "gh" ;;
                debian|ubuntu|pop) echo "gh" ;;
                *)              echo "gh" ;;
            esac ;;
        *)  echo "$dep" ;;
    esac
}

deps_menu() {
    printf "\n${BLD}━━━ Dependencies ━━━${RST}\n\n"

    local distro; distro=$(_detect_distro)
    printf "  ${C_DIM}Distro:${RST} ${C_INFO}%s${RST}\n\n" "$distro"

    # Categorized deps
    local categories="Core Phone Cloud"
    local deps_core="git jq rclone fusermount"
    local deps_phone="kdeconnect-cli qdbus"
    local deps_cloud="oci gh gcloud"

    local missing_required=0 missing_optional=0

    for cat in $categories; do
        local deps_var="deps_$(echo "$cat" | tr '[:upper:]' '[:lower:]')"
        local deps_list="${!deps_var}"
        local cat_color="$C_INFO"
        local is_required="false"

        case "$cat" in
            Core)  cat_color="$C_OK"; is_required="true" ;;
            Phone) cat_color="$C_WARN" ;;
            Cloud) cat_color="$C_INFO" ;;
        esac

        printf "  %b${BLD}%s${RST}" "$cat_color" "$cat"
        [ "$is_required" = "true" ] && printf " ${C_DIM}(required)${RST}" || printf " ${C_DIM}(optional)${RST}"
        printf "\n"

        for dep in $deps_list; do
            if command -v "$dep" >/dev/null 2>&1; then
                local ver; ver=$(_dep_version "$dep")
                printf "    ${C_OK}${S_OK}${RST} %-20s ${C_DIM}%s${RST}\n" "$dep" "$ver"
            else
                local pkg; pkg=$(_dep_pkg_name "$dep" "$distro")
                if [ "$is_required" = "true" ]; then
                    printf "    ${C_ERR}${S_FAIL}${RST} %-20s ${C_DIM}(missing → %s)${RST}\n" "$dep" "$pkg"
                    missing_required=$((missing_required + 1))
                else
                    printf "    ${C_WARN}${S_STOP}${RST} %-20s ${C_DIM}(not installed → %s)${RST}\n" "$dep" "$pkg"
                    missing_optional=$((missing_optional + 1))
                fi
            fi
        done
        printf "\n"
    done

    printf "${BLD}Actions:${RST}\n"
    printf "  ${C_INFO}1${RST}) Install missing required deps"
    [ "$missing_required" -gt 0 ] && printf " ${C_WARN}(%d missing)${RST}" "$missing_required"
    printf "\n"
    printf "  ${C_INFO}2${RST}) Install all missing deps"
    local total_missing=$((missing_required + missing_optional))
    [ "$total_missing" -gt 0 ] && printf " ${C_WARN}(%d missing)${RST}" "$total_missing"
    printf "\n"
    printf "  ${C_DIM}0${RST}) Back\n"
    printf "${BLD}Choice:${RST} "
    read -r ch

    case "$ch" in
        1) install_deps_category "core" ;;
        2) install_deps_category "core"; install_deps_category "phone"; install_deps_category "cloud" ;;
        0) return ;;
        *) printf "${C_ERR}Invalid choice${RST}\n" ;;
    esac
}

install_dep() {
    local dep="$1"
    local distro; distro=$(_detect_distro)

    if command -v "$dep" >/dev/null 2>&1; then
        printf "${C_DIM}%s already installed${RST}\n" "$dep"
        return 0
    fi

    # Resolve distro-specific package name
    local pkg; pkg=$(_dep_pkg_name "$dep" "$distro")

    if [ "$distro" = "nixos" ]; then
        printf "${C_WARN}NixOS detected. Options:${RST}\n"
        local snippet="environment.systemPackages = [ pkgs.$pkg ];"
        printf "  ${C_INFO}1${RST}) Add to flake/configuration.nix: ${C_INFO}%s${RST}\n" "$snippet"
        printf "  ${C_INFO}2${RST}) Temporary shell: ${C_INFO}nix-shell -p %s${RST}\n" "$pkg"
        printf "  ${C_INFO}3${RST}) Install to user profile (nix-env, not recommended)\n"
        printf "  ${C_DIM}0${RST}) Skip\n"
        printf "${BLD}Choice [0]:${RST} "
        read -r answer
        case "$answer" in
            1)
                # Copy snippet to clipboard if possible
                if command -v wl-copy >/dev/null 2>&1; then
                    printf '%s' "$snippet" | wl-copy 2>/dev/null
                    printf "${C_OK}${S_OK}${RST} Copied to clipboard: %s\n" "$snippet"
                elif command -v xclip >/dev/null 2>&1; then
                    printf '%s' "$snippet" | xclip -selection clipboard 2>/dev/null
                    printf "${C_OK}${S_OK}${RST} Copied to clipboard: %s\n" "$snippet"
                else
                    printf "${C_INFO}Add this to configuration.nix:${RST} %s\n" "$snippet"
                fi
                return 0 ;;
            2) printf "${C_INFO}Run:${RST} nix-shell -p %s\n" "$pkg"; return 0 ;;
            3) nix-env -iA "nixpkgs.$pkg"; return $? ;;
            *) printf "${C_DIM}Skipped${RST}\n"; return 1 ;;
        esac
    fi

    # Arch: try AUR helpers if pacman fails
    if [ "$distro" = "arch" ] || [ "$distro" = "manjaro" ]; then
        if ! pacman -Si "$pkg" >/dev/null 2>&1; then
            local aur_helper=""
            command -v yay >/dev/null 2>&1 && aur_helper="yay"
            command -v paru >/dev/null 2>&1 && aur_helper="paru"
            if [ -n "$aur_helper" ]; then
                printf "${C_INFO}Installing %s from AUR via %s...${RST}\n" "$pkg" "$aur_helper"
                "$aur_helper" -S --noconfirm "$pkg"
                return $?
            else
                printf "${C_WARN}%s not in official repos. Install yay/paru for AUR.${RST}\n" "$pkg"
                return 1
            fi
        fi
    fi

    local pkg_cmd; pkg_cmd=$(_get_pkg_cmd)
    if [ -z "$pkg_cmd" ]; then
        printf "${C_ERR}Unknown distro. Install manually: %s${RST}\n" "$pkg"
        return 1
    fi

    printf "${C_INFO}Installing %s (package: %s)...${RST}\n" "$dep" "$pkg"
    # shellcheck disable=SC2086
    ${pkg_cmd}${pkg}
    return $?
}

install_deps_category() {
    local category="$1"
    local deps_list=""
    case "$category" in
        core)  deps_list="git jq rclone fusermount" ;;
        phone) deps_list="kdeconnect-cli qdbus" ;;
        cloud) deps_list="oci gh gcloud" ;;
        *)     printf "${C_ERR}Unknown category: %s${RST}\n" "$category"; return 1 ;;
    esac

    local distro; distro=$(_detect_distro)

    # NixOS batch mode: collect all missing and present as batch
    if [ "$distro" = "nixos" ]; then
        local missing_pkgs=""
        for dep in $deps_list; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                local pkg; pkg=$(_dep_pkg_name "$dep" "$distro")
                missing_pkgs="${missing_pkgs}${missing_pkgs:+ }${pkg}"
            fi
        done
        if [ -z "$missing_pkgs" ]; then
            printf "${C_OK}${S_OK}${RST} All %s deps installed\n" "$category"
            return 0
        fi
        printf "\n${C_WARN}NixOS — Missing %s packages:${RST} %s\n\n" "$category" "$missing_pkgs"
        printf "${BLD}How to install:${RST}\n"
        printf "  ${C_INFO}1${RST}) Open nix-shell with packages ${C_DIM}(temporary)${RST}\n"
        printf "  ${C_INFO}2${RST}) Copy configuration.nix snippet ${C_DIM}(persistent, recommended)${RST}\n"
        printf "  ${C_INFO}3${RST}) Install to user profile ${C_DIM}(nix-env, not recommended)${RST}\n"
        printf "  ${C_DIM}0${RST}) Skip\n"
        printf "${BLD}Choice [0]:${RST} "
        read -r ch
        case "$ch" in
            1)
                printf "\n${C_INFO}Run:${RST} nix-shell -p %s\n" "$missing_pkgs"
                printf "${C_DIM}Or:${RST}  nix-shell -p %s --run '%s'\n" "$missing_pkgs" "$0"
                printf "\nOpen nix-shell now? [y/N] "
                read -r yn
                case "$yn" in
                    [Yy]*) nix-shell -p $missing_pkgs ;;
                    *) printf "${C_DIM}Skipped${RST}\n" ;;
                esac ;;
            2)
                local snippet="environment.systemPackages = with pkgs; ["
                for pkg in $missing_pkgs; do snippet="$snippet $pkg"; done
                snippet="$snippet ];"
                printf "\n${C_INFO}Add to configuration.nix:${RST}\n  %s\n" "$snippet"
                if command -v wl-copy >/dev/null 2>&1; then
                    printf '%s' "$snippet" | wl-copy 2>/dev/null
                    printf "${C_OK}${S_OK}${RST} Copied to clipboard (wl-copy)\n"
                elif command -v xclip >/dev/null 2>&1; then
                    printf '%s' "$snippet" | xclip -selection clipboard 2>/dev/null
                    printf "${C_OK}${S_OK}${RST} Copied to clipboard (xclip)\n"
                fi ;;
            3)
                for pkg in $missing_pkgs; do
                    printf "${C_INFO}Installing %s...${RST}\n" "$pkg"
                    nix-env -iA "nixpkgs.$pkg" || true
                done ;;
            *) printf "${C_DIM}Skipped${RST}\n" ;;
        esac
        return 0
    fi

    # Non-NixOS: install one by one
    local missing=0
    for dep in $deps_list; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            install_dep "$dep"
            missing=$((missing+1))
        fi
    done
    [ "$missing" -eq 0 ] && printf "${C_OK}${S_OK}${RST} All %s deps installed\n" "$category"
}

install_all_deps() {
    local scope="${1:-required}"
    local deps

    if [ "$scope" = "all" ]; then
        deps=$(_jq -r '(.dependencies.required[], .dependencies.optional[])')
    else
        deps=$(_jq -r '.dependencies.required[]')
    fi

    local missing=0
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        if ! command -v "$dep" >/dev/null 2>&1; then
            install_dep "$dep"
            missing=$((missing+1))
        fi
    done <<< "$deps"

    [ "$missing" -eq 0 ] && printf "${C_OK}${S_OK}${RST} All dependencies installed\n"
}

clear_log() {
    if [ -f "$LOG_FILE" ]; then
        : > "$LOG_FILE"
        printf "${C_OK}${S_OK}${RST} Log cleared\n"
        log_msg "Log cleared"
    else
        printf "${C_DIM}No log file${RST}\n"
    fi
}

view_log() {
    if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
        printf "${C_DIM}Log is empty${RST}\n"
        return
    fi

    # Log info header
    local fsize line_count err_count warn_count
    fsize=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null)
    err_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
    warn_count=$(grep -c "WARN" "$LOG_FILE" 2>/dev/null || echo 0)

    printf "\n${BLD}━━━ Log (%s) ━━━${RST}\n" "$LOG_FILE"
    printf "  ${C_DIM}Size: %s | Lines: %s | Errors: ${RST}" "$fsize" "$line_count"
    [ "$err_count" -gt 0 ] && printf "${C_ERR}%s${RST}" "$err_count" || printf "${C_OK}%s${RST}" "$err_count"
    printf " ${C_DIM}| Warnings: ${RST}"
    [ "$warn_count" -gt 0 ] && printf "${C_WARN}%s${RST}" "$warn_count" || printf "${C_OK}%s${RST}" "$warn_count"
    printf "\n\n"

    tail -30 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -q "ERROR"; then
            printf "  ${C_ERR}%s${RST}\n" "$line"
        elif echo "$line" | grep -q "WARN"; then
            printf "  ${C_WARN}%s${RST}\n" "$line"
        else
            printf "  ${C_DIM}%s${RST}\n" "$line"
        fi
    done
}

edit_workdir() {
    local local_dir; local_dir=$(pwd)

    printf "\n${BLD}=== Edit Git Working Directory ===${RST}\n\n"
    printf "  Current:  ${C_INFO}%s${RST}\n" "$GIT_WORKDIR"
    printf "  Local:    ${C_DIM}%s${RST}\n\n" "$local_dir"

    printf "  ${C_INFO}1${RST}) Use current directory (%s)\n" "$local_dir"
    printf "  ${C_INFO}2${RST}) Enter custom path\n"
    printf "  ${C_DIM}0${RST}) Cancel\n"
    printf "\n${BLD}Choice [1]:${RST} "
    read -r choice
    choice="${choice:-1}"

    local new_path
    case "$choice" in
        1) new_path="$local_dir" ;;
        2)
            printf "\n${BLD}Enter path:${RST} "
            read -r new_path
            [ -z "$new_path" ] && { printf "${C_DIM}Cancelled${RST}\n"; return; }
            new_path=$(echo "$new_path" | sed "s|^~|$HOME|")
            ;;
        0) return ;;
        *) printf "${C_ERR}Invalid choice${RST}\n"; return ;;
    esac

    if [ ! -d "$new_path" ]; then
        printf "${C_WARN}Directory does not exist: %s${RST}\n" "$new_path"
        printf "Create it? [y/N] "
        read -r create
        case "$create" in
            [Yy]*) mkdir -p "$new_path" || { printf "${C_ERR}Failed to create directory${RST}\n"; return; } ;;
            *) printf "${C_DIM}Cancelled${RST}\n"; return ;;
        esac
    fi

    update_setting "git_workdir" "$new_path"
    GIT_WORKDIR="$new_path"
    printf "${C_OK}${S_OK}${RST} Git workdir updated to: %s\n" "$new_path"
}

edit_config() {
    "${EDITOR:-vim}" "$CONFIG_FILE"
    printf "${C_WARN}Restart to apply changes${RST}\n"
}

# =============================================================================
# E) SERVERS - Rclone serve
# =============================================================================

render_servers() {
    printf "  ${BLD}%-17s %-8s %-6s %-30s %-8s %-7s Clients  Up${RST}\n" \
        "RCLONE SERVE" "Type" "Port" "Root Path" "Auth" "State"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local srv_count; srv_count=$(_jq '.servers | length')
    local s=0
    while [ "$s" -lt "$srv_count" ]; do
        local sname stype sport sroot sauth
        sname=$(_jq -r ".servers[$s].name")
        stype=$(_jq -r ".servers[$s].type")
        sport=$(_jq -r ".servers[$s].port")
        sroot=$(_jq -r ".servers[$s].root" | sed "s|\$HOME|$HOME|;s|~|$HOME|")
        sauth=$(_jq -r ".servers[$s].auth // \"none\"")

        # Check if actually running
        local is_running="false"
        if pgrep -f "rclone serve.*$sport" >/dev/null 2>&1; then
            is_running="true"
        fi

        if [ "$is_running" = "true" ]; then
            printf "  %-17s %-8s %-6s %-30s %-8s ${C_OK}${S_RUN} RUN${RST}   ?        ?\n" \
                "$sname" "$stype" "$sport" "${sroot:0:30}" "$sauth"
        else
            printf "  %-17s %-8s %-6s %-30s %-8s ${C_DIM}${S_STOP} STOP${RST}  —        —\n" \
                "$sname" "$stype" "$sport" "${sroot:0:30}" "$sauth"
        fi
        s=$((s+1))
    done

    if [ "$srv_count" -eq 0 ]; then printf "  ${C_DIM}No servers configured${RST}\n"; fi
}

server_start() {
    local srv_count; srv_count=$(_jq '.servers | length')
    [ "$srv_count" -eq 0 ] && { printf "${C_WARN}No servers configured${RST}\n"; return; }

    printf "\n${BLD}Select server to start:${RST}\n"
    local s=0
    while [ "$s" -lt "$srv_count" ]; do
        local sname sport; sname=$(_jq -r ".servers[$s].name"); sport=$(_jq -r ".servers[$s].port")
        printf "  ${C_INFO}%d${RST}) %s (:%s)\n" "$((s+1))" "$sname" "$sport"
        s=$((s+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return

    local idx=$((ch-1))
    local stype sport sroot sauth
    stype=$(_jq -r ".servers[$idx].type")
    sport=$(_jq -r ".servers[$idx].port")
    sroot=$(_jq -r ".servers[$idx].root" | sed "s|\$HOME|$HOME|;s|~|$HOME|")
    sauth=$(_jq -r ".servers[$idx].auth // \"none\"")

    local cmd="rclone serve $stype '$sroot' --addr :$sport"
    [ "$sauth" = "basic" ] && cmd="$cmd --user admin --pass admin"

    printf "${C_INFO}[+]${RST} Starting: %s\n" "$cmd"
    eval "nohup $cmd >/dev/null 2>&1 &"
    printf "${C_OK}${S_OK}${RST} Server started on port %s\n" "$sport"
}

server_stop() {
    local srv_count; srv_count=$(_jq '.servers | length')
    printf "\n${BLD}Select server to stop:${RST}\n"
    local s=0
    while [ "$s" -lt "$srv_count" ]; do
        local sname sport; sname=$(_jq -r ".servers[$s].name"); sport=$(_jq -r ".servers[$s].port")
        printf "  ${C_INFO}%d${RST}) %s (:%s)\n" "$((s+1))" "$sname" "$sport"
        s=$((s+1))
    done
    printf "  ${C_DIM}0${RST}) Cancel\n${BLD}Choice:${RST} "
    read -r ch
    [ "$ch" = "0" ] || [ -z "$ch" ] && return

    local idx=$((ch-1))
    local sport; sport=$(_jq -r ".servers[$idx].port")
    pkill -f "rclone serve.*$sport" 2>/dev/null && \
        printf "${C_OK}${S_OK}${RST} Stopped\n" || \
        printf "${C_WARN}Not running${RST}\n"
}

# =============================================================================
# F) WEBSERVER - Dev servers detection
# =============================================================================

render_webservers() {
    printf "  ${BLD}%-17s %-6s %-10s %-12s %-26s %-8s %-7s State${RST}\n" \
        "DEV SERVER" "Port" "Runtime" "Framework" "Project" "PID" "Up"
    printf "  ${C_DIM}"
    local w=0; while [ "$w" -lt 99 ]; do printf "─"; w=$((w+1)); done
    printf "${RST}\n"

    local found=0

    # Detect node dev servers
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        found=1
        local pid port cmd cwd
        pid=$(echo "$line" | awk '{print $1}')
        # Get the listening port
        port=$(ss -tlnp 2>/dev/null | grep "pid=$pid" | grep -oP ':\K\d+' | head -1 || echo "?")
        # Get command and cwd
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c40 || echo "?")
        cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || echo "?")
        local proj
        proj=$(echo "$cwd" | sed "s|$HOME/Mounts/Git/||;s|$HOME/||" | head -c26)

        # Detect framework
        local fw="node"
        echo "$cmd" | grep -qi "vite" && fw="Vite"
        echo "$cmd" | grep -qi "svelte" && fw="SvelteKit"
        echo "$cmd" | grep -qi "next" && fw="Next.js"
        echo "$cmd" | grep -qi "astro" && fw="Astro"

        # Uptime
        local up_s; up_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
        local up_str
        if [ "$up_s" -lt 3600 ] 2>/dev/null; then
            up_str="$((up_s / 60))m"
        else
            up_str="$((up_s / 3600))h"
        fi

        printf "  %-17s %-6s %-10s %-12s %-26s %-8s %-7s ${C_OK}${S_RUN} RUN${RST}\n" \
            "node" "$port" "Node" "$fw" "$proj" "$pid" "$up_str"
    done < <(pgrep -f "node.*dev\|node.*serve\|vite\|next.*dev" 2>/dev/null || true)

    # Detect python dev servers
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        found=1
        local pid port cmd cwd
        pid=$(echo "$line" | awk '{print $1}')
        port=$(ss -tlnp 2>/dev/null | grep "pid=$pid" | grep -oP ':\K\d+' | head -1 || echo "?")
        cmd=$(ps -o args= -p "$pid" 2>/dev/null | head -c40 || echo "?")
        cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || echo "?")
        local proj
        proj=$(echo "$cwd" | sed "s|$HOME/Mounts/Git/||;s|$HOME/||" | head -c26)

        local fw="python"
        echo "$cmd" | grep -qi "flask" && fw="Flask"
        echo "$cmd" | grep -qi "uvicorn\|fastapi" && fw="FastAPI"
        echo "$cmd" | grep -qi "django" && fw="Django"

        local up_s; up_s=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || echo 0)
        local up_str
        if [ "$up_s" -lt 3600 ] 2>/dev/null; then
            up_str="$((up_s / 60))m"
        else
            up_str="$((up_s / 3600))h"
        fi

        printf "  %-17s %-6s %-10s %-12s %-26s %-8s %-7s ${C_OK}${S_RUN} RUN${RST}\n" \
            "python" "$port" "Python" "$fw" "$proj" "$pid" "$up_str"
    done < <(pgrep -f "python.*-m\|uvicorn\|flask\|gunicorn" 2>/dev/null || true)

    # Static entries from config
    local ws_count; ws_count=$(_jq '.webservers | length')
    if [ "$ws_count" -gt 0 ]; then
        local ws=0
        while [ "$ws" -lt "$ws_count" ]; do
            # future: static config entries
            ws=$((ws+1))
        done
    fi

    if [ "$found" -eq 0 ] && [ "$ws_count" -eq 0 ]; then printf "  ${C_DIM}No dev servers running${RST}\n"; fi
}

# =============================================================================
# SUMMARY GAUGES
# =============================================================================

compute_gauges() {
    # MESH: % of VMs reachable (quick check: mounted subdirs > 0 means was recently reachable)
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local vm_up=0
    local v=0
    while [ "$v" -lt "$vm_count" ]; do
        local name; name=$(_jq -r ".mesh.vms[$v].name")
        for sub in sys home docker mnt; do
            if is_mounted "$MOUNT_DIR/$name/$sub"; then
                vm_up=$((vm_up + 1))
                break
            fi
        done
        v=$((v+1))
    done
    GAUGE_MESH_CUR=$vm_up
    GAUGE_MESH_MAX=$vm_count

    # GIT: % of cloned repos that are clean
    local repos; repos=$(git_get_repos)
    local cloned=0 clean=0
    while IFS= read -r rname; do
        [ -z "$rname" ] && continue
        local dir="$GIT_WORKDIR/$rname"
        if [ -d "$dir/.git" ]; then
            cloned=$((cloned+1))
            local dirty; dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            [ "$dirty" -eq 0 ] && clean=$((clean+1))
        fi
    done <<< "$repos"
    GAUGE_GIT_CUR=$clean
    GAUGE_GIT_MAX=$cloned

    # DRIVES: % of drives + VM mounts active
    local drive_count; drive_count=$(_jq '.drives | length')
    local drive_up=0
    local d=0
    while [ "$d" -lt "$drive_count" ]; do
        local dname; dname=$(_jq -r ".drives[$d].name")
        is_mounted "$MOUNT_DIR/$dname" && drive_up=$((drive_up+1))
        d=$((d+1))
    done
    local total_mounts=$((drive_count + vm_count))
    GAUGE_DRIVE_CUR=$((drive_up + vm_up))
    GAUGE_DRIVE_MAX=$total_mounts

    # SYNC: % of enabled rules that ran recently (< 24h)
    local rules; rules=$(sync_list_rules)
    local enabled_count; enabled_count=$(echo "$rules" | jq '[.[] | select(.enabled == true)] | length')
    local recent=0
    if [ "$enabled_count" -gt 0 ]; then
        local now_epoch; now_epoch=$(date +%s)
        while IFS= read -r lr; do
            [ "$lr" = "null" ] || [ "$lr" = "never" ] || [ -z "$lr" ] && continue
            local lr_epoch; lr_epoch=$(date -d "$lr" +%s 2>/dev/null || echo 0)
            local diff=$(( now_epoch - lr_epoch ))
            [ "$diff" -lt 86400 ] && recent=$((recent+1))
        done < <(echo "$rules" | jq -r '.[] | select(.enabled == true) | .last_run // "never"')
    fi
    GAUGE_SYNC_CUR=$recent
    GAUGE_SYNC_MAX=$enabled_count
}

# =============================================================================
# ALERT STRIP
# =============================================================================

render_alerts() {
    local alerts=""

    # VM alerts
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local vm_down=0
    local v=0
    while [ "$v" -lt "$vm_count" ]; do
        local name; name=$(_jq -r ".mesh.vms[$v].name")
        local any_mounted=false
        for sub in sys home docker mnt; do
            is_mounted "$MOUNT_DIR/$name/$sub" && any_mounted=true && break
        done
        [ "$any_mounted" = "false" ] && vm_down=$((vm_down+1))
        v=$((v+1))
    done
    [ "$vm_down" -gt 0 ] && alerts="${alerts}  ${C_ALERT}${S_WARN} ${vm_down} VMs unmounted${RST}"

    # Dirty repos
    local repos; repos=$(git_get_repos)
    local dirty_count=0
    while IFS= read -r rname; do
        [ -z "$rname" ] && continue
        local dir="$GIT_WORKDIR/$rname"
        [ -d "$dir/.git" ] || continue
        local d; d=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        [ "$d" -gt 0 ] 2>/dev/null && dirty_count=$((dirty_count+1))
    done <<< "$repos"
    [ "$dirty_count" -gt 0 ] && alerts="${alerts}  ${C_WARN}${S_WARN} ${dirty_count} repos dirty${RST}"

    # Drive alerts
    local drive_count; drive_count=$(_jq '.drives | length')
    local drive_down=0
    local d=0
    while [ "$d" -lt "$drive_count" ]; do
        local dname; dname=$(_jq -r ".drives[$d].name")
        is_mounted "$MOUNT_DIR/$dname" || drive_down=$((drive_down+1))
        d=$((d+1))
    done
    [ "$drive_down" -gt 0 ] && alerts="${alerts}  ${C_ALERT}${S_WARN} ${drive_down} drives unmounted${RST}"

    # Sync alerts
    local running; running=$(sync_get_running_jobs)
    local run_count; run_count=$(echo "$running" | jq 'length')
    [ "$run_count" -gt 0 ] && alerts="${alerts}  ${C_OK}${S_DOT} ${run_count} sync running${RST}"

    printf "%b" "$alerts"
}

# =============================================================================
# MAIN DASHBOARD RENDER
# =============================================================================

render_dashboard() {
    local mode="${1:-print}"  # "print" = one-shot, "interactive" = loop
    if [ "$mode" = "interactive" ]; then clear; fi

    # Compute gauges
    compute_gauges

    # ── Header ──
    local hostname_str="${HM_PROFILE:-$(hostname 2>/dev/null || echo 'unknown')}"
    local date_str; date_str=$(date '+%a %d %b  %H:%M')

    printf "%b%b" "$BG_HEAD" "$C_HEAD"
    printf "┏"
    local w=0; while [ "$w" -lt 100 ]; do printf "━"; w=$((w+1)); done
    printf "┓\n"
    printf "┃  ◆ CLOUD CONNECT%65s%18s  ┃\n" "diego@${hostname_str}" "$date_str"
    local wd_short; wd_short=$(echo "$GIT_WORKDIR" | sed "s|$HOME|~|")
    local md_short; md_short=$(echo "$MOUNT_DIR" | sed "s|$HOME|~|")
    local merge_label="SERVER"
    [ "$MERGE_STRATEGY" = "ours" ] && merge_label="LOCAL"
    printf "┃  Git: %-28s  Mounts: %-26s  Merge: %-18s  ┃\n" "$wd_short" "$md_short" "$merge_label ($MERGE_STRATEGY)"
    printf "┗"
    w=0; while [ "$w" -lt 100 ]; do printf "━"; w=$((w+1)); done
    printf "┛%b\n" "$RST"

    # ── Gauge Strip ──
    printf "  ${C_MESH}MESH${RST} "
    gauge_bar "$GAUGE_MESH_CUR" "$GAUGE_MESH_MAX" 12
    printf " ${C_DIM}%s/%s${RST}" "$GAUGE_MESH_CUR" "$GAUGE_MESH_MAX"
    printf "  ${C_GIT}GIT${RST} "
    gauge_bar "$GAUGE_GIT_CUR" "$GAUGE_GIT_MAX" 12
    printf " ${C_DIM}%s/%s${RST}" "$GAUGE_GIT_CUR" "$GAUGE_GIT_MAX"
    printf "  ${C_DRIVE}DRIVES${RST} "
    gauge_bar "$GAUGE_DRIVE_CUR" "$GAUGE_DRIVE_MAX" 10
    printf " ${C_DIM}%s/%s${RST}" "$GAUGE_DRIVE_CUR" "$GAUGE_DRIVE_MAX"
    printf "  ${C_SYNC}SYNC${RST} "
    gauge_bar "$GAUGE_SYNC_CUR" "$GAUGE_SYNC_MAX" 6
    printf " ${C_DIM}%s/%s${RST}" "$GAUGE_SYNC_CUR" "$GAUGE_SYNC_MAX"

    # Running jobs count
    local rj; rj=$(sync_get_running_jobs 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    [ "$rj" -gt 0 ] && printf "  ${C_OK}${S_PLAY} %s jobs${RST}" "$rj"
    printf "\n"

    # ── Alert Strip ──
    render_alerts
    printf "\n"

    # ── A) MESH ──
    printf "\n%b━━ A) MESH ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$C_MESH" "$RST"
    render_mesh

    # ── B) GIT ──
    printf "\n%b━━ B) GIT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$C_GIT" "$RST"
    render_git

    # ── C) DRIVES ──
    printf "\n%b━━ C) DRIVES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$C_DRIVE" "$RST"
    render_drives

    # ── D) SYNC ──
    printf "\n%b━━ D) SYNC ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$C_SYNC" "$RST"
    render_sync

    # ── E) SERVERS ──
    printf "\n%b━━ E) SERVERS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$C_SRVR" "$RST"
    render_servers

    # ── F) WEBSERVER ──
    printf "\n%b━━ F) WEBSERVER ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$C_WEB" "$RST"
    render_webservers

    # ── Log ──
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        local log_size log_lines log_errs log_warns
        log_size=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null)
        log_errs=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
        log_warns=$(grep -c "WARN" "$LOG_FILE" 2>/dev/null || echo 0)
        printf "\n  ${C_DIM}Log: %s | %s lines | " "$log_size" "$log_lines"
        [ "$log_errs" -gt 0 ] && printf "${C_ERR}%s errors${RST}${C_DIM}" "$log_errs" || printf "0 errors"
        printf " | "
        [ "$log_warns" -gt 0 ] && printf "${C_WARN}%s warnings${RST}" "$log_warns" || printf "0 warnings"
        printf "${RST}\n"
    fi

    # ── Commands ──
    printf "\n%b━━ COMMANDS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n" "$BLD" "$RST"
    printf "  ${C_GIT}GIT${RST}    ${C_DIM}sync  pull  push  commit  fetch  fetch-status  clone  dirty  git-notok  git-refresh${RST}\n"
    printf "  ${C_GIT}   ${RST}    ${C_DIM}untracked  unstaged  ignored  merge  restore-symlinks  git-remotes  git-branches  git-tags${RST}\n"
    printf "  ${C_GIT}   ${RST}    ${C_DIM}git-log  git-stash-list  git-diff  git-gc  git-prune${RST}\n"
    printf "  ${C_MESH}MESH${RST}   ${C_DIM}mount-vm  unmount-vm  mount-all-vm  unmount-all  mount-phone  unmount-phone${RST}\n"
    printf "  ${C_MESH}OCI${RST}    ${C_DIM}flex-start  flex-stop  flex-reset  flex-status${RST}\n"
    printf "  ${C_DRIVE}DRIVE${RST}  ${C_DIM}mount-drive  unmount-drive  mount-all-drives  unmount-all-drives  toggle-drives${RST}\n"
    printf "  ${C_SYNC}SYNC${RST}   ${C_DIM}sync-run  sync-run-bg  sync-run-rule  sync-to  bisync-to  sync-quick  sync-status  sync-list${RST}\n"
    printf "  ${C_SYNC}    ${RST}   ${C_DIM}sync-add  sync-delete  sync-toggle  sync-edit  sync-jobs  sync-cancel  sync-cancel-id  sync-kill  sync-clear-jobs${RST}\n"
    printf "  ${C_SRVR}SRVR${RST}   ${C_DIM}server-start  server-stop${RST}\n"
    printf "  ${C_DIM}SETUP${RST}  ${C_DIM}settings  config-set  deps  deps-core  deps-phone  deps-cloud  remotes  view-log  clear-log  edit-workdir  edit-config${RST}\n"
    printf "  ${C_DIM}────${RST}   ${C_DIM}refresh  detail  compact  help  quit${RST}\n"
    printf "%b" "$BLD"
    w=0; while [ "$w" -lt 102 ]; do printf "━"; w=$((w+1)); done
    printf "%b\n" "$RST"
    printf "▸ "
}

# =============================================================================
# INTERACTIVE LOOP (CLI-first: type command + Enter)
# =============================================================================

_dispatch_cmd() {
    local cmd="$1"
    case "$cmd" in
        # ── Git ──
        sync)                git_cmd_sync ;;
        pull)                git_cmd_pull ;;
        push)                git_cmd_push ;;
        commit)              git_cmd_commit ;;
        fetch)               git_cmd_fetch ;;
        fetch-status)        git_cmd_fetch_status ;;
        clone)               git_cmd_clone_menu ;;
        untracked)           git_cmd_untracked ;;
        unstaged)            git_cmd_unstaged ;;
        ignored)             git_cmd_ignored ;;
        workdir)             edit_workdir ;;
        merge)               git_toggle_merge ;;
        status)              render_git ;;

        # ── Mesh (VM mounts) ──
        mount-vm)            select_and_mount_vm ;;
        unmount-vm)          select_and_unmount_vm ;;
        mount-all-vm)        _mount_all_vms ;;
        unmount-all)         _unmount_all_vms; _unmount_all_drives; unmount_phone ;;
        mount-phone)         mount_phone ;;
        unmount-phone)       unmount_phone ;;

        # ── OCI Flex ──
        flex-start)          flex_select_and_action "start" ;;
        flex-stop)           flex_select_and_action "stop" ;;
        flex-reset)          flex_select_and_action "reset" ;;
        flex-status)         flex_select_and_action "status" ;;

        # ── Drives ──
        mount-drive)         select_and_mount_drive ;;
        unmount-drive)       select_and_unmount_drive ;;
        mount-all-drives)    _mount_all_drives ;;
        unmount-all-drives)  _unmount_all_drives ;;
        toggle-drives)       _toggle_all_drives ;;

        # ── Sync ──
        sync-run)            sync_run_all ;;
        sync-add)            sync_add_rule_wizard ;;
        sync-delete)         sync_delete_rule ;;
        sync-toggle)         sync_toggle_rule ;;
        sync-quick)          sync_quick_menu ;;
        sync-edit)           sync_edit_rules ;;
        sync-jobs)           sync_show_jobs ;;
        sync-cancel)         sync_cancel_job ;;
        sync-kill)           sync_kill_all ;;
        sync-clear-jobs)     sync_clear_completed ;;

        # ── Servers ──
        server-start)        server_start ;;
        server-stop)         server_stop ;;

        # ── Sync (extra) ──
        sync-run-rule)       sync_run_rule_interactive ;;
        sync-list)           sync_list_cli ;;
        sync-run-bg)         sync_run_all_bg ;;
        sync-to)             printf "Source: "; read -r _src; printf "Dest: "; read -r _dst; sync_adhoc "$_src" "$_dst" ;;
        bisync-to)           printf "Path 1: "; read -r _p1; printf "Path 2: "; read -r _p2; bisync_adhoc "$_p1" "$_p2" ;;
        sync-cancel-id)      printf "Job ID: "; read -r _jid; sync_cancel_by_id "$_jid" ;;
        sync-status)         sync_full_status ;;
        dirty)               git_cmd_dirty ;;

        # ── Git (extra) ──
        restore-symlinks)    restore_symlinks ;;
        git-refresh)         render_git ;;
        git-notok)           git_cmd_dirty ;;
        git-remotes)         git_cmd_remotes ;;
        git-branches)        git_cmd_branches ;;
        git-tags)            git_cmd_tags ;;
        git-log)             git_cmd_log ;;
        git-stash-list)      git_cmd_stash_list ;;
        git-diff)            git_cmd_diff ;;
        git-gc)              git_cmd_gc ;;
        git-prune)           git_cmd_prune ;;

        # ── View modes ──
        compact)             _compact_view ;;

        # ── Setup ──
        settings)            settings_menu ;;
        deps)                deps_menu ;;
        deps-core)           install_deps_category "core" ;;
        deps-phone)          install_deps_category "phone" ;;
        deps-cloud)          install_deps_category "cloud" ;;
        remotes)             configure_remote_menu ;;
        edit-workdir)        edit_workdir ;;
        clear-log)           clear_log ;;
        view-log|log)        view_log ;;
        edit-config)         edit_config ;;
        config-set)          printf "Key: "; read -r _ck; printf "Value: "; read -r _cv; config_set "$_ck" "$_cv" ;;

        # ── Global ──
        refresh|r)           return 0 ;;
        detail)              _detail_view ;;
        help|h|\?)           show_help ;;
        quit|q|exit)         printf "\n"; exit 0 ;;
        "")                  return 0 ;;  # Empty input = refresh

        *)  printf "${C_ERR}Unknown command: %s${RST}  (type ${BLD}help${RST} for commands)\n" "$cmd" ;;
    esac
}

run_interactive() {
    while true; do
        render_dashboard "interactive"
        read -r cmd || exit 0
        printf "\n"
        _dispatch_cmd "$cmd"
    done
}

run_tui() {
    run_interactive
}

# =============================================================================
# CLI INTERFACE
# =============================================================================

show_help() {
    printf "${BLD}cloud-connect - Unified Command Center${RST}\n"
    printf "${C_DIM}Manage git repos, VM/drive mounts, sync rules, and cloud infrastructure from one dashboard${RST}\n\n"

    printf "${BLD}Usage:${RST}\n"
    printf "  ./cloud-connect.sh              ${C_DIM}# Interactive dashboard (default)${RST}\n"
    printf "  ./cloud-connect.sh <command>    ${C_DIM}# Run a specific action${RST}\n"
    printf "  ./cloud-connect.sh --help       ${C_DIM}# Show this help${RST}\n\n"

    printf "${BLD}Dashboard Views (4):${RST}\n"
    printf "  (no args)          Full dashboard with all 6 sections (MESH/GIT/DRIVES/SYNC/SERVERS/WEBSERVER)\n"
    printf "  tui                Interactive TUI (type commands + Enter)\n"
    printf "  detail             Verbose status (all sections + log tail)\n"
    printf "  compact            One-liner-per-section summary\n\n"
    printf "${BLD}Git (23 commands):${RST}\n"
    printf "  git-status         Show git repo table with dual local/remote status, auth, branches\n"
    printf "  git-sync           Commit+pull+push all\n"
    printf "  git-pull           Pull all repos\n"
    printf "  git-push           Push all repos\n"
    printf "  git-commit         Commit all dirty repos\n"
    printf "  git-fetch          Fetch all repos (parallel)\n"
    printf "  git-fetch-status   Parallel fetch + show status table\n"
    printf "  git-clone          Clone menu (multi-select)\n"
    printf "  git-untracked      List untracked files\n"
    printf "  git-unstaged       List unstaged changes\n"
    printf "  git-ignored        List ignored files\n"
    printf "  git-dirty          Show only repos with issues (dirty/behind/ahead)\n"
    printf "  git-notok          Same as git-dirty (select-not-OK filter)\n"
    printf "  git-refresh        Fast local-only git status table\n"
    printf "  git-remotes        Show all remotes for all repos\n"
    printf "  git-branches       Show all branches for all repos\n"
    printf "  git-tags           Show all tags for all repos\n"
    printf "  git-log            Show last 10 commits per repo\n"
    printf "  git-stash-list     Show all stashes across repos\n"
    printf "  git-diff           Show unstaged changes (diff --stat)\n"
    printf "  git-gc             Run garbage collection on all repos\n"
    printf "  git-prune          Prune unreachable objects (requires confirmation)\n"
    printf "  git-workdir        Show git working directory\n"
    printf "  git-merge          Toggle merge strategy (ours/theirs)\n"
    printf "  restore-symlinks   Restore 0.spec symlinks in git workdir\n\n"
    printf "${BLD}Mesh - VM Mounts (6 commands):${RST}\n"
    printf "  mount-vm [NAME]    Mount single VM (interactive if no NAME)\n"
    printf "  unmount-vm [NAME]  Unmount single VM (interactive if no NAME)\n"
    printf "  mount-all-vm       Mount all VMs\n"
    printf "  unmount-all        Unmount ALL (VMs + Drives + Phone)\n"
    printf "  mount-phone        Mount phone via KDE Connect\n"
    printf "  unmount-phone      Unmount phone\n\n"
    printf "${BLD}OCI Flex (4 commands):${RST}\n"
    printf "  flex-start [NAME]  Start OCI Flex VM\n"
    printf "  flex-stop [NAME]   Stop OCI Flex VM\n"
    printf "  flex-reset [NAME]  Reset OCI Flex VM\n"
    printf "  flex-status [NAME] Show OCI Flex VM status\n\n"
    printf "${BLD}Drives - Rclone Mounts (5 commands):${RST}\n"
    printf "  mount-drive [NAME]   Mount a cloud drive (interactive if no NAME)\n"
    printf "  unmount-drive [NAME] Unmount a cloud drive (interactive if no NAME)\n"
    printf "  mount-all-drives     Mount all drives\n"
    printf "  unmount-all-drives   Unmount all drives\n"
    printf "  toggle-drives        Toggle all drives (mount unmounted, unmount mounted)\n\n"
    printf "${BLD}Sync - Rclone Sync/Bisync (17 commands):${RST}\n"
    printf "  sync-run           Run all enabled sync rules\n"
    printf "  sync-add           Add a new sync rule (wizard)\n"
    printf "  sync-delete        Delete a sync rule\n"
    printf "  sync-toggle        Enable/disable a sync rule\n"
    printf "  sync-quick         One-time sync without saving a rule\n"
    printf "  sync-edit          Edit sync rules file\n"
    printf "  sync-jobs          Show running sync jobs\n"
    printf "  sync-cancel        Cancel a sync job\n"
    printf "  sync-kill          Kill all sync jobs\n"
    printf "  sync-clear-jobs    Clear completed/failed jobs\n"
    printf "  sync-run-rule NAME Run a specific rule [--dry-run] [--background]\n"
    printf "  sync-run-bg        Run all enabled rules in background (non-interactive)\n"
    printf "  sync-list          List all rules with details\n"
    printf "  sync-to SRC DEST   Ad-hoc one-way sync [--dry-run] [--background]\n"
    printf "  bisync-to P1 P2    Ad-hoc bidirectional sync [--dry-run] [--resync] [--background]\n"
    printf "  sync-cancel-id ID  Cancel a sync job by job ID\n"
    printf "  sync-status        Full sync status (remotes + rules + jobs + log)\n\n"
    printf "${BLD}Servers - Rclone Serve (2 commands):${RST}\n"
    printf "  server-start [NAME]  Start rclone serve instance\n"
    printf "  server-stop [NAME]   Stop rclone serve instance\n\n"
    printf "${BLD}Setup & Config (11 commands):${RST}\n"
    printf "  settings           Settings menu (dirs, options, merge strategy)\n"
    printf "  deps               Dependency status + install (categorized)\n"
    printf "  deps-core          Install core deps (git, jq, rclone, fusermount)\n"
    printf "  deps-phone         Install phone deps (kdeconnect-cli, qdbus)\n"
    printf "  deps-cloud         Install cloud deps (oci, gh, gcloud)\n"
    printf "  remotes            Configure rclone remotes\n"
    printf "  edit-workdir       Change git working directory\n"
    printf "  clear-log          Truncate log file\n"
    printf "  view-log           Show last 30 log lines (colored)\n"
    printf "  edit-config        Open config JSON in editor\n"
    printf "  config-set K V     Set a config value (e.g. config-set mount_dir /mnt)\n\n"

    printf "${BLD}Examples:${RST}\n"
    printf "  ${C_DIM}# Interactive dashboard${RST}\n"
    printf "  ./cloud-connect.sh\n\n"
    printf "  ${C_DIM}# Check git status for all repos${RST}\n"
    printf "  ./cloud-connect.sh git-status\n\n"
    printf "  ${C_DIM}# Sync all enabled rclone rules in background${RST}\n"
    printf "  ./cloud-connect.sh sync-run-bg\n\n"
    printf "  ${C_DIM}# Mount all VMs and drives${RST}\n"
    printf "  ./cloud-connect.sh mount-all-vm && ./cloud-connect.sh mount-all-drives\n\n"
    printf "  ${C_DIM}# Install missing dependencies${RST}\n"
    printf "  ./cloud-connect.sh deps\n\n"

    printf "${BLD}Config File:${RST} ${C_DIM}%s${RST}\n" "$CONFIG_FILE"
    printf "${BLD}Total Commands:${RST} ${C_INFO}68${RST} (Git:23 Mesh:6 OCI:4 Drives:5 Sync:17 Servers:2 Setup:11)\n"
}

# =============================================================================
# CLI HELPERS
# =============================================================================

_mount_all_vms() {
    local vc vi vn vr
    vc=$(_jq '.mesh.vms | length'); vi=0
    while [ "$vi" -lt "$vc" ]; do
        vn=$(_jq -r ".mesh.vms[$vi].name"); vr=$(_jq -r ".mesh.vms[$vi].remote")
        mount_vm "$vn" "$vr"; vi=$((vi+1))
    done
}

_unmount_all_vms() {
    local vc vi vn
    vc=$(_jq '.mesh.vms | length'); vi=0
    while [ "$vi" -lt "$vc" ]; do
        vn=$(_jq -r ".mesh.vms[$vi].name"); unmount_vm "$vn"; vi=$((vi+1))
    done
}

_mount_all_drives() {
    local dc di dn dr
    dc=$(_jq '.drives | length'); di=0
    while [ "$di" -lt "$dc" ]; do
        dn=$(_jq -r ".drives[$di].name"); dr=$(_jq -r ".drives[$di].remote")
        mount_drive "$dn" "$dr"; di=$((di+1))
    done
}

_unmount_all_drives() {
    local dc di dn
    dc=$(_jq '.drives | length'); di=0
    while [ "$di" -lt "$dc" ]; do
        dn=$(_jq -r ".drives[$di].name"); unmount_drive "$dn"; di=$((di+1))
    done
}

_toggle_all_drives() {
    local dc di dn dr
    dc=$(_jq '.drives | length'); di=0
    while [ "$di" -lt "$dc" ]; do
        dn=$(_jq -r ".drives[$di].name"); dr=$(_jq -r ".drives[$di].remote")
        if is_mounted "$MOUNT_DIR/$dn"; then
            unmount_drive "$dn"
        else
            mount_drive "$dn" "$dr"
        fi
        di=$((di+1))
    done
}

_compact_view() {
    printf "\n${BLD}━━━ Compact Status ━━━${RST}\n\n"

    # MESH: one liner per VM
    local vm_count; vm_count=$(_jq '.mesh.vms | length')
    local vm_up=0 v=0
    while [ "$v" -lt "$vm_count" ]; do
        local name; name=$(_jq -r ".mesh.vms[$v].name")
        local mounted=false
        for sub in sys home docker mnt; do
            is_mounted "$MOUNT_DIR/$name/$sub" && mounted=true && break
        done
        [ "$mounted" = "true" ] && vm_up=$((vm_up+1))
        v=$((v+1))
    done
    printf "  ${C_MESH}MESH${RST}   %s/%s VMs " "$vm_up" "$vm_count"
    v=0; while [ "$v" -lt "$vm_count" ]; do
        local name; name=$(_jq -r ".mesh.vms[$v].name")
        local mounted=false
        for sub in sys home docker mnt; do is_mounted "$MOUNT_DIR/$name/$sub" && mounted=true && break; done
        [ "$mounted" = "true" ] && printf "${C_OK}${S_DOT}%s${RST} " "$name" || printf "${C_DIM}${S_STOP}%s${RST} " "$name"
        v=$((v+1))
    done
    local phone_mounted=false; is_mounted "$MOUNT_DIR/phone" && phone_mounted=true
    [ "$phone_mounted" = "true" ] && printf "${C_OK}${S_DOT}phone${RST}" || printf "${C_DIM}${S_STOP}phone${RST}"
    printf "\n"

    # GIT: one liner summary
    local repos; repos=$(git_get_repos)
    local cloned=0 clean=0 dirty=0 ahead=0 behind=0
    while IFS= read -r rname; do
        [ -z "$rname" ] && continue
        local dir="$GIT_WORKDIR/$rname"
        [ ! -d "$dir/.git" ] && continue
        cloned=$((cloned+1))
        local d; d=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        [ "$d" -gt 0 ] && dirty=$((dirty+1)) || clean=$((clean+1))
        local pu; pu=$(git_unpushed "$dir"); [ "$pu" != "?" ] && [ "$pu" -gt 0 ] 2>/dev/null && ahead=$((ahead+1))
        local pl; pl=$(git_unpulled "$dir"); [ "$pl" != "?" ] && [ "$pl" -gt 0 ] 2>/dev/null && behind=$((behind+1))
    done <<< "$repos"
    printf "  ${C_GIT}GIT${RST}    %s/%s cloned" "$cloned" "$(echo "$repos" | grep -c '.' || echo 0)"
    [ "$clean" -gt 0 ] && printf "  ${C_OK}%s clean${RST}" "$clean"
    [ "$dirty" -gt 0 ] && printf "  ${C_WARN}%s dirty${RST}" "$dirty"
    [ "$ahead" -gt 0 ] && printf "  ${C_WARN}%s ahead${RST}" "$ahead"
    [ "$behind" -gt 0 ] && printf "  ${C_INFO}%s behind${RST}" "$behind"
    printf "\n"

    # DRIVES: one liner
    local drive_count; drive_count=$(_jq '.drives | length')
    local drive_up=0 d=0
    while [ "$d" -lt "$drive_count" ]; do
        local dname; dname=$(_jq -r ".drives[$d].name")
        is_mounted "$MOUNT_DIR/$dname" && drive_up=$((drive_up+1))
        d=$((d+1))
    done
    printf "  ${C_DRIVE}DRIVE${RST}  %s/%s mounted " "$drive_up" "$drive_count"
    d=0; while [ "$d" -lt "$drive_count" ]; do
        local dname; dname=$(_jq -r ".drives[$d].name")
        is_mounted "$MOUNT_DIR/$dname" && printf "${C_OK}${S_DOT}%s${RST} " "$dname" || printf "${C_DIM}${S_STOP}%s${RST} " "$dname"
        d=$((d+1))
    done
    printf "\n"

    # SYNC: one liner
    local rules; rules=$(sync_list_rules)
    local rule_count; rule_count=$(echo "$rules" | jq 'length')
    local enabled_cnt; enabled_cnt=$(echo "$rules" | jq '[.[] | select(.enabled == true)] | length')
    local running; running=$(sync_get_running_jobs)
    local run_count; run_count=$(echo "$running" | jq 'length')
    printf "  ${C_SYNC}SYNC${RST}   %s rules (%s enabled)" "$rule_count" "$enabled_cnt"
    [ "$run_count" -gt 0 ] && printf "  ${C_OK}${S_PLAY} %s running${RST}" "$run_count"
    printf "\n"

    # SERVERS: one liner
    local srv_count; srv_count=$(_jq '.servers | length')
    local srv_up=0 s=0
    while [ "$s" -lt "$srv_count" ]; do
        local sport; sport=$(_jq -r ".servers[$s].port")
        pgrep -f "rclone serve.*$sport" >/dev/null 2>&1 && srv_up=$((srv_up+1))
        s=$((s+1))
    done
    printf "  ${C_SRVR}SRVR${RST}   %s/%s servers running\n" "$srv_up" "$srv_count"

    printf "\n"
}

_detail_view() {
    printf "${BLD}=== DETAILED STATUS ===${RST}\n\n"
    printf "${C_MESH}── MESH ──${RST}\n"
    render_mesh
    printf "\n${C_GIT}── GIT ──${RST}\n"
    render_git
    printf "\n${C_DRIVE}── DRIVES ──${RST}\n"
    render_drives
    printf "\n${C_SYNC}── SYNC ──${RST}\n"
    render_sync
    printf "\n${C_SRVR}── SERVERS ──${RST}\n"
    render_servers
    printf "\n${C_WEB}── WEBSERVER ──${RST}\n"
    render_webservers
    printf "\n${C_DIM}── LOG ──${RST}\n"
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        local fsize line_count err_count
        fsize=$(du -h "$LOG_FILE" 2>/dev/null | cut -f1)
        line_count=$(wc -l < "$LOG_FILE" 2>/dev/null)
        err_count=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo 0)
        printf "  ${C_DIM}Size: %s | Lines: %s | Errors: " "$fsize" "$line_count"
        [ "$err_count" -gt 0 ] && printf "${C_ERR}%s${RST}\n" "$err_count" || printf "${C_OK}%s${RST}\n" "$err_count"
        tail -10 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
            if echo "$line" | grep -q "ERROR"; then
                printf "  ${C_ERR}%s${RST}\n" "$line"
            else
                printf "  ${C_DIM}%s${RST}\n" "$line"
            fi
        done
    else
        printf "  ${C_DIM}Log empty${RST}\n"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Handle deps/help commands BEFORE requiring jq (like mount.sh)
    case "${1:-}" in
        deps)            deps_menu; return ;;
        deps-core)       install_deps_category "core"; return ;;
        deps-phone)      install_deps_category "phone"; return ;;
        deps-cloud)      install_deps_category "cloud"; return ;;
        --help|-h|help)
            if ! command -v jq >/dev/null 2>&1; then
                printf "${C_ERR}${S_FAIL}${RST} jq not installed — showing minimal help\n\n"
                printf "${BLD}Dependency commands (work without jq):${RST}\n"
                printf "  deps           Show dependency status\n"
                printf "  deps-core      Install core deps (git, jq, rclone, fusermount)\n"
                printf "  deps-phone     Install phone deps (kdeconnect, qdbus)\n"
                printf "  deps-cloud     Install cloud deps (oci, gh, gcloud)\n"
                printf "\nRun ${C_INFO}deps-core${RST} first, then ${C_INFO}--help${RST} for full help.\n"
                return
            fi
            ;;
    esac

    load_config

    case "${1:-}" in
        # ── Dashboard ──
        "")              run_tui ;;
        tui)             run_tui ;;
        detail)          _detail_view ;;
        compact)         _compact_view ;;
        --help|-h|help)  show_help ;;

        # ── Git ──
        git-status)      render_git ;;
        git-sync)        git_cmd_sync ;;
        git-pull)        git_cmd_pull ;;
        git-push)        git_cmd_push ;;
        git-commit)      git_cmd_commit ;;
        git-fetch)       git_cmd_fetch ;;
        git-fetch-status) git_cmd_fetch_status ;;
        git-clone)       git_cmd_clone_menu ;;
        git-untracked)   git_cmd_untracked ;;
        git-unstaged)    git_cmd_unstaged ;;
        git-ignored)     git_cmd_ignored ;;
        git-workdir)     edit_workdir ;;
        git-merge)       git_toggle_merge ;;
        git-dirty)       git_cmd_dirty ;;
        git-notok)       git_cmd_dirty ;;
        git-refresh)     render_git ;;
        git-remotes)     git_cmd_remotes ;;
        git-branches)    git_cmd_branches ;;
        git-tags)        git_cmd_tags ;;
        git-log)         git_cmd_log ;;
        git-stash-list)  git_cmd_stash_list ;;
        git-diff)        git_cmd_diff ;;
        git-gc)          git_cmd_gc ;;
        git-prune)       git_cmd_prune ;;

        # ── Mesh (VM mounts) ──
        mount-vm)
            if [ -n "${2:-}" ]; then
                mount_vm "$2" "$2"
            else
                select_and_mount_vm
            fi ;;
        unmount-vm)
            if [ -n "${2:-}" ]; then
                unmount_vm "$2"
            else
                select_and_unmount_vm
            fi ;;
        mount-all-vm)    _mount_all_vms ;;
        unmount-all)
            _unmount_all_vms
            _unmount_all_drives
            unmount_phone ;;
        mount-phone)     mount_phone ;;
        unmount-phone)   unmount_phone ;;

        # ── OCI Flex ──
        flex-start)      flex_select_and_action "start" ;;
        flex-stop)       flex_select_and_action "stop" ;;
        flex-reset)      flex_select_and_action "reset" ;;
        flex-status)     flex_select_and_action "status" ;;

        # ── Drives ──
        mount-drive)
            if [ -n "${2:-}" ]; then
                local dr; dr=$(_jq -r ".drives[] | select(.name==\"$2\") | .remote")
                [ -n "$dr" ] && mount_drive "$2" "$dr" || printf "${C_ERR}Drive not found: %s${RST}\n" "$2"
            else
                select_and_mount_drive
            fi ;;
        unmount-drive)
            if [ -n "${2:-}" ]; then
                unmount_drive "$2"
            else
                select_and_unmount_drive
            fi ;;
        mount-all-drives)   _mount_all_drives ;;
        unmount-all-drives) _unmount_all_drives ;;
        toggle-drives)      _toggle_all_drives ;;

        # ── Sync ──
        sync-run)        sync_run_all ;;
        sync-add)        sync_add_rule_wizard ;;
        sync-delete)     sync_delete_rule ;;
        sync-toggle)     sync_toggle_rule ;;
        sync-quick)      sync_quick_menu ;;
        sync-edit)       sync_edit_rules ;;
        sync-jobs)       sync_show_jobs ;;
        sync-cancel)     sync_cancel_job ;;
        sync-kill)       sync_kill_all ;;
        sync-clear-jobs) sync_clear_completed ;;
        sync-run-rule)   shift; sync_run_rule_cli "$@" ;;
        sync-list)       sync_list_cli ;;
        sync-run-bg)     sync_run_all_bg ;;
        sync-to)         shift; sync_adhoc "$@" ;;
        bisync-to)       shift; bisync_adhoc "$@" ;;
        sync-cancel-id)  shift; sync_cancel_by_id "$@" ;;
        sync-status)     sync_full_status ;;

        # ── Servers ──
        server-start)    server_start ;;
        server-stop)     server_stop ;;

        # ── Setup ──
        settings)        settings_menu ;;
        deps)            deps_menu ;;
        deps-core)       install_deps_category "core" ;;
        deps-phone)      install_deps_category "phone" ;;
        deps-cloud)      install_deps_category "cloud" ;;
        remotes)         configure_remote_menu ;;
        edit-workdir)    edit_workdir ;;
        clear-log)       clear_log ;;
        view-log)        view_log ;;
        edit-config)     edit_config ;;
        config-set)      shift; config_set "$@" ;;
        restore-symlinks) restore_symlinks ;;

        # ── Legacy aliases ──
        status)          render_git ;;
        sync)            git_cmd_sync ;;
        pull)            git_cmd_pull ;;
        push)            git_cmd_push ;;
        commit)          git_cmd_commit ;;
        fetch)           git_cmd_fetch ;;
        clone)           git_cmd_clone_menu ;;
        mount)           _mount_all_vms; _mount_all_drives ;;
        unmount)         _unmount_all_vms; _unmount_all_drives ;;

        *)
            printf "${C_ERR}Unknown command: %s${RST}\n\n" "$1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
