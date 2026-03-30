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
export PATH="/usr/bin:/usr/sbin:/usr/local/bin:/bin:/sbin:/nix/var/nix/profiles/default/bin:${HOME:-/root}/.nix-profile/bin:/run/current-system/sw/bin:$PATH"

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
  printf "  ${Y}host${R}  ${W}%-20s${R}  ${Y}os${R}  ${W}%s${R}\n" "$SYS_HOSTNAME" "$SYS_DISTRO"
  printf "  ${Y}arch${R}  ${W}%-20s${R}  ${Y}kernel${R}  ${W}%s${R}\n" "$SYS_ARCH" "$_kern"
  printf "  ${Y}cpu${R}   ${W}%-20s${R}  ${Y}ram${R}  ${W}%sMB${R}\n" "${SYS_CPUS} cores" "$SYS_RAM_MB"
  printf "  ${Y}pkg${R}   ${W}%-20s${R}  ${Y}init${R}  ${W}%s${R}\n" "$SYS_PKG" "$SYS_INIT"
  printf "  ${Y}nix${R}   $nix_icon                     ${Y}docker${R}  $docker_icon\n"
  printf "  ${D}──────────────────────────────────────────────────────────────────────────────────${R}\n"
  printf '\n'
}

show_menu_header() { set +x 2>/dev/null
  R='\033[0m'; C='\033[1;36m'; D='\033[0;90m'
  show_banner

  printf "  ${C}1) aliases${R}        ${C}2) containers${R}    ${C}3) connect${R}       ${C}4) others${R}        ${C}5) help${R}\n"
  printf "  ${D}11 modern-cli${R}    ${D}21 deb-nix${R}       ${D}31 git${R}            ${D}41 ssh${R}            ${D}usage${R}\n"
  printf "  ${D}12 navigation${R}    ${D}22 deb-apt${R}       ${D}32 mounts${R}         ${D}42 git-clone${R}      ${D}commands${R}\n"
  printf "  ${D}13 safety${R}        ${D}23 cli${R}           ${D}33 sync${R}           ${D}43 install${R}        \n"
  printf "  ${D}14 python${R}        ${D}24 gui${R}           ${D}34 servers${R}        ${D}44 commands${R}       \n"
  printf "  ${D}15 system${R}        ${D}25 tty${R}                             ${D}45 info${R}           \n"
  printf "  ${D}16 git${R}                                                ${D}46 engines${R}        \n"
  printf "  ${D}17 docker${R}                                                            \n"
  printf "  ${D}18 session${R}                                                           \n"
  printf "  ${D}19 web-terminal${R}                                                      \n"
  printf "  ${D}1a misc${R}                                                              \n"
  printf "  ${D}1b functions${R}                                                         \n"
  printf "  ${D}──────────────────────────────────────────────────────────────────────────────────${R}\n"
  printf "  ${D}(b)ack  (q)uit  1-5 menu  11-46 shortcode${R}\n"
  printf "\n"
}

detect_system

# ═══════════════════════════════════════════════════════════════════
# VM Map (POSIX: case statement instead of associative array)
# ═══════════════════════════════════════════════════════════════════

PROJECT="diegonmarcos-infra-prod"

resolve_vm() {
  case "$1" in
    gcp-proxy) INSTANCE="arch-1";          ZONE="us-central1-a" ;;
    gcp-t4)    INSTANCE="ollama-spot-gpu"; ZONE="us-central1-a" ;;
    *) echo "Unknown VM: $1 (available: gcp-proxy gcp-t4)"; exit 1 ;;
  esac
}

