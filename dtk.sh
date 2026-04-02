#!/bin/sh
# Diego's Toolkit (DTK) — unified CLI for aliases, containers, connect, and ops
# Usage: ./dtk.sh                # interactive
#        ./dtk.sh <cmd> [args]   # direct
# OS-agnostic POSIX: NixOS, Arch, Debian, Fedora, macOS, Termux
set -eu

# Logging — verbose trace to screen + log file
LOGFILE="${HOME:-/tmp}/dtk.log"
_LOG_USER=$(whoami 2>/dev/null || echo "?")
_LOG_HOST=$(hostname -s 2>/dev/null || echo "?")
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ${_LOG_USER}@${_LOG_HOST} === dtk.sh $* ===" >> "$LOGFILE"

# Force real system binaries FIRST (bypass nix guardrail wrappers)
export PATH="/run/wrappers/bin:/usr/bin:/usr/sbin:/usr/local/bin:/bin:/sbin:/nix/var/nix/profiles/default/bin:${HOME:-/root}/.nix-profile/bin:/run/current-system/sw/bin:$PATH"

# Stop systemd journal from flooding the terminal
if [ "$(id -u)" = "0" ] 2>/dev/null; then
  dmesg -n 1 2>/dev/null || true
  systemctl stop systemd-journald-audit.socket 2>/dev/null || true
  echo 0 > /proc/sys/kernel/printk 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════════
# SYSTEM DETECTION — populated once, used by all commands
# ═══════════════════════════════════════════════════════════════════

SYS_OS="unknown"; SYS_DISTRO="unknown"; SYS_PKG="none"
SYS_HAS_NIX=false; SYS_HAS_DOCKER=false; SYS_DOCKER_PATH=""
SYS_ARCH="unknown"; SYS_ARCH_SHORT="unknown"
SYS_HOSTNAME="unknown"; SYS_CPUS="?"; SYS_RAM_MB="?"
SYS_KERNEL="?"; SYS_INIT="other"

detect_system() {
  # OS / Distro
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    SYS_OS="${ID:-unknown}"
    SYS_DISTRO="${PRETTY_NAME:-$ID}"
    case "$ID" in
      nixos)                         SYS_PKG="nix" ;;
      arch|manjaro)                  SYS_PKG="pacman" ;;
      debian|ubuntu|pop|mint)        SYS_PKG="apt" ;;
      fedora|rhel|centos|rocky|alma) SYS_PKG="dnf" ;;
    esac
  elif [ -d /data/data/com.termux ]; then
    SYS_OS="termux"; SYS_DISTRO="Termux (Android)"; SYS_PKG="pkg"
  elif command -v sw_vers >/dev/null 2>&1; then
    SYS_OS="macos"; SYS_DISTRO="macOS $(sw_vers -productVersion 2>/dev/null)"; SYS_PKG="brew"
  fi

  # Has nix?
  if command -v nix >/dev/null 2>&1; then
    SYS_HAS_NIX=true
    [ "$SYS_PKG" = "none" ] && SYS_PKG="nix"
  fi

  # Architecture
  SYS_ARCH=$(uname -m 2>/dev/null || echo "unknown")
  case "$SYS_ARCH" in
    x86_64|amd64)  SYS_ARCH_SHORT="x86" ;;
    aarch64|arm64) SYS_ARCH_SHORT="arm64" ;;
    armv7l|armhf)  SYS_ARCH_SHORT="arm32" ;;
    *)             SYS_ARCH_SHORT="$SYS_ARCH" ;;
  esac

  SYS_HOSTNAME=$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown")
  SYS_CPUS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")

  if [ -f /proc/meminfo ]; then
    SYS_RAM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
  elif command -v sysctl >/dev/null 2>&1; then
    SYS_RAM_MB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 ))
  fi

  SYS_KERNEL=$(uname -r 2>/dev/null || echo "?")

  if command -v docker >/dev/null 2>&1; then
    SYS_HAS_DOCKER=true
    SYS_DOCKER_PATH=$(command -v docker)
  fi

  if command -v systemctl >/dev/null 2>&1; then
    SYS_INIT="systemd"
  elif [ -f /sbin/openrc ]; then
    SYS_INIT="openrc"
  fi
}

show_banner() { set +x 2>/dev/null
  R='\033[0m'; B='\033[1;34m'; C='\033[1;36m'; G='\033[1;32m'
  Y='\033[1;33m'; M='\033[1;35m'; W='\033[1;37m'; D='\033[0;90m'
  nix_icon="$D off$R"; [ "$SYS_HAS_NIX" = true ] && nix_icon="${G}ON${R}"
  docker_icon="$D off$R"; [ "$SYS_HAS_DOCKER" = true ] && docker_icon="${G}ON${R}"
  _kern="${SYS_KERNEL%%[-+]*}"

  printf '\n'
  printf "${C}  ██████╗ ${B}████████╗${M}██╗  ██╗${R}\n"
  printf "${C}  ██╔══██╗${B}╚══██╔══╝${M}██║ ██╔╝${R}\n"
  printf "${C}  ██║  ██║${B}   ██║   ${M}█████╔╝ ${R}  ${W}Diego's Toolkit${R}\n"
  printf "${C}  ██║  ██║${B}   ██║   ${M}██╔═██╗ ${R}  ${D}OS-agnostic VM & container manager${R}\n"
  printf "${C}  ██████╔╝${B}   ██║   ${M}██║  ██╗${R}\n"
  printf "${C}  ╚═════╝ ${B}   ╚═╝   ${M}╚═╝  ╚═╝${R}\n"
  printf '\n'
  _T=$(printf '\t')
  _uptime=$(uptime -p 2>/dev/null | sed 's/up //')
  [ -z "$_uptime" ] && _uptime=$(uptime 2>/dev/null | sed 's/.*up //' | sed 's/,.*//' | sed 's/^ *//')
  [ -z "$_uptime" ] && _uptime="?"
  _disk=$(LANG=C command df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2}' || echo "?")
  _mem_used=$(free -m 2>/dev/null | awk '/Mem/{print $3}' || echo "?")
  _load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "?")
  _wg_ip=$(ip -4 addr show wg0 2>/dev/null | awk '/inet/{print $2}' | cut -d/ -f1 || echo "down")
  _containers=$(docker ps -q 2>/dev/null | wc -l || echo "0")
  printf '%s\n' \
    "host ${SYS_HOSTNAME}${_T}os ${SYS_DISTRO}${_T}uptime ${_uptime}" \
    "arch ${SYS_ARCH}${_T}kernel ${_kern}${_T}disk ${_disk}" \
    "cpu ${SYS_CPUS} cores${_T}ram ${_mem_used}/${SYS_RAM_MB}MB${_T}load ${_load}" \
    "pkg ${SYS_PKG}${_T}init ${SYS_INIT}${_T}wg0 ${_wg_ip}" \
    "nix $([ "$SYS_HAS_NIX" = true ] && echo ON || echo off)${_T}docker $([ "$SYS_HAS_DOCKER" = true ] && echo ON || echo off)${_T}containers ${_containers}" \
  | column -t -s"${_T}" | while IFS= read -r _line; do printf "  ${D}%s${R}\n" "$_line"; done
  printf "  ${D}──────────────────────────────────────────────────────────────────────────────────${R}\n"
  printf '\n'
}