REPOS="cloud:https://github.com/diegonmarcos/cloud.git
cloud-data:https://github.com/diegonmarcos/cloud-data.git
unix:https://github.com/diegonmarcos/unix.git
front:https://github.com/diegonmarcos/front.git
vault:https://github.com/diegonmarcos/vault.git"

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
  R='\033[0m'; C='\033[1;36m'; Y='\033[1;33m'; D='\033[0;90m'
  _SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  _ALIASES_JSON="$_SCRIPT_DIR/1-aliases/aliases.json"

  _sub="${1:-}"
  if [ -z "$_sub" ]; then
    while true; do
      show_menu_header
      pick "Alias category:" modern-cli navigation safety python system git docker session web-terminal misc functions all
      [ "$PICK" = "back" ] && return 0
      _sub="$PICK"
      break
    done
  fi

  # Render a category from aliases.json
  _render_category() {
    _cat="$1"
    _title="$2"
    printf "\n${C}── %s ──${R}\n" "$_title"
    # Handle nested objects (git has abbrs+functions, functions has search)
    jq -r ".[\"$_cat\"] | paths(scalars) as \$p | \"\(\$p | join(\".\")) \(getpath(\$p))\"" "$_ALIASES_JSON" 2>/dev/null | while read -r _path _rest; do
      _key="${_path##*.}"
      _val="$_rest"
      # Skip sub-object names, only print leaf values
      printf "  ${Y}%-14s${R} %s\n" "$_key" "$_val"
    done
  }

  case "$_sub" in
    modern-cli)    _render_category "modern-cli" "Modern CLI Replacements" ;;
    navigation)    _render_category "navigation" "Navigation" ;;
    safety)        _render_category "safety" "Safety Aliases" ;;
    python)        _render_category "python" "Python" ;;
    system)        _render_category "system" "System" ;;
    git)           _render_category "git" "Git" ;;
    docker)        _render_category "docker" "Docker Abbreviations" ;;
    session)       _render_category "session" "Session (Plasma 6)" ;;
    web-terminal)  _render_category "web-terminal" "Web Terminal" ;;
    misc)          _render_category "misc" "Misc" ;;
    functions)     _render_category "functions" "Functions" ;;
    all)
      for _c in modern-cli navigation safety python system git docker session web-terminal misc functions; do
        _render_category "$_c" "$_c"
      done
      ;;
  esac
  printf "\n"
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
# C) CONNECT — unified dashboard (git/mounts/sync/servers)
# ═══════════════════════════════════════════════════════════════════

do_connect() {
  _connect_sh="${HOME:-/home/diego}/git/tools/3-connect/connect.sh"
  if [ -f "$_connect_sh" ]; then
    sh "$_connect_sh" "$@"
  else
    echo "connect.sh not found at: $_connect_sh"
    echo "Clone tools repo: git clone https://github.com/diegonmarcos/tools.git ~/git/tools"
    exit 1
  fi
}

# ═══════════════════════════════════════════════════════════════════
# D) OTHERS — ssh, git-clone, install, commands, info
# ═══════════════════════════════════════════════════════════════════

# ── D1) SSH ──────────────────────────────────────────────────────
do_ssh() {
  show_menu_header
  pick "SSH Mode:" serial ssh rescue reset kill-watchdog
  [ "$PICK" = "back" ] && return 0
  _mode="$PICK"
  pick "VM:" gcp-proxy gcp-t4
  [ "$PICK" = "back" ] && return 0
  _vm="$PICK"
  resolve_vm "$_vm"

  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud not found — install first (dtk.sh install)"
    exit 1
  fi

  case "$_mode" in
    serial)        gcloud compute connect-to-serial-port "$INSTANCE" --zone="$ZONE" --project="$PROJECT" ;;
    ssh)           gcloud compute ssh root@"$INSTANCE" --zone="$ZONE" --project="$PROJECT" ;;
    rescue)        gcloud compute ssh "$INSTANCE" --zone="$ZONE" --project="$PROJECT" --command='sudo iptables -F INPUT; sudo iptables -P INPUT ACCEPT; sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null; echo done' ;;
    reset)         gcloud compute instances reset "$INSTANCE" --zone="$ZONE" --project="$PROJECT" ;;
    kill-watchdog) gcloud compute ssh "$INSTANCE" --zone="$ZONE" --project="$PROJECT" --command='sudo systemctl stop watchdog-petter.timer watchdog-petter.service 2>/dev/null; sudo systemctl disable watchdog-petter.timer 2>/dev/null; echo done' ;;
  esac
}