_BANNER_SHOWN=false
show_menu_header() { set +x 2>/dev/null
  R='\033[0m'; C='\033[1;36m'; D='\033[0;90m'
  if [ "$_BANNER_SHOWN" = false ]; then
    show_banner
    _BANNER_SHOWN=true
  else
    printf "\n"
  fi

  # Menu tree — auto-aligned via column -t
  _T=$(printf '\t')
  printf "1) cmds-local${_T}2) cmds-cloud${_T}3) dashboards${_T}4) setups${_T}5) infos\n" | column -t -s"${_T}" | while IFS= read -r _line; do printf "  ${C}%s${R}\n" "$_line"; done
  printf "  ${D}──────────────────────────────────────────────────────────────────────────────────${R}\n"
  printf '%s\n' \
    "10 aliases${_T}20 quick-cmds${_T}local${_T}40 deb${_T}50 help" \
    "11 webhooks${_T}  20a gcp-proxy${_T}30 monitors${_T}  40a nix-cli${_T}51 tools" \
    "12 commands${_T}  20b oci-mail${_T}  30a btop${_T}  40b nix-gui${_T}  51a table" \
    "  (120-1225)${_T}  20c oci-analy${_T}  30b iotop${_T}  40c nix-tty${_T}  51b help" \
    "${_T}  20d oci-apps${_T}  30c top-batch${_T}  40d apt-cli${_T}52 info" \
    "${_T}  20e gcp-t4${_T}31 sysstat${_T}  40e apt-gui${_T}  52a info" \
    "${_T}  20f orchestrate${_T}  31a iostat${_T}  40f apt-tty${_T}  52b engines" \
    "${_T}  20g local${_T}  31b mpstat${_T}41 nixos${_T}" \
    "${_T}  20h desktop${_T}  31c pidstat${_T}  41a hm-cli${_T}" \
    "${_T}  20i vps-cloud${_T}  31d sar${_T}  41b hm-gui${_T}" \
    "${_T}  20j gh-actions${_T}32 journal-dash${_T}  41c hm-tty${_T}" \
    "${_T}  20k gh-repos${_T}  32a transport${_T}42 shell${_T}" \
    "${_T}  20l gh-registry${_T}  32b priority${_T}  42a fish+tools${_T}" \
    "${_T}21 ssh${_T}  32c unit${_T}  42b fish${_T}" \
    "${_T}  21a gcp-proxy${_T}  32d watch-n35${_T}  42c konsole-cfg${_T}" \
    "${_T}  21b oci-mail${_T}33 connect${_T}43 git${_T}" \
    "${_T}  21c oci-analy${_T}remote${_T}  43a gcl-https${_T}" \
    "${_T}  21d oci-apps${_T}34 btop-dash${_T}  43b gcl-ssh${_T}" \
    "${_T}  21e gcp-t4${_T}35 journal-dash${_T}${_T}" \
    "${_T}  21f github${_T}36 docker-stats${_T}${_T}" \
  | column -t -s"${_T}" | while IFS= read -r _line; do printf "  ${D}%s${R}\n" "$_line"; done
  printf "  ${D}──────────────────────────────────────────────────────────────────────────────────${R}\n"
  # Commands sub-table
  printf "  ${D}12) commands:${R}\n"
  printf '%s\n' \
    "120 fish-install${_T}125 stop-docker${_T}1210 free-mem${_T}1215 full-rescue${_T}1220 ssh-restart" \
    "121 flush-ipt${_T}126 start-docker${_T}1211 disk-usage${_T}1216 tmux-web${_T}1221 wg-debug" \
    "122 rst-sshd${_T}127 docker-ps${_T}1212 kill-wdog${_T}1217 fix-wg-ip${_T}1222 sshd-debug" \
    "123 rst-wg${_T}128 wg-status${_T}1213 journal-sil${_T}1218 guardrail${_T}1223 vm-health" \
    "124 rst-docker${_T}129 iptables${_T}1214 fix-journal${_T}1219 fix-nix-path${_T}1224 fix-all" \
    "${_T}${_T}${_T}${_T}1225 mem-emerg" \
  | column -t -s"${_T}" | while IFS= read -r _line; do printf "  ${D}%s${R}\n" "$_line"; done
  printf "  ${D}──────────────────────────────────────────────────────────────────────────────────${R}\n"
  printf "  ${D}(b)ack  (q)uit  (r)efresh  1-5 menu  10-52 shortcode${R}\n"
  printf "\n"
}

detect_system

# ═══════════════════════════════════════════════════════════════════
# VM Map (POSIX: case statement instead of associative array)
# ═══════════════════════════════════════════════════════════════════

PROJECT="diegonmarcos-infra-prod"

# Module paths — all logic lives in subfolders, dtk.sh is the orchestrator
_DTK_DIR="$(cd "$(dirname "$0")" && pwd)"
_OTHERS_DIR="$_DTK_DIR/5-infos"
_ALIASES_DIR="$_DTK_DIR/1-aliases"

# ═══════════════════════════════════════════════════════════════════
# POSIX menu picker
# ═══════════════════════════════════════════════════════════════════

pick() { set +x 2>/dev/null
  _label="$1"; shift
  echo "$_label"
  _i=1
  for _item in "$@"; do
    printf "  %d) %s\n" "$_i" "$_item"
    _i=$((_i + 1))
  done
  printf "> "
  read -r _idx
  case "$_idx" in b|B) PICK="back"; return 0 ;; q|Q) echo "Bye."; exit 0 ;; esac
  # Global shortcodes: if input looks like a multi-digit shortcode, route it
  case "$_idx" in [1-5][0-9a-f]*) _resolve_shortcode "$_idx"; PICK="back"; return 0 ;; esac
  _idx=$((_idx)) 2>/dev/null || { echo "Invalid"; return 1; }
  [ "$_idx" -ge 1 ] && [ "$_idx" -le $# ] || { echo "Invalid"; return 1; }
  _c=0
  for _item in "$@"; do
    _c=$((_c + 1))
    [ "$_c" -eq "$_idx" ] && PICK="$_item" && return 0
  done
}

# ═══════════════════════════════════════════════════════════════════
# A) ALIASES — toolchain list (all aliases/functions by category)
# ═══════════════════════════════════════════════════════════════════

do_aliases() { set +x 2>/dev/null
  _SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  _ALIASES_JSON="$_SCRIPT_DIR/1-aliases/aliases.json"

  # 3-column layout: key+val | key+val | key+val
  jq -r '
    to_entries[] |
    .key as $cat |
    "H:" + $cat,
    (.value | paths(scalars) as $p | (.key = ($p | last) | .val = getpath($p)) |
      "\(.key)|\(.val)")
  ' "$_ALIASES_JSON" 2>/dev/null | awk -F'|' '
    BEGIN {
      C = "\033[1;36m"; Y = "\033[1;33m"; R = "\033[0m"
      n = 0; COLS = 3; KW = 12; VW = 16
    }
    /^H:/ { sub(/^H:/, ""); lines[n] = "H|" $0; n++; next }
    { if ($1 != "") { lines[n] = $1 "|" $2; n++ } }
    END {
      i = 0
      while (i < n) {
        if (substr(lines[i], 1, 2) == "H|") {
          printf "  " C "── %s ──" R "\n", substr(lines[i], 3)
          i++; continue
        }
        col = 0
        while (col < COLS && i < n && substr(lines[i], 1, 2) != "H|") {
          split(lines[i], a, "|"); k = a[1]; v = a[2]
          if (k == "") { i++; continue }
          if (length(v) > VW) v = substr(v, 1, VW-1) "…"
          printf "  " Y "%-*s" R "%-*s", KW, k, VW, v
          col++; i++
        }
        if (col > 0) printf "\n"
      }
      printf "\n"
    }
  '
}

do_tools() { set +x 2>/dev/null
  _SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  _TOOLS_JSON="$_SCRIPT_DIR/1-aliases/tools.json"

  # 5-column layout: tool names (keys only) by category
  jq -r '
    to_entries[] |
    "H:" + .key,
    (.value | keys_unsorted[])
  ' "$_TOOLS_JSON" 2>/dev/null | awk '
    BEGIN {
      C = "\033[1;36m"; G = "\033[1;32m"; R = "\033[0m"; D = "\033[0;90m"
      n = 0; COLS = 5; W = 16
    }
    /^H:/ { sub(/^H:/, ""); lines[n] = "H|" $0; n++; next }
    { if ($0 != "") { lines[n] = $0; n++ } }
    END {
      i = 0
      while (i < n) {
        if (substr(lines[i], 1, 2) == "H|") {
          printf "  " C "── %s ──" R "\n", substr(lines[i], 3)
          i++; continue
        }
        col = 0
        while (col < COLS && i < n && substr(lines[i], 1, 2) != "H|") {
          t = lines[i]
          if (length(t) > W-2) t = substr(t, 1, W-3) "…"
          printf "  " G "%-*s" R, W-2, t
          col++; i++
        }
        if (col > 0) printf "\n"
      }
      printf "\n"
    }
  '
}