# ── D2) GIT CLONE ────────────────────────────────────────────────
do_git_clone() {
  _target="${1:-$HOME/git}"
  mkdir -p "$_target"
  echo "=== Cloning all repos to $_target ==="
  echo "$REPOS" | while read -r _line; do
    _name="${_line%%:*}"
    _url="${_line#*:}"
    if [ -d "$_target/$_name" ]; then
      echo "  $_name — exists, pulling..."
      git -C "$_target/$_name" pull --ff-only 2>&1 | head -1
    else
      echo "  $_name — cloning..."
      git clone "$_url" "$_target/$_name" 2>&1 | tail -1
    fi
  done
  echo "=== Done ==="
}

# ── D3) INSTALL ──────────────────────────────────────────────────
install_dev_fedora() {
  echo "=== Fedora/RHEL: Full Dev Toolchain ==="
  dnf install -y --skip-unavailable \
    fish git curl wget htop btop vim nano neovim \
    gcc gcc-c++ make cmake rust cargo golang \
    python3 python3-pip python3-virtualenv \
    nodejs npm \
    docker docker-compose \
    jq ripgrep fd-find bat tree fzf zoxide duf ncdu \
    rsync openssh-server wireguard-tools \
    tmux screen strace lsof bind-utils net-tools iproute nmap ncat \
    zip unzip p7zip tar gzip \
    man-db less which file \
    gnupg2 openssl \
    sqlite sqlite-devel postgresql-devel \
    gh rclone
  echo "Installing extras (eza, starship, terraform)..."
  command -v eza >/dev/null 2>&1 || cargo install eza 2>/dev/null || true
  command -v starship >/dev/null 2>&1 || curl -sS https://starship.rs/install.sh | sh -s -- -y 2>/dev/null || true
  if ! command -v terraform >/dev/null 2>&1; then
    dnf config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo 2>/dev/null || true
    dnf install -y terraform 2>/dev/null || true
  fi
  command -v sops >/dev/null 2>&1 || { curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/latest/download/sops-v3.9.4.linux.amd64 && chmod +x /usr/local/bin/sops; } 2>/dev/null || true
  command -v age >/dev/null 2>&1 || dnf install -y age 2>/dev/null || true
  install_cloud_clis
  install_extras
}

install_dev_arch() {
  echo "=== Arch Linux: Full Dev Toolchain ==="
  /usr/bin/pacman -Syu --noconfirm
  /usr/bin/pacman -S --noconfirm --needed \
    fish git curl wget htop btop vim nano neovim \
    base-devel gcc make cmake rust cargo go \
    python python-pip python-virtualenv \
    nodejs npm yarn typescript \
    docker docker-compose docker-buildx \
    jq yq ripgrep fd bat eza tree fzf zoxide duf ncdu \
    rsync openssh wireguard-tools \
    tmux screen strace lsof bind-tools net-tools iproute2 nmap ncat \
    zip unzip p7zip tar gzip \
    man-db less which file \
    sops age gnupg openssl \
    sqlite postgresql-libs \
    starship github-cli terraform \
    rclone unison
  install_cloud_clis
  install_extras
}

install_dev_debian() {
  echo "=== Debian/Ubuntu: Full Dev Toolchain ==="
  apt-get update -qq
  apt-get install -y -qq \
    fish git curl wget htop vim nano neovim \
    build-essential gcc make cmake rustc cargo golang \
    python3 python3-pip python3-venv \
    nodejs npm \
    docker.io docker-compose docker-buildx-plugin \
    jq ripgrep fd-find bat eza tree fzf duf ncdu \
    rsync openssh-server wireguard-tools \
    tmux screen strace lsof dnsutils net-tools iproute2 nmap ncat \
    zip unzip p7zip-full tar gzip \
    man-db less file \
    sops age gnupg openssl \
    sqlite3 libpq-dev \
    gh terraform \
    rclone
  install_cloud_clis
  install_extras
}

install_dev_nix() {
  echo "=== Nix: Full Dev Toolchain ==="
  if ! command -v nix >/dev/null 2>&1; then
    echo "Installing Nix..."
    curl -L https://nixos.org/nix/install | sh -s -- --daemon --yes
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
  fi
  nix-env -iA \
    nixpkgs.fish nixpkgs.git nixpkgs.curl nixpkgs.wget nixpkgs.htop nixpkgs.btop \
    nixpkgs.neovim nixpkgs.gcc nixpkgs.gnumake nixpkgs.cmake \
    nixpkgs.rustc nixpkgs.cargo nixpkgs.go \
    nixpkgs.python3 nixpkgs.nodejs_22 nixpkgs.yarn nixpkgs.typescript \
    nixpkgs.docker-compose \
    nixpkgs.jq nixpkgs.yq-go nixpkgs.ripgrep nixpkgs.fd nixpkgs.bat nixpkgs.eza \
    nixpkgs.tree nixpkgs.fzf nixpkgs.zoxide nixpkgs.duf nixpkgs.ncdu \
    nixpkgs.rsync nixpkgs.wireguard-tools nixpkgs.openssh \
    nixpkgs.tmux nixpkgs.strace nixpkgs.nmap \
    nixpkgs.unzip nixpkgs.p7zip \
    nixpkgs.sops nixpkgs.age nixpkgs.gnupg nixpkgs.openssl \
    nixpkgs.sqlite nixpkgs.starship nixpkgs.gh nixpkgs.terraform \
    nixpkgs.google-cloud-sdk nixpkgs.oci-cli nixpkgs.awscli2 \
    nixpkgs.flarectl nixpkgs.cloudflared nixpkgs.rclone
  install_extras
}

install_cloud_clis() {
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "Installing Google Cloud SDK..."
    curl -sL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/opt 2>/dev/null || true
    ln -sf /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud 2>/dev/null || true
  fi
  command -v oci >/dev/null 2>&1 || pip3 install oci-cli 2>/dev/null || pip install oci-cli 2>/dev/null || true
  command -v aws >/dev/null 2>&1 || pip3 install awscli 2>/dev/null || true
}

install_extras() {
  echo ""
  echo "=== Extras: Claude Code, Wrangler, Fish config ==="
  npm install -g @anthropic-ai/claude-code 2>/dev/null || true
  npm install -g wrangler 2>/dev/null || true

  if command -v fish >/dev/null 2>&1; then
    FISH_PATH="$(command -v fish)"
    grep -qxF "$FISH_PATH" /etc/shells 2>/dev/null || echo "$FISH_PATH" >> /etc/shells 2>/dev/null || true
    chsh -s "$FISH_PATH" "$(logname 2>/dev/null || whoami)" 2>/dev/null || true
    chsh -s "$FISH_PATH" root 2>/dev/null || true
  fi

  setup_fish_config
  setup_starship
  echo ""
  echo "=== Install complete ==="
}

setup_starship() {
  command -v starship >/dev/null 2>&1 || return 0
  mkdir -p "${HOME}/.config"
  [ -f "${HOME}/.config/starship.toml" ] && return 0
  cat > "${HOME}/.config/starship.toml" << 'STAR'
format = "$username$hostname$directory$git_branch$git_status$cmd_duration$line_break$character"
[character]
success_symbol = "[>](green)"
error_symbol = "[>](red)"
[directory]
truncation_length = 3
[git_branch]
format = "[$branch]($style) "
[cmd_duration]
min_time = 2000
STAR
}