do_tools_help() { set +x 2>/dev/null
  _SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  _TOOLS_JSON="$_SCRIPT_DIR/1-aliases/tools.json"

  # 1-column: tool name + description, grouped by category
  jq -r '
    to_entries[] |
    "H:" + .key,
    (.value | to_entries[] | "\(.key)|\(.value)")
  ' "$_TOOLS_JSON" 2>/dev/null | awk -F'|' '
    BEGIN {
      C = "\033[1;36m"; G = "\033[1;32m"; D = "\033[0;90m"; R = "\033[0m"
    }
    /^H:/ { sub(/^H:/, ""); printf "  " C "── %s ──" R "\n", $0; next }
    {
      if ($1 != "") printf "  " G "%-18s" R D "%s" R "\n", $1, $2
    }
    END { printf "\n" }
  '
}

# ═══════════════════════════════════════════════════════════════════
# B) CONTAINERS — pull & run dev environment container
# ═══════════════════════════════════════════════════════════════════

# Find docker binary by full path (skip shell aliases/wrappers)
find_docker() {
  DOCKER="" RUNTIME="docker"
  # 1a. From systemd service ExecStart
  if [ -f /etc/systemd/system/docker.service ]; then
    _dockerd=$(sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' /etc/systemd/system/docker.service 2>/dev/null || true)
    if [ -n "$_dockerd" ]; then
      _dir=$(dirname "$_dockerd" 2>/dev/null)
      [ -x "${_dir}/docker" ] && { DOCKER="${_dir}/docker"; return 0; }
    fi
  fi
  # 1b. Known full paths
  for p in \
    /run/current-system/sw/bin/docker \
    /usr/bin/docker \
    /usr/local/bin/docker \
    /nix/var/nix/profiles/default/bin/docker \
    "${HOME}/.nix-profile/bin/docker" \
    /opt/homebrew/bin/docker \
    /data/data/com.termux.nix/files/home/.nix-profile/bin/docker; do
    [ -x "$p" ] && { DOCKER="$p"; return 0; }
  done
  # 1c. command -v (last resort)
  _found=$(command -v docker 2>/dev/null || true)
  [ -n "$_found" ] && { DOCKER="$_found"; return 0; }
  return 1
}

# Find podman by full path
find_podman() {
  _PODMAN=""
  for p in /usr/bin/podman /usr/local/bin/podman /run/current-system/sw/bin/podman \
           "${HOME}/.nix-profile/bin/podman" /nix/var/nix/profiles/default/bin/podman; do
    [ -x "$p" ] && { _PODMAN="$p"; return 0; }
  done
  _PODMAN=$(command -v podman 2>/dev/null || true)
  [ -n "$_PODMAN" ] && return 0
  return 1
}

# Shared: ensure container runtime is ready
ensure_runtime() {
  DOCKER=""; RUNTIME="docker"
  find_docker || true
  if [ -z "$DOCKER" ]; then
    echo "Docker not found — installing for $SYS_PKG..."
    case "$SYS_PKG" in
      apt)    apt-get update -qq && apt-get install -y -qq docker.io ;;
      dnf)    dnf install -y --skip-unavailable docker ;;
      pacman) pacman -Sy --noconfirm docker ;;
      nix)
        if [ "$SYS_OS" = "nixos" ]; then
          echo "On NixOS: virtualisation.docker.enable = true; then nixos-rebuild switch"
          echo "Trying nix-shell fallback..."
        fi
        exec nix-shell -p docker --run "sh $0 $1" ;;
      brew)   brew install --cask docker ;;
      pkg)    echo "Docker not available on Termux"; exit 1 ;;
      *)      echo "No supported package manager — install docker manually"; exit 1 ;;
    esac
    find_docker || true
    [ -z "$DOCKER" ] && { echo "ERROR: docker not found after install"; exit 1; }
  fi
  if ! "$DOCKER" info >/dev/null 2>&1; then
    echo "Docker daemon not running — starting..."
    if [ "$SYS_INIT" = "systemd" ]; then
      systemctl start docker 2>/dev/null || true
      _w=0; while [ $_w -lt 15 ]; do "$DOCKER" info >/dev/null 2>&1 && break; sleep 1; _w=$((_w + 1)); done
    elif command -v service >/dev/null 2>&1; then
      service docker start 2>/dev/null || true; sleep 3
    elif [ "$SYS_OS" = "macos" ]; then
      open -a Docker 2>/dev/null || true
      _w=0; while [ $_w -lt 30 ]; do "$DOCKER" info >/dev/null 2>&1 && break; sleep 1; _w=$((_w + 1)); done
    fi
  fi
  if ! "$DOCKER" info >/dev/null 2>&1; then
    if find_podman; then
      echo "Docker failed — podman fallback ($_PODMAN)"
      DOCKER="$_PODMAN"; RUNTIME="podman"
      "$DOCKER" system migrate 2>/dev/null || true
    else
      echo "ERROR: Neither docker nor podman available"; exit 1
    fi
  fi
  echo "Using: $RUNTIME ($DOCKER)"
}

# ── docker-run: pick profile then launch ─────────────────────────────
do_docker_run() {
  _variant="${1:-}"
  _profile="${2:-}"
  _extra_cmd="${3:-}"

  # ── Pick image variant ──────────────────────────────────────────
  if [ -z "$_variant" ]; then
    show_menu_header
    pick "Image:" deb-nix deb-apt
    [ "$PICK" = "back" ] && return 0
    _variant="$PICK"
  fi
  # Normalize legacy names
  case "$_variant" in
    diego-cli|diego-gui|diego-tty)
      _profile=$(echo "$_variant" | sed 's/diego-//')
      _variant="deb-nix" ;;
  esac

  # ── Pick profile ────────────────────────────────────────────────
  if [ -z "$_profile" ]; then
    show_menu_header
    pick "Profile:" cli gui tty
    [ "$PICK" = "back" ] && return 0
    _profile="$PICK"
  fi

  # ── Resolve image ──────────────────────────────────────────────
  case "$_variant" in
    deb-nix) IMG="ghcr.io/diegonmarcos/diego-deb-nix:latest" ;;
    deb-apt) IMG="ghcr.io/diegonmarcos/diego-deb-apt:latest" ;;
    *)       IMG="ghcr.io/diegonmarcos/diego-deb-nix:latest" ;;
  esac
  HOME_DIR="${HOME:-/root}"
  ensure_runtime "docker-run"

  # Show banner inside container after launch
  _HELLO='
R="\033[0m"; C="\033[1;36m"; B="\033[1;34m"; M="\033[1;35m"; W="\033[1;37m"; D="\033[0;90m"; Y="\033[1;33m"; G="\033[1;32m"
printf "\n"
printf "${C}  ██████╗ ${B}████████╗${M}██╗  ██╗${R}\n"
printf "${C}  ██╔══██╗${B}╚══██╔══╝${M}██║ ██╔╝${R}\n"
printf "${C}  ██║  ██║${B}   ██║   ${M}█████╔╝ ${R}  ${W}Diego'\''s Container${R}\n"
printf "${C}  ██║  ██║${B}   ██║   ${M}██╔═██╗ ${R}  ${D}Profile: PROFILE_PLACEHOLDER${R}\n"
printf "${C}  ██████╔╝${B}   ██║   ${M}██║  ██╗${R}\n"
printf "${C}  ╚═════╝ ${B}   ╚═╝   ${M}╚═╝  ╚═╝${R}\n"
printf "\n"
_h=$(hostname -s 2>/dev/null || echo "?")
_os=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d "\"" || uname -s)
_arch=$(uname -m 2>/dev/null || echo "?")
_kern=$(uname -r 2>/dev/null || echo "?"); _kern=${_kern%%[-+]*}
_cpu=$(nproc 2>/dev/null || echo "?")
_ram=$(awk "/MemTotal/{printf \"%d\", \$2/1024}" /proc/meminfo 2>/dev/null || echo "?")
_nix="off"; command -v nix >/dev/null 2>&1 && _nix="${G}ON${R}"
_dk="off"; command -v docker >/dev/null 2>&1 && _dk="${G}ON${R}"
printf "  ${Y}host${R}  ${W}%-20s${R}  ${Y}os${R}    ${W}%s${R}\n" "$_h" "$_os"
printf "  ${Y}arch${R}  ${W}%-20s${R}  ${Y}kernel${R}  ${W}%s${R}\n" "$_arch" "$_kern"
printf "  ${Y}cpu${R}   ${W}%-20s${R}  ${Y}ram${R}     ${W}%sMB${R}\n" "$_cpu cores" "$_ram"
printf "  ${Y}nix${R}   $_nix                        ${Y}docker${R}  $_dk\n"
printf "  ${D}──────────────────────────────────────────────${R}\n"
printf "\n"
'
  _HELLO=$(printf '%s' "$_HELLO" | sed "s/PROFILE_PLACEHOLDER/$_variant \/ $_profile/")

  echo "=== docker-run [$_profile]: $IMG ==="
  "$DOCKER" pull "$IMG"

  # Add image + label info to hello banner
  _IMG_SIZE=$("$DOCKER" image inspect "$IMG" --format '{{.Size}}' 2>/dev/null || echo "0")
  _IMG_SIZE_MB=$(( _IMG_SIZE / 1024 / 1024 ))
  _IMG_CREATED=$("$DOCKER" image inspect "$IMG" --format '{{.Created}}' 2>/dev/null | cut -c1-10 || echo "?")
  _IMG_ARCH=$("$DOCKER" image inspect "$IMG" --format '{{.Architecture}}' 2>/dev/null || echo "?")
  _lbl() { _v=$("$DOCKER" image inspect "$IMG" --format "{{index .Config.Labels \"$1\"}}" 2>/dev/null); [ "$_v" != "<no value>" ] && [ -n "$_v" ] && echo "$_v" || echo "$2"; }
  _IMG_DIGEST=$("$DOCKER" image inspect "$IMG" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//' | cut -c1-19 || echo "?")
  _IMG_LAYERS=$("$DOCKER" image inspect "$IMG" --format '{{len .RootFS.Layers}}' 2>/dev/null || echo "?")
  _IMG_SRC=$(_lbl "org.opencontainers.image.source" "github.com/diegonmarcos/unix")
  _IMG_DESC=$(_lbl "org.opencontainers.image.description" "Nix dev env (nix profile install)")
  _IMG_DFILE=$(_lbl "diego.image.dockerfile.path" "ba_flakes_desktop/src/container/Containerfile")
  _IMG_COMPOSE=$(_lbl "diego.image.compose.path" "ba_flakes_desktop/src/container/compose.yaml")
  _IMG_FLAKE=$(_lbl "diego.image.flake.path" "ba_flakes_desktop/src/")
  _IMG_GHCR=$(_lbl "diego.image.ghcr" "$IMG")
  _IMG_RUNNER=$(_lbl "diego.image.runner" "~/git/tools/dtk.sh containers {cli|gui|tty}")
  _IMG_SHELL=$(_lbl "diego.image.packages.shell" "fish starship eza bat fd rg fzf jq")
  _IMG_LANG=$(_lbl "diego.image.packages.lang" "rust go node python ruby gcc llvm")
  _IMG_CLOUD=$(_lbl "diego.image.packages.cloud" "docker kubectl helm terraform sops age")
  _IMG_META=$(_lbl "diego.image.container.path" "~/.image-meta/ (Containerfile + compose.yaml)")

  _HELLO="${_HELLO}
printf \"  \${Y}image\${R} \${W}%-20s\${R}  \${Y}size\${R}    \${W}%sMB\${R}\n\" \"$_IMG_ARCH\" \"$_IMG_SIZE_MB\"
printf \"  \${Y}built\${R} \${W}%-20s\${R}  \${Y}tag\${R}     \${W}%s\${R}\n\" \"$_IMG_CREATED\" \"latest\"
printf \"  \${Y}layers\${R}\${W}%-19s\${R}  \${Y}digest\${R}  \${W}%s\${R}\n\" \" $_IMG_LAYERS\" \"$_IMG_DIGEST\"
printf \"  \${D}──────────────────────────────────────────────\${R}\n\"
printf \"  \${Y}ghcr\${R}      \${W}%s\${R}\n\" \"$_IMG_GHCR\"
printf \"  \${Y}src\${R}       \${W}%s\${R}\n\" \"$_IMG_SRC\"
printf \"  \${Y}flake\${R}     \${W}%s\${R}\n\" \"$_IMG_FLAKE\"
printf \"  \${Y}file\${R}      \${D}%s\${R}\n\" \"$_IMG_DFILE\"
printf \"  \${Y}compose\${R}   \${D}%s\${R}\n\" \"$_IMG_COMPOSE\"
printf \"  \${Y}embedded\${R}  \${D}%s\${R}\n\" \"$_IMG_META\"
printf \"  \${Y}runner\${R}    \${D}%s\${R}\n\" \"$_IMG_RUNNER\"
printf \"  \${D}──────────────────────────────────────────────\${R}\n\"
printf \"  \${Y}shell\${R}     \${D}%s\${R}\n\" \"$_IMG_SHELL\"
printf \"  \${Y}lang\${R}      \${D}%s\${R}\n\" \"$_IMG_LANG\"
printf \"  \${Y}cloud\${R}     \${D}%s\${R}\n\" \"$_IMG_CLOUD\"
printf \"  \${D}──────────────────────────────────────────────\${R}\n\"
printf \"  \${D}%s\${R}\n\" \"$_IMG_DESC\"
printf \"\n\"
"

  # Shell commands: show banner then drop to shell (or run tty command)
  SHELL_CMD="${_HELLO}
exec fish 2>/dev/null || exec bash 2>/dev/null || exec sh"
  _NIX_PATH="/home/${USER:-root}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/sbin"

  case "$_profile" in
    cli)
      MOUNTS="-v $HOME_DIR:$HOME_DIR"
      [ -S /var/run/docker.sock ] && MOUNTS="$MOUNTS -v /var/run/docker.sock:/var/run/docker.sock"
      [ -d /etc/wireguard ]       && MOUNTS="$MOUNTS -v /etc/wireguard:/etc/wireguard:ro"
      [ -d /opt ]                 && MOUNTS="$MOUNTS -v /opt:/opt"

      FLAGS="--privileged --network host --pid host"
      [ "$RUNTIME" = "podman" ] && FLAGS="--privileged --network host"

      "$DOCKER" run -it --rm \
        --name diego-cli \
        --hostname "${SYS_HOSTNAME}-cli" \
        $FLAGS $MOUNTS \
        -w "$HOME_DIR" \
        -e HOME="$HOME_DIR" -e USER="${USER:-root}" \
        -e TERM="${TERM:-xterm-256color}" \
        -e PATH="$_NIX_PATH" \
        "$IMG" bash -c "$SHELL_CMD"
      ;;

    gui)
      _UID=$(id -u 2>/dev/null || echo 1000)
      _XDG="${XDG_RUNTIME_DIR:-/run/user/$_UID}"

      MOUNTS="-v $HOME_DIR:$HOME_DIR:rslave"
      MOUNTS="$MOUNTS -v /tmp:/tmp:rslave"
      MOUNTS="$MOUNTS -v /dev:/dev:rslave"
      MOUNTS="$MOUNTS -v /sys:/sys:rslave"
      MOUNTS="$MOUNTS -v /dev/pts -v /dev/null:/dev/ptmx"
      [ -d "$_XDG" ]              && MOUNTS="$MOUNTS -v $_XDG:$_XDG:rslave"
      [ -S /var/run/docker.sock ] && MOUNTS="$MOUNTS -v /var/run/docker.sock:/var/run/docker.sock"
      [ -d /etc/wireguard ]       && MOUNTS="$MOUNTS -v /etc/wireguard:/etc/wireguard:ro"
      [ -d /opt ]                 && MOUNTS="$MOUNTS -v /opt:/opt"
      [ -d /nix ]                 && MOUNTS="$MOUNTS -v /nix:/nix"
      [ -d /var/log/journal ]     && MOUNTS="$MOUNTS -v /var/log/journal:/var/log/journal"
      MOUNTS="$MOUNTS -v /etc/hosts:/etc/hosts:ro"
      MOUNTS="$MOUNTS -v /etc/resolv.conf:/etc/resolv.conf:ro"
      MOUNTS="$MOUNTS -v /etc/hostname:/etc/hostname:ro"

      FLAGS="--privileged --network host --pid host --ipc host"
      FLAGS="$FLAGS --security-opt label=disable --security-opt apparmor=unconfined"
      FLAGS="$FLAGS --pids-limit=-1 --ulimit host"
      [ "$RUNTIME" = "podman" ] && FLAGS="$FLAGS --userns keep-id"

      "$DOCKER" run -it --rm \
        --name diego-gui \
        --hostname "${SYS_HOSTNAME}-gui" \
        $FLAGS $MOUNTS \
        -w "$HOME_DIR" \
        -e HOME="$HOME_DIR" -e USER="${USER:-root}" \
        -e TERM="${TERM:-xterm-256color}" \
        -e DISPLAY="${DISPLAY:-}" \
        -e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
        -e XDG_RUNTIME_DIR="$_XDG" \
        -e DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
        -e PULSE_SERVER="${PULSE_SERVER:-}" \
        -e SHELL=fish \
        -e PATH="$_NIX_PATH" \
        "$IMG" bash -c "$SHELL_CMD"
      ;;

    tty)
      _CMD="${_extra_cmd:-bash}"
      MOUNTS="-v $HOME_DIR:$HOME_DIR"
      [ -S /var/run/docker.sock ] && MOUNTS="$MOUNTS -v /var/run/docker.sock:/var/run/docker.sock"
      [ -d /etc/wireguard ]       && MOUNTS="$MOUNTS -v /etc/wireguard:/etc/wireguard:ro"
      [ -d /opt ]                 && MOUNTS="$MOUNTS -v /opt:/opt"

      FLAGS="--privileged --network host --pid host"

      "$DOCKER" run --rm \
        --name diego-tty \
        --hostname "${SYS_HOSTNAME}-tty" \
        $FLAGS $MOUNTS \
        -w "$HOME_DIR" \
        -e HOME="$HOME_DIR" -e USER="${USER:-root}" \
        -e TERM=dumb \
        -e PATH="$_NIX_PATH" \
        "$IMG" bash -c "${_HELLO}