setup_fish_config() {
  FISH_DIR="${HOME}/.config/fish"
  mkdir -p "$FISH_DIR"
  cat > "$FISH_DIR/config.fish" << 'FISHCONF'
if status is-interactive
    alias ls="eza --color=auto --icons 2>/dev/null || command ls --color=auto"
    alias ll="eza -alF --icons 2>/dev/null || command ls -alF"
    alias la="eza -A --icons 2>/dev/null || command ls -A"
    alias lt="eza --tree --level=2 --icons 2>/dev/null || tree -L 2"
    alias cat="bat --paging=never 2>/dev/null || command cat"
    alias grep="rg 2>/dev/null || command grep --color=auto"
    alias find="fd 2>/dev/null || command find"
    alias df="duf 2>/dev/null || command df -h"
    alias du="ncdu 2>/dev/null || command du -sh"
    alias ..="cd .."; alias ...="cd ../.."; alias ....="cd ../../.."
    alias rm="rm -i"; alias cp="cp -i"; alias mv="mv -i"
    abbr -a gs "git status -sb"
    abbr -a ga "git add"; abbr -a gaa "git add --all"
    abbr -a gc "git commit"; abbr -a gcm "git commit -m"
    abbr -a gp "git push"; abbr -a gpl "git pull"
    abbr -a gl "git log --oneline --graph --decorate -20"
    abbr -a gd "git diff"; abbr -a gco "git checkout"
    abbr -a dps "docker ps"; abbr -a dpsa "docker ps -a"
    abbr -a dcu "docker compose up"; abbr -a dcd "docker compose down"
    abbr -a dcl "docker compose logs -f"
    alias c="clear"; alias h="history"
    alias ports="ss -tulanp"; alias myip="curl -s ifconfig.me"
    alias py="python3"; alias cc="claude"
    alias reload="source ~/.config/fish/config.fish"
    fish_add_path -m ~/.cargo/bin ~/.npm-global/bin ~/go/bin ~/.local/bin ~/.nix-profile/bin
    if command -q starship; starship init fish | source; end
    if command -q zoxide; zoxide init fish | source; end
end
FISHCONF
  echo "Fish config written to $FISH_DIR/config.fish"
}

detect_distro() {
  case "$SYS_PKG" in
    dnf)    echo "fedora" ;;
    pacman) echo "arch" ;;
    apt)    echo "debian" ;;
    nix)    echo "nix" ;;
    brew)   echo "macos" ;;
    *)      echo "" ;;
  esac
}

do_install() {
  _detected=$(detect_distro)
  if [ -n "$_detected" ]; then
    echo "Detected: $_detected"
    printf "Use $_detected? [Y/n] "
    read -r _yn
    case "${_yn:-y}" in
      [Yy]*|"") PICK="$_detected" ;;
      *)
        pick "Distro:" fedora arch debian nix
        [ "$PICK" = "back" ] && return 0 ;;
    esac
  else
    pick "Distro:" fedora arch debian nix
    [ "$PICK" = "back" ] && return 0
  fi
  case "$PICK" in
    fedora) install_dev_fedora ;;
    arch)   install_dev_arch ;;
    debian) install_dev_debian ;;
    nix)    install_dev_nix ;;
  esac
}

# ── D4) COMMANDS ─────────────────────────────────────────────────
do_commands() {
  _idx="${1:-}"
  if [ -z "$_idx" ]; then
    echo "Commands (runs locally on this machine):"
    echo "   1) flush-iptables"
    echo "   2) restart-sshd"
    echo "   3) restart-wg"
    echo "   4) restart-docker"
    echo "   5) stop-docker"
    echo "   6) start-docker"
    echo "   7) docker-ps"
    echo "   8) wg-status"
    echo "   9) iptables-show"
    echo "  10) free-mem"
    echo "  11) disk-usage"
    echo "  12) kill-watchdog"
    echo "  13) journal-silence"
    echo "  14) fix-journal"
    echo "  15) full-rescue"
    printf "> "
    read -r _idx
  fi
  case "$_idx" in
    1)  iptables -F INPUT; iptables -P INPUT ACCEPT; echo "iptables flushed" ;;
    2)  systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; echo "sshd restarted" ;;
    3)  systemctl restart wg-quick@wg0; echo "wg restarted" ;;
    4)  systemctl restart docker; echo "docker restarted" ;;
    5)  systemctl stop docker; echo "docker stopped" ;;
    6)  systemctl start docker; echo "docker started" ;;
    7)  docker ps --format '{{.Names}}: {{.Status}}' | sort ;;
    8)  wg show wg0 ;;
    9)  iptables -L INPUT -n --line-numbers ;;
    10) free -m ;;
    11) df -h / /var /opt 2>/dev/null ;;
    12) systemctl stop watchdog-petter.timer watchdog-petter.service 2>/dev/null
        systemctl disable watchdog-petter.timer 2>/dev/null; echo "watchdog killed" ;;
    13) echo 0 > /proc/sys/kernel/printk; dmesg -n 1; echo "journal silenced" ;;
    14) echo 0 > /proc/sys/kernel/printk 2>/dev/null || true
        dmesg -n 1 2>/dev/null || true
        systemctl stop systemd-journald-audit.socket 2>/dev/null || true
        mkdir -p /etc/sysctl.d
        echo 'kernel.printk = 0 0 0 0' > /etc/sysctl.d/99-silence-console.conf 2>/dev/null || true
        echo "journal spam silenced" ;;
    15) iptables -F INPUT; iptables -P INPUT ACCEPT
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        systemctl restart wg-quick@wg0 2>/dev/null; echo "full rescue done" ;;
    *)  echo "Invalid" ;;
  esac
}