$_CMD"
      ;;

    *) echo "Unknown profile: $_profile (use: cli, gui, or tty)"; exit 1 ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════
# GIT CLONE — public (HTTPS) and private (SSH)
# ═══════════════════════════════════════════════════════════════════

_gcl_repos() {
  _proto="$1"  # https or ssh
  _target="${HOME:-/root}/git"
  mkdir -p "$_target"

  # Public repos (HTTPS or SSH)
  _public="unix cloud cloud-data tools front"
  # Private repos (SSH only, fail silent on HTTPS)
  _private="vault notes"

  printf "\n\033[1;36m── git clone (%s) ──\033[0m\n" "$_proto"

  for _name in $_public $_private; do
    case "$_proto" in
      https) _url="https://github.com/diegonmarcos/${_name}.git" ;;
      ssh)   _url="git@github.com:diegonmarcos/${_name}.git" ;;
    esac

    if [ -d "$_target/$_name" ]; then
      printf "  \033[1;33m%-14s\033[0m exists, pulling... "  "$_name"
      git -C "$_target/$_name" pull --ff-only 2>&1 | head -1
    else
      printf "  \033[1;32m%-14s\033[0m cloning... " "$_name"
      git clone "$_url" "$_target/$_name" 2>/dev/null && echo "done" || echo "skipped (no access)"
    fi
  done
  printf "\n"
}

do_gcl_https() { _gcl_repos https; }
do_gcl_ssh()   { _gcl_repos ssh; }

do_konsole_cfg() {
  _DTK="$(cd "$(dirname "$0")" && pwd)"
  _src_qc="$_DTK/4-quick-cmds/konsolequickcommandsconfig"
  _src_ssh="$_DTK/4-quick-cmds/konsolesshconfig"
  _dst_qc="${HOME:-/root}/.config/konsolequickcommandsconfig"
  _dst_ssh="${HOME:-/root}/.config/konsolesshconfig"

  printf "\n\033[1;36m── Konsole Quick Commands + SSH Config ──\033[0m\n"

  if [ ! -f "$_src_qc" ] || [ ! -f "$_src_ssh" ]; then
    echo "  ERROR: asset files not found in $_DTK/4-quick-cmds/"
    echo "  Run: git clone https://github.com/diegonmarcos/tools.git ~/git/tools"
    return 1
  fi

  cp "$_src_qc" "$_dst_qc" && printf "  \033[1;32minstalled\033[0m %s\n" "$_dst_qc"
  cp "$_src_ssh" "$_dst_ssh" && printf "  \033[1;32minstalled\033[0m %s\n" "$_dst_ssh"
  printf "\n  Restart Konsole to pick up changes.\n\n"
}

# ═══════════════════════════════════════════════════════════════════
# C) CONNECT — unified dashboard (git/mounts/sync/servers)
# ═══════════════════════════════════════════════════════════════════

do_connect() {
  _connect_sh="$(cd "$(dirname "$0")" && pwd)/3-dashboards/connect.sh"
  if [ -f "$_connect_sh" ]; then
    sh "$_connect_sh" "$@"
  else
    echo "connect.sh not found at: $_connect_sh"
    echo "Clone tools repo: git clone https://github.com/diegonmarcos/tools.git ~/git/tools"
    exit 1
  fi
}

do_top_batch() {
  printf "\n\033[1;36m── top (batch mode) ──\033[0m\n\n"
  top -b -n 1 | head -40
}

do_local_iotop() {
  printf "\n\033[1;36m── iotop ──\033[0m\n\n"
  sudo iotop 2>/dev/null || sudo iotop-c 2>/dev/null || { echo "iotop not found"; return 1; }
}

do_sysstat() {
  _cmd="${1:-}"
  if [ -z "$_cmd" ]; then
    pick "sysstat:" iostat mpstat pidstat sar
    [ "$PICK" = "back" ] && return 0
    _cmd="$PICK"
  fi
  printf "\n\033[1;36m── %s ──\033[0m\n\n" "$_cmd"
  case "$_cmd" in
    iostat)  iostat -xz 2 5 2>/dev/null || echo "iostat not found (install sysstat)" ;;
    mpstat)  mpstat -P ALL 2 5 2>/dev/null || echo "mpstat not found (install sysstat)" ;;
    pidstat) pidstat -u -d 2 5 2>/dev/null || echo "pidstat not found (install sysstat)" ;;
    sar)     sar -u -r -d 1 10 2>/dev/null || echo "sar not found (install sysstat)" ;;
    *)       echo "Unknown: $_cmd" ;;
  esac
}

do_local_btop() {
  printf "\n\033[1;36m── local btop ──\033[0m\n\n"
  _s="local-btop"
  tmux kill-session -t "$_s" 2>/dev/null || true
  tmux new-session -d -s "$_s" "btop 2>/dev/null || htop 2>/dev/null || top; read"
  _tmux_enable_titles "$_s"
  tmux select-pane -t "$_s" -t 1 -T "local / btop"
  tmux attach-session -t "$_s"
}

do_batch_htop() {
  printf "\n\033[1;36m── remote btop-dash ──\033[0m\n"
  printf "  4-pane: htop on all VMs\n\n"
  _s="remote-btop"
  tmux kill-session -t "$_s" 2>/dev/null || true
  _first=true
  for _vm in gcp-proxy oci-mail oci-analytics oci-apps; do
    if $_first; then
      tmux new-session -d -s "$_s" "ssh $_vm -t 'btop 2>/dev/null || htop 2>/dev/null || top'; read"
      _first=false
    else
      tmux split-window -t "$_s" "ssh $_vm -t 'btop 2>/dev/null || htop 2>/dev/null || top'; read"
    fi
  done
  tmux select-layout -t "$_s" tiled
  _tmux_enable_titles "$_s"
  _i=1; for _vm in gcp-proxy oci-mail oci-analytics oci-apps; do
    tmux select-pane -t "$_s" -t $_i -T "$_vm / ssh $_vm -t btop"
    _i=$((_i + 1))
  done
  tmux attach-session -t "$_s"
}

do_journal_dash() {
  _sub="${1:-}"
  R='\033[0m'; C='\033[1;36m'; D='\033[0;90m'

  if [ -z "$_sub" ]; then
    show_menu_header
    pick "Journal dashboard:" transport priority unit
    [ "$PICK" = "back" ] && return 0
    _sub="$PICK"
  fi

  case "$_sub" in
    transport|t) _journal_dash_transport ;;
    priority|p)  _journal_dash_priority ;;
    unit|u)      _journal_dash_unit ;;
    *)           echo "Unknown: $_sub (use: transport, priority, unit)" ;;
  esac
}

# Helper: enable pane titles for a session
_tmux_enable_titles() {
  tmux set-option -t "$1" pane-border-status top
  tmux set-option -t "$1" pane-border-format " #{pane_title} "
}

_journal_dash_transport() {
  printf "\n\033[1;36m── journal-dash-transport ──\033[0m\n"
  printf "  2x2: kernel | syslog | stdout | journal\n\n"
  _s="jdash-transport"
  tmux kill-session -t "$_s" 2>/dev/null || true
  tmux new-session -d -s "$_s" \
    "journalctl _TRANSPORT=kernel -f --no-pager -o short-iso; read"
  tmux split-window -t "$_s" \
    "journalctl _TRANSPORT=syslog -f --no-pager -o short-iso; read"
  tmux split-window -t "$_s" \
    "journalctl _TRANSPORT=stdout -f --no-pager -o short-iso; read"
  tmux split-window -t "$_s" \
    "journalctl _TRANSPORT=journal -f --no-pager -o short-iso; read"
  tmux select-layout -t "$_s" tiled
  _tmux_enable_titles "$_s"
  _i=1; for _t in "kernel / _TRANSPORT=kernel" "syslog / _TRANSPORT=syslog" "stdout / _TRANSPORT=stdout" "journal / _TRANSPORT=journal"; do
    tmux select-pane -t "$_s" -t $_i -T "$_t"; _i=$((_i + 1))
  done
  tmux attach-session -t "$_s"
}

_journal_dash_priority() {
  printf "\n\033[1;36m── journal-dash-priority ──\033[0m\n"
  printf "  8 panes: emerg(0) | alert(1) | crit(2) | err(3) | warn(4) | notice(5) | info(6) | debug(7)\n\n"
  _s="jdash-priority"
  tmux kill-session -t "$_s" 2>/dev/null || true
  _names="emerg alert crit err warning notice info debug"
  _i=0; _first=true
  for _name in $_names; do
    _cmd="journalctl -p $_i..$_i -f --no-pager -o short-iso; read"
    if $_first; then
      tmux new-session -d -s "$_s" "$_cmd"
      _first=false
    else
      tmux split-window -t "$_s" "$_cmd"
      tmux select-layout -t "$_s" tiled
    fi
    _i=$((_i + 1))
  done
  tmux select-layout -t "$_s" tiled
  _tmux_enable_titles "$_s"
  _i=1; _p=0
  for _name in $_names; do
    tmux select-pane -t "$_s" -t $_i -T "$_name / -p $_p..$_p"
    _i=$((_i + 1)); _p=$((_p + 1))
  done
  tmux attach-session -t "$_s"
}

_journal_dash_unit() {
  printf "\n\033[1;36m── journal-dash-unit ──\033[0m\n"
  printf "  2x2: kernel+network+ssh+storage | system | docker | others\n\n"
  _s="jdash-unit"
  tmux kill-session -t "$_s" 2>/dev/null || true
  tmux new-session -d -s "$_s" \
    "journalctl -k -u NetworkManager -u wpa_supplicant -u sshd -u ssh -u rescue-ssh -u udisks2 -u fstrim -f --no-pager -o short-iso; read"
  tmux split-window -t "$_s" \
    "journalctl -u nix-daemon -u nix-gc -u earlyoom -u disk-watchdog -u systemd-logind -u systemd-timesyncd -u thermald -u polkit -f --no-pager -o short-iso; read"
  tmux split-window -t "$_s" \
    "journalctl -u docker -f --no-pager -o short-iso; read"
  tmux split-window -t "$_s" \
    "journalctl -f --no-pager -o short-iso _TRANSPORT=stdout; read"
  tmux select-layout -t "$_s" tiled
  _tmux_enable_titles "$_s"
  _i=1; for _t in \
    "kernel+net+ssh+storage / -k -u NetworkManager -u sshd ..." \
    "system / -u nix-daemon -u earlyoom -u systemd-logind ..." \
    "docker / -u docker" \
    "others / _TRANSPORT=stdout"; do
    tmux select-pane -t "$_s" -t $_i -T "$_t"; _i=$((_i + 1))
  done
  tmux attach-session -t "$_s"
}

do_docker_stats_dash() {
  printf "\n\033[1;36m── remote docker-stats ──\033[0m\n"
  printf "  4-pane: docker stats on all VMs\n\n"
  _s="remote-docker-stats"
  tmux kill-session -t "$_s" 2>/dev/null || true
  _first=true
  for _vm in gcp-proxy oci-mail oci-analytics oci-apps; do
    _cmd="ssh $_vm -t 'docker stats 2>/dev/null || echo no docker'; read"
    if $_first; then
      tmux new-session -d -s "$_s" "$_cmd"
      _first=false
    else
      tmux split-window -t "$_s" "$_cmd"
    fi
  done
  tmux select-layout -t "$_s" tiled
  _tmux_enable_titles "$_s"
  _i=1; for _vm in gcp-proxy oci-mail oci-analytics oci-apps; do
    tmux select-pane -t "$_s" -t $_i -T "$_vm / docker stats"
    _i=$((_i + 1))
  done
  tmux attach-session -t "$_s"
}

do_journal_watch_n35() {
  printf "\n\033[1;36m── journal watch (last 35, refresh 5s) ──\033[0m\n\n"
  watch -n 5 -c "journalctl -n 35 --no-pager -o short-iso"
}

do_remote_journal() {
  printf "\n\033[1;36m── remote journal-dash ──\033[0m\n"
  printf "  4-pane: journal -f on all VMs\n\n"
  _s="remote-journal"
  tmux kill-session -t "$_s" 2>/dev/null || true
  _first=true
  for _vm in gcp-proxy oci-mail oci-analytics oci-apps; do
    _cmd="ssh $_vm -t 'journalctl -f --no-pager -o short-iso 2>/dev/null || tail -f /var/log/syslog 2>/dev/null || echo no journal'; read"
    if $_first; then
      tmux new-session -d -s "$_s" "$_cmd"
      _first=false
    else
      tmux split-window -t "$_s" "$_cmd"
    fi
  done
  tmux select-layout -t "$_s" tiled
  _tmux_enable_titles "$_s"
  _i=1; for _vm in gcp-proxy oci-mail oci-analytics oci-apps; do
    tmux select-pane -t "$_s" -t $_i -T "$_vm / ssh $_vm journalctl -f"
    _i=$((_i + 1))
  done
  tmux attach-session -t "$_s"
}

# ═══════════════════════════════════════════════════════════════════
# QUICK COMMANDS — delegates to cloud-container-orchestrator.sh
# ═══════════════════════════════════════════════════════════════════

_QC="bash ${HOME:-/root}/git/tools/1-aliases/engines/cloud-container-orchestrator/cloud-container-orchestrator.sh"

do_qc_vm() {
  _vm="${1:-}"
  R='\033[0m'; C='\033[1;36m'; Y='\033[1;33m'; D='\033[0;90m'
  if [ -z "$_vm" ]; then
    show_menu_header
    pick "VM:" gcp-proxy oci-mail oci-analytics oci-apps gcp-t4
    [ "$PICK" = "back" ] && return 0
    _vm="$PICK"
  fi
  printf "\n${C}── VM: $_vm ──${R}\n"
  pick "Command:" \
    htop journalctl-f \
    journal-docker journal-sshd journal-wg journal-cinit journal-kernel journal-errors \
    systemctl-status systemctl-list \
    docker-start docker-stop docker-ps docker-stats docker-exec \
    dashboard \
    oci-start oci-stop oci-reset oci-serial \
    gcloud-start gcloud-stop gcloud-reset gcloud-serial
  [ "$PICK" = "back" ] && return 0
  case "$PICK" in
    dashboard)       $_QC vm-dashboard "$_vm" ;;
    oci-*|gcloud-*)  $_QC "vm-$PICK" "$_vm" ;;
    *)               $_QC "vm-$PICK" "$_vm" ;;
  esac
}

do_qc_ssh() {
  _vm="${1:-}"
  if [ -z "$_vm" ]; then
    show_menu_header
    pick "SSH to:" gcp-proxy oci-mail oci-analytics oci-apps gcp-t4
    [ "$PICK" = "back" ] && return 0
    _vm="$PICK"
  fi
  printf "\n\033[1;36m── SSH: $_vm ──\033[0m\n"
  ssh "$_vm"
}

do_qc_orchestrate() {
  R='\033[0m'; C='\033[1;36m'
  printf "\n${C}── Orchestration (all VMs) ──${R}\n"
  pick "Command:" \
    mode-ssh mode-dropbear mode-serial mode-status \
    htop journalctl-f \
    journal-docker journal-sshd journal-wg journal-cinit journal-kernel journal-errors \
    systemctl-status systemctl-list \
    docker-start docker-stop docker-ps docker-stats \
    dashboard-stats dashboard-journal script-push
  [ "$PICK" = "back" ] && return 0
  case "$PICK" in
    mode-*) $_QC "$PICK" ;;
    *)      $_QC "all-$PICK" ;;
  esac
}