# ── D5) INFO ─────────────────────────────────────────────────────
do_info() { set +x 2>/dev/null
  show_banner
  echo "=== Installed Tools ==="
  for t in fish git node npm python3 rust cargo go docker podman gcloud oci aws \
           terraform claude wrangler gh jq yq rg fd bat eza fzf zoxide tmux ttyd \
           starship sops age nix rsync curl wget; do
    if command -v "$t" >/dev/null 2>&1; then
      _ver=$("$t" --version 2>/dev/null | head -1 || echo "ok")
      printf "  + %-12s %s\n" "$t" "$_ver"
    else
      printf "  - %-12s not installed\n" "$t"
    fi
  done
  echo ""
  echo "=== Repos ==="
  echo "$REPOS" | while read -r _line; do echo "  ${_line%%:*}"; done
}

# ── D6) ENGINES ──────────────────────────────────────────────────
do_engines() { set +x 2>/dev/null
  _git="${HOME:-/home/diego}/git"
  _idx="${1:-}"
  if [ -z "$_idx" ]; then
    echo "Build Engines:"
    echo "  1) nixos-host       ~/git/unix/aa_nixos-surface_host/build.sh"
    echo "  2) home-desktop     ~/git/unix/ba_flakes_desktop/build.sh"
    echo "  3) home-termux      ~/git/unix/bb_flakes_termux/build.sh"
    echo "  4) cloud-service    ~/git/cloud/a_solutions/<service>/build.sh"
    echo "  5) front-end        ~/git/front/1.ops/build_main.sh"
    printf "> "
    read -r _idx
  fi
  case "$_idx" in
    1) sh "$_git/unix/aa_nixos-surface_host/build.sh" ;;
    2) sh "$_git/unix/ba_flakes_desktop/build.sh" ;;
    3) sh "$_git/unix/bb_flakes_termux/build.sh" ;;
    4)
      # List cloud services with build.sh
      echo "Cloud services:"
      _i=1; _services=""
      for _bs in "$_git"/cloud/a_solutions/*/build.sh; do
        [ -f "$_bs" ] || continue
        _svc=$(basename "$(dirname "$_bs")")
        printf "  %d) %s\n" "$_i" "$_svc"
        _services="${_services}${_svc}
"
        _i=$((_i + 1))
      done
      printf "> "
      read -r _sidx
      _c=0
      echo "$_services" | while read -r _s; do
        [ -z "$_s" ] && continue
        _c=$((_c + 1))
        if [ "$_c" -eq "$_sidx" ]; then
          sh "$_git/cloud/a_solutions/$_s/build.sh"
          break
        fi
      done
      ;;
    5) sh "$_git/front/1.ops/build_main.sh" ;;
    *) echo "Invalid" ;;
  esac
}

# ── D) Others submenu ────────────────────────────────────────────
do_others() {
  _sub="${1:-}"
  if [ -z "$_sub" ]; then
    while true; do
      show_menu_header
      pick "Others:" ssh git-clone install commands info engines
      [ "$PICK" = "back" ] && return 0
      _sub="$PICK"
      break
    done
  fi
  case "$_sub" in
    ssh)        do_ssh ;;
    git-clone)  do_git_clone "${2:-$HOME/git}" ;;
    install)    do_install ;;
    commands)   do_commands "${2:-}" ;;
    info)       do_info ;;
    engines)    do_engines "${2:-}" ;;
  esac
}

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
  printf "  ${W}b) containers${R}   Pull & run dev environment container (cli/gui/tty)\n"
  printf "  ${W}c) connect${R}      Cloud Connect dashboard (git/mounts/sync/servers)\n"
  printf "  ${W}d) others${R}       SSH, git-clone, install, commands, info\n"
  printf "  ${W}e) help${R}         This help\n\n"
  printf "${Y}Direct Commands:${R}\n"
  printf "  dtk.sh aliases [category]      ${D}# modern-cli|navigation|git|docker|...${R}\n"
  printf "  dtk.sh containers [img] [prof] ${D}# deb-nix cli | deb-apt gui${R}\n"
  printf "  dtk.sh connect                 ${D}# launch connect.sh${R}\n"
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
_ALIAS_MAP="1:modern-cli 2:navigation 3:safety 4:python 5:system 6:git 7:docker 8:session 9:web-terminal a:misc b:functions"

_resolve_shortcode() {
  _code="$1"
  _major=$(echo "$_code" | cut -c1)
  _minor=$(echo "$_code" | cut -c2-)
  case "$_major" in
    1) # aliases
      for _pair in $_ALIAS_MAP; do
        _k="${_pair%%:*}"; _v="${_pair#*:}"
        [ "$_k" = "$_minor" ] && { do_aliases "$_v"; return 0; }
      done ;;
    2) # containers
      case "$_minor" in
        1) do_docker_run deb-nix ;; 2) do_docker_run deb-apt ;;
        3) do_docker_run deb-nix cli ;; 4) do_docker_run deb-nix gui ;; 5) do_docker_run deb-nix tty ;;
        *) echo "Invalid shortcode: $_code" ;;
      esac; return 0 ;;
    3) # connect
      do_connect; return 0 ;;
    4) # others
      case "$_minor" in
        1) do_ssh ;; 2) do_git_clone ;; 3) do_install ;;
        4) do_commands ;; 5) do_info ;; 6) do_engines ;;
        *) echo "Invalid shortcode: $_code" ;;
      esac; return 0 ;;
  esac
  return 1
}

set +x 2>/dev/null
if [ $# -ge 1 ]; then
  case "$1" in
    # Shortcodes: 11-1b, 21-25, 31-34, 41-46
    [1-4][0-9a-b]) _resolve_shortcode "$1" ;;
    aliases)        do_aliases "${2:-}" ;;
    containers)     shift; do_docker_run "$@" ;;
    docker-run)     shift; do_docker_run "$@" ;;
    docker-start)   do_docker_run cli ;;
    connect)        shift; do_connect "$@" ;;
    others)         shift; do_others "$@" ;;
    ssh)            do_ssh ;;
    git-clone)      do_git_clone "${2:-$HOME/git}" ;;
    install)        do_install ;;
    commands)       do_commands "${2:-}" ;;
    info)           do_info ;;
    engines)        do_engines "${2:-}" ;;
    fix-journal)    do_commands 14 ;;
    full-rescue)    do_commands 15 ;;
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
      1)  do_aliases ;;
      2)  do_docker_run ;;
      3)  do_connect ;;
      4)  do_others ;;
      5)  do_help ;;
      q)  echo "Bye."; exit 0 ;;
      # Shortcodes: 11-1b, 21-25, 31-34, 41-46
      [1-4][0-9a-b]) _resolve_shortcode "$_input" ;;
      *)  echo "Invalid — enter 1-5, shortcode (e.g. 16), or q to quit" ;;
    esac
  done
fi