do_qc_local() {
  R='\033[0m'; C='\033[1;36m'
  printf "\n${C}── Local ──${R}\n"
  pick "Command:" \
    htop journalctl-f \
    journal-docker journal-sshd journal-wg journal-cinit journal-kernel journal-errors \
    systemctl-status systemctl-list \
    docker-start docker-stop docker-ps docker-stats docker-exec
  [ "$PICK" = "back" ] && return 0
  $_QC "local-$PICK"
}

do_qc_desktop() {
  R='\033[0m'; C='\033[1;36m'
  printf "\n${C}── Desktop ──${R}\n"
  pick "Command:" \
    tui dtk dtk-install dtk-docker dtk-git-clone dtk-info dtk-commands dtk-ssh \
    desktop-htop hm-switch nixos-switch \
    git-status-all wg-status docker-ps-local free-mem disk-usage konsole-script-push
  [ "$PICK" = "back" ] && return 0
  $_QC "$PICK"
}

do_qc_vps() {
  _cat="${1:-}"
  R='\033[0m'; C='\033[1;36m'
  printf "\n${C}── VPS / Cloud ──${R}\n"
  if [ -z "$_cat" ]; then
    pick "Category:" cloud gh-actions gh-repos gh-registry
    [ "$PICK" = "back" ] && return 0
    _cat="$PICK"
  fi
  case "$_cat" in
    cloud)
      pick "Cloud:" oci-list oci-details oci-vnics gcloud-list gcloud-details gcloud-billing
      [ "$PICK" = "back" ] && return 0
      $_QC "$PICK" ;;
    gh-actions)
      pick "GH Actions:" runs-cloud failed-cloud log-cloud workflows runs-unix runs-front
      [ "$PICK" = "back" ] && return 0
      $_QC "gha-$PICK" ;;
    gh-repos)
      pick "GH Repos:" status list prs issues commits
      [ "$PICK" = "back" ] && return 0
      $_QC "gh-${PICK}" ;;
    gh-registry)
      pick "GHCR:" list versions count inspect latest visibility
      [ "$PICK" = "back" ] && return 0
      $_QC "ghcr-$PICK" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════
# D) OTHERS — ssh, git-clone, install, commands, info
# ═══════════════════════════════════════════════════════════════════
# D) OTHERS — all logic in 5-infos/ modules, these are thin delegators
# ═══════════════════════════════════════════════════════════════════

do_all_commands() { set +x 2>/dev/null
  R='\033[0m'; C='\033[1;36m'; Y='\033[1;33m'; D='\033[0;90m'
  printf "\n${C}── All DTK Commands ──${R}\n"
  # Two-column: shortcode + description
  _cmds="
10|aliases (3-col)
11|tools (5-col compact)
11a|tools table (5-col)
11b|tools help (1-col+desc)
12|info
12a|info (installed tools)
12b|engines (build scripts)
20|deb setups
20a|deb nix-cli
20b|deb nix-gui
20c|deb nix-tty
20d|deb apt-cli
20e|deb apt-gui
20f|deb apt-tty
21|nixos setups
21a|nixos hm-cli
21b|nixos hm-gui
21c|nixos hm-tty
22|shell setup
22a|fish+tools (sudo)
22b|fish (no sudo)
22c|git clone (https)
22d|git clone (ssh)
22e|konsole quick-cmds install
30|local btop
31|journal-dash (picker)
31a|journal transport (4-pane)
31b|journal priority (8-pane)
31c|journal unit (4-pane)
31d|journal watch -n35
32|connect dashboard
33|remote btop-dash (4-pane)
34|remote journal-dash (4-pane)
35|remote docker-stats (4-pane)
40|VM quick-cmds (picker)
40a|VM gcp-proxy
40b|VM oci-mail
40c|VM oci-analytics
40d|VM oci-apps
40e|VM gcp-t4
40f|orchestrate (all VMs)
40g|local commands
40h|desktop commands
40i|vps cloud (oci/gcloud)
40j|vps gh-actions
40k|vps gh-repos
40l|vps gh-registry
41|SSH (picker)
41a|SSH gcp-proxy
41b|SSH oci-mail
41c|SSH oci-analytics
41d|SSH oci-apps
41e|SSH gcp-t4
41f|SSH github
50|help
51|webhooks
52|commands (this list)
"
  echo "$_cmds" | awk -F'|' '
    BEGIN { C="\033[1;36m"; Y="\033[1;33m"; R="\033[0m"; n=0 }
    /\|/ { keys[n]=$1; vals[n]=$2; n++ }
    END {
      for (i=0; i<n; i+=2) {
        gsub(/^ +/,"",keys[i]); gsub(/^ +/,"",vals[i])
        left = sprintf("  " Y "%-6s" R "%-28s", keys[i], vals[i])
        if (i+1 < n) {
          gsub(/^ +/,"",keys[i+1]); gsub(/^ +/,"",vals[i+1])
          printf "  " Y "%-6s" R "%-28s" Y "%-6s" R "%s\n", keys[i], vals[i], keys[i+1], vals[i+1]
        } else {
          printf "  " Y "%-6s" R "%s\n", keys[i], vals[i]
        }
      }
      printf "\n"
    }
  '
}

do_ssh()       { sh "$_OTHERS_DIR/ssh/ssh.sh" "$@"; }

do_git_clone() { sh "$_OTHERS_DIR/git-clone/git-clone.sh" "$@"; }

do_install()   { sh "$_OTHERS_DIR/install/install.sh" "$@"; }
do_commands()  { sh "$_OTHERS_DIR/commands/commands.sh" "$@"; }
do_info()      { sh "$_ALIASES_DIR/info/info.sh" "$@"; }
do_engines()   { sh "$_ALIASES_DIR/engines/engines.sh" "$@"; }
do_webhooks()  { sh "$_OTHERS_DIR/webhooks/webhooks.sh" "$@"; }
do_others()    { sh "$_OTHERS_DIR/others.sh" "$@"; }

# ═══════════════════════════════════════════════════════════════════
# E) HELP
# ═══════════════════════════════════════════════════════════════════

do_help() { set +x 2>/dev/null
  R='\033[0m'; C='\033[1;36m'; Y='\033[1;33m'; D='\033[0;90m'; W='\033[1;37m'
  printf "\n${C}Diego's Toolkit (DTK)${R} — unified CLI\n\n"
  printf "${Y}Usage:${R}\n"
  printf "  dtk.sh                        ${D}# interactive menu${R}\n"
  printf "  dtk.sh <command> [args]        ${D}# direct${R}\n\n"
  printf "${Y}Main Menu:${R}\n"
  printf "  ${W}a) aliases${R}      Toolchain list — all aliases/functions by category\n"
  printf "  ${W}b) setups${R}       Containers, NixOS, shell setup\n"
  printf "  ${W}c) dashboards${R}   Local & remote monitoring dashboards\n"
  printf "  ${W}d) commands${R}     SSH, git-clone, install, commands, info\n"
  printf "  ${W}e) infos${R}        Help, webhooks, commands\n\n"
  printf "${Y}Direct Commands:${R}\n"
  printf "  dtk.sh aliases                  ${D}# all shell aliases (3-column)${R}\n"
  printf "  dtk.sh tools                    ${D}# all installed CLI tools (5-column)${R}\n"
  printf "  dtk.sh containers [img] [prof] ${D}# deb-nix cli | deb-apt gui${R}\n"
  printf "  dtk.sh btop                    ${D}# local btop (tmux)${R}\n"
  printf "  dtk.sh journal-dash [t|p|u]   ${D}# local journal (transport/priority/unit)${R}\n"
  printf "  dtk.sh connect                 ${D}# cloud connect dashboard${R}\n"
  printf "  dtk.sh btop-dash              ${D}# htop on all VMs (tmux 2x2)${R}\n"
  printf "  dtk.sh remote-journal         ${D}# journal on all VMs (tmux 2x2)${R}\n"
  printf "  dtk.sh ssh                     ${D}# GCP serial/ssh/rescue${R}\n"
  printf "  dtk.sh git-clone [path]        ${D}# clone all repos${R}\n"
  printf "  dtk.sh install                 ${D}# install dev toolchain${R}\n"
  printf "  dtk.sh commands [n]            ${D}# run quick command by number${R}\n"
  printf "  dtk.sh info                    ${D}# show installed tools${R}\n"
  printf "  dtk.sh engines                 ${D}# launch build engines${R}\n"
  printf "  dtk.sh fix-journal             ${D}# silence journal spam${R}\n"
  printf "  dtk.sh full-rescue             ${D}# flush iptables + restart sshd/wg${R}\n\n"
}

# ═══════════════════════════════════════════════════════════════════
# ENTRY POINT — set -x starts here (after quiet setup)
# ═══════════════════════════════════════════════════════════════════
_resolve_shortcode() {
  _code="$1"
  _major=$(echo "$_code" | cut -c1)
  _minor=$(echo "$_code" | cut -c2)
  _rest=$(echo "$_code" | cut -c3-)
  case "$_major" in
    1) # cmds-local
      case "$_minor" in
        0) do_aliases ;; 1) sh "$_OTHERS_DIR/webhooks/webhooks.sh" ;;
        2) # commands: 12 = menu, 120-1225 = direct run
          if [ -n "$_rest" ]; then do_commands "$_rest"; else do_commands; fi ;;
        *) do_aliases ;;
      esac; return 0 ;;
    2) # cmds-cloud (quick-cmds + ssh)
      case "$_minor$_rest" in
        0) do_qc_vm ;;
        0a) do_qc_vm gcp-proxy ;; 0b) do_qc_vm oci-mail ;; 0c) do_qc_vm oci-analytics ;; 0d) do_qc_vm oci-apps ;; 0e) do_qc_vm gcp-t4 ;;
        0f) do_qc_orchestrate ;; 0g) do_qc_local ;; 0h) do_qc_desktop ;;
        0i) do_qc_vps cloud ;; 0j) do_qc_vps gh-actions ;; 0k) do_qc_vps gh-repos ;; 0l) do_qc_vps gh-registry ;;
        1) do_qc_ssh ;;
        1a) do_qc_ssh gcp-proxy ;; 1b) do_qc_ssh oci-mail ;; 1c) do_qc_ssh oci-analytics ;; 1d) do_qc_ssh oci-apps ;; 1e) do_qc_ssh gcp-t4 ;;
        1f) ssh github.com ;;
        *) echo "Invalid shortcode: $_code" ;;
      esac; return 0 ;;
    3) # dashboards
      case "$_minor$_rest" in
        # local monitors
        0) do_local_btop ;; 0a) do_local_btop ;; 0b) do_local_iotop ;; 0c) do_top_batch ;;
        # sysstat
        1) do_sysstat ;; 1a) do_sysstat iostat ;; 1b) do_sysstat mpstat ;; 1c) do_sysstat pidstat ;; 1d) do_sysstat sar ;;
        # journal
        2) do_journal_dash ;; 2a) do_journal_dash transport ;; 2b) do_journal_dash priority ;; 2c) do_journal_dash unit ;; 2d) do_journal_watch_n35 ;;
        # connect + remote
        3) do_connect ;; 4) do_batch_htop ;; 5) do_remote_journal ;; 6) do_docker_stats_dash ;;
        *) do_connect "$_minor$_rest" ;;
      esac; return 0 ;;
    4) # setups (containers + shell + git)
      _dtk_dir="$(cd "$(dirname "$0")" && pwd)"
      _containers_sh="$_dtk_dir/2-setups/containers.sh"
      case "$_minor$_rest" in
        0) sh "$_containers_sh" ;;
        0a) sh "$_containers_sh" 1 ;; 0b) sh "$_containers_sh" 2 ;; 0c) sh "$_containers_sh" 3 ;;
        0d) sh "$_containers_sh" 4 ;; 0e) sh "$_containers_sh" 5 ;; 0f) sh "$_containers_sh" 6 ;;
        1) echo "41a hm-cli  41b hm-gui  41c hm-tty" ;;
        1a) sh "$_containers_sh" 7 ;; 1b) sh "$_containers_sh" 8 ;; 1c) sh "$_containers_sh" 9 ;;
        2) echo "42a fish+tools  42b fish  42c konsole-cfg" ;;
        2a) sh "$_dtk_dir/2-setups/fish-tools.sh" ;;
        2b) sh "$_dtk_dir/2-setups/fish-shell.sh" ;;
        2c) do_konsole_cfg ;;
        3) echo "43a gcl-https  43b gcl-ssh" ;;
        3a) do_gcl_https ;; 3b) do_gcl_ssh ;;
        *) echo "Invalid shortcode: $_code" ;;
      esac; return 0 ;;
    5) # infos
      case "$_minor$_rest" in
        0) do_help ;; 1) do_tools ;; 1a) do_tools ;; 1b) do_tools_help ;;
        2) do_info ;; 2a) do_info ;; 2b) do_engines ;;
        *) do_help ;;
      esac; return 0 ;;
  esac
  return 1
}

set +x 2>/dev/null
if [ $# -ge 1 ]; then
  case "$1" in
    # Shortcodes: 2+ digits (e.g. 16, 44, 448, 4415)
    [1-5][0-9a-f]*) _resolve_shortcode "$1" ;;
    aliases)        do_aliases ;;
    tools)          do_tools ;;
    tools-help)     do_tools_help ;;
    gcl-https)      do_gcl_https ;;
    gcl-ssh)        do_gcl_ssh ;;
    git-clone)      do_gcl_https ;;
    btop)           do_local_btop ;;
    batch-htop|btop-dash) do_batch_htop ;;
    journal-dash)   do_journal_dash "${2:-}" ;;
    journal-transport) do_journal_dash transport ;;
    journal-priority)  do_journal_dash priority ;;
    journal-unit)      do_journal_dash unit ;;
    remote-journal) do_remote_journal ;;
    containers)     shift; sh "$(cd "$(dirname "$0")" && pwd)/2-setups/containers.sh" "$@" ;;
    docker-run)     shift; sh "$(cd "$(dirname "$0")" && pwd)/2-setups/containers.sh" "$@" ;;
    docker-start)   sh "$(cd "$(dirname "$0")" && pwd)/2-setups/containers.sh" deb-nix cli ;;
    connect)        shift; do_connect "$@" ;;
    others)         shift; do_others "$@" ;;
    ssh)            do_ssh ;;
    git-clone-old)  do_git_clone "${2:-$HOME/git}" ;;
    install)        do_install ;;
    commands)       do_commands "${2:-}" ;;
    info)           do_info ;;
    engines)        do_engines "${2:-}" ;;
    fix-journal)    do_commands 14 ;;
    full-rescue)    do_commands 15 ;;
    refresh|r|pull) _repo_dir="$(cd "$(dirname "$0")" && pwd)"; echo "Pulling latest from remote..."; git -C "$_repo_dir" fetch --all && git -C "$_repo_dir" reset --hard "origin/$(git -C "$_repo_dir" rev-parse --abbrev-ref HEAD)" && echo "Updated to $(git -C "$_repo_dir" log --oneline -1)" ;;
    help|--help|-h) do_help ;;
    *)              do_help; exit 1 ;;
  esac
else
  set +x 2>/dev/null
  while true; do
    show_menu_header
    printf "> "
    read -r _input
    case "$_input" in
      1)  do_aliases; do_tools ;;
      2)  printf "\n  20 quick-cmds  21 ssh\n\n" ;;
      3)  do_connect ;;
      4)  sh "$(cd "$(dirname "$0")" && pwd)/2-setups/containers.sh" ;;
      5)  do_help ;;
      b|back) continue ;;
      r|refresh) _repo_dir="$(cd "$(dirname "$0")" && pwd)"; echo "Pulling latest from remote..."; git -C "$_repo_dir" fetch --all && git -C "$_repo_dir" reset --hard origin/$(git -C "$_repo_dir" rev-parse --abbrev-ref HEAD) && echo "Updated to $(git -C "$_repo_dir" log --oneline -1)" ;;
      q)  echo "Bye."; exit 0 ;;
      # Shortcodes: 2+ digits — route through resolver
      [1-5][0-9a-f]*) _resolve_shortcode "$_input" ;;
      *)  echo "Invalid — enter 1-5, shortcode (e.g. 16, 448), b/q/r" ;;
    esac
  done
fi
