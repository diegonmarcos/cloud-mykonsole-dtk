#!/bin/sh
# Diego's Toolkit (DTK) — install, ssh, clone, info
# Usage: ./dtk.sh                # interactive
#        ./dtk.sh <cmd> [args]   # direct
# OS-agnostic POSIX: NixOS, Arch, Debian, Fedora, macOS, Termux
set -eu

# Logging — verbose trace to screen + log file
LOGFILE="${HOME:-/tmp}/dtk.log"
_LOG_USER=$(whoami 2>/dev/null || echo "?")
_LOG_HOST=$(hostname -s 2>/dev/null || echo "?")
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ${_LOG_USER}@${_LOG_HOST} === dtk.sh $* ===" >> "$LOGFILE"
# POSIX: write set -x trace to log file via fd 9, copy stdout/stderr to log too
exec 9>>"$LOGFILE"
# set -x trace goes to stderr → capture stderr to both screen and log
# Use a named pipe to tee stderr without bash process substitution
_DTK_FIFO="/tmp/.dtk-log-$$"
mkfifo "$_DTK_FIFO" 2>/dev/null || true
tee -a "$LOGFILE" < "$_DTK_FIFO" >&2 &
_DTK_TEE_PID=$!
exec 2>"$_DTK_FIFO"
trap 'rm -f "$_DTK_FIFO"; kill "$_DTK_TEE_PID" 2>/dev/null || true' EXIT
# set -x enabled after setup (avoids noisy PATH/detect_system trace)

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
  printf "  ${D}──────────────────────────────────────────────${R}\n"
  printf '\n'
  set -x 2>/dev/null || true
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
  _idx=$((_idx)) 2>/dev/null || { echo "Invalid"; exit 1; }
  [ "$_idx" -ge 1 ] && [ "$_idx" -le $# ] || { echo "Invalid"; exit 1; }
  # Get item by index
  _c=0
  for _item in "$@"; do
    _c=$((_c + 1))
    [ "$_c" -eq "$_idx" ] && PICK="$_item" && set -x 2>/dev/null && return 0
  done
  set -x 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════
# 0) COMMANDS — quick commands to run on this machine
# ═══════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════
# 1) DOCKER START — pull & run dev environment container
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

do_docker_start() {
  IMG="ghcr.io/diegonmarcos/diego-user-env:latest"
  HOME_DIR="${HOME:-/root}"
  DOCKER=""; RUNTIME="docker"

  # ── Step 1: Find docker binary ───────────────────────────────────────
  find_docker || true

  # ── Step 2: Install if not found ─────────────────────────────────────
  if [ -z "$DOCKER" ]; then
    echo "Docker not found — installing for $SYS_PKG..."
    case "$SYS_PKG" in
      apt)    apt-get update -qq && apt-get install -y -qq docker.io ;;
      dnf)    dnf install -y --skip-unavailable docker ;;
      pacman) pacman -Sy --noconfirm docker ;;
      nix)
        if [ "$SYS_OS" = "nixos" ]; then
          echo "On NixOS, Docker must be enabled in your system flake:"
          echo "  virtualisation.docker.enable = true;"
          echo "Then: sudo nixos-rebuild switch"
          echo ""
          echo "Trying nix-shell fallback for docker CLI..."
        fi
        exec nix-shell -p docker --run "sh $0 docker-start" ;;
      brew)   brew install --cask docker ;;
      pkg)    echo "Docker not available on Termux"; exit 1 ;;
      *)      echo "No supported package manager — install docker manually"; exit 1 ;;
    esac
    find_docker || true
    [ -z "$DOCKER" ] && { echo "ERROR: docker still not found after install"; exit 1; }
  fi

  # ── Step 3: Start daemon if not running ──────────────────────────────
  if ! "$DOCKER" info >/dev/null 2>&1; then
    echo "Docker daemon not running — starting..."
    if [ "$SYS_INIT" = "systemd" ]; then
      systemctl start docker 2>/dev/null || true
      _w=0; while [ $_w -lt 15 ]; do
        "$DOCKER" info >/dev/null 2>&1 && break
        sleep 1; _w=$((_w + 1))
      done
    elif command -v service >/dev/null 2>&1; then
      service docker start 2>/dev/null || true; sleep 3
    elif [ "$SYS_OS" = "macos" ]; then
      open -a Docker 2>/dev/null || true
      echo "Waiting for Docker Desktop..."
      _w=0; while [ $_w -lt 30 ]; do
        "$DOCKER" info >/dev/null 2>&1 && break
        sleep 1; _w=$((_w + 1))
      done
    fi
  fi

  # ── Step 4: Podman fallback ──────────────────────────────────────────
  if ! "$DOCKER" info >/dev/null 2>&1; then
    if find_podman; then
      echo "Docker daemon failed — falling back to podman ($_PODMAN)"
      DOCKER="$_PODMAN"; RUNTIME="podman"
      "$DOCKER" system migrate 2>/dev/null || true
    else
      echo "ERROR: Neither docker daemon nor podman available"
      echo "  Docker: $DOCKER (found but daemon not running)"
      echo "  OS=$SYS_OS PKG=$SYS_PKG INIT=$SYS_INIT"
      echo "  Try: systemctl status docker / journalctl -u docker"
      exit 1
    fi
  fi
  echo "Using: $RUNTIME ($DOCKER)"

  # ── Step 5: Pull and run ─────────────────────────────────────────────
  echo "=== Docker Start: $IMG ==="
  echo "Pulling latest image..."
  "$DOCKER" pull "$IMG"

  # Build mount args (only mount paths that exist)
  MOUNTS="-v $HOME_DIR:$HOME_DIR"
  [ -S /var/run/docker.sock ] && MOUNTS="$MOUNTS -v /var/run/docker.sock:/var/run/docker.sock"
  [ -d /etc/wireguard ]       && MOUNTS="$MOUNTS -v /etc/wireguard:/etc/wireguard:ro"
  [ -d /opt ]                 && MOUNTS="$MOUNTS -v /opt:/opt"

  echo "Starting container ($RUNTIME, home=$HOME_DIR, arch=$SYS_ARCH)..."
  EXTRA_FLAGS="--privileged --network host --pid host"
  [ "$RUNTIME" = "podman" ] && EXTRA_FLAGS="--privileged --network host"

  SHELL_CMD='exec fish 2>/dev/null || exec bash 2>/dev/null || exec sh'

  exec "$DOCKER" run -it --rm \
    --name diego-env \
    --hostname "${SYS_HOSTNAME}-dev" \
    $EXTRA_FLAGS \
    $MOUNTS \
    -w "$HOME_DIR" \
    -e HOME="$HOME_DIR" \
    -e USER="${USER:-root}" \
    -e TERM="${TERM:-xterm-256color}" \
    -e PATH="/home/${USER:-root}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/sbin" \
    "$IMG" \
    bash -c "$SHELL_CMD"
}

# ═══════════════════════════════════════════════════════════════════
# 2) INSTALL
# ═══════════════════════════════════════════════════════════════════

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
success_symbol = "[❯](green)"
error_symbol = "[❯](red)"
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
        pick "Distro:" fedora arch debian nix ;;
    esac
  else
    pick "Distro:" fedora arch debian nix
  fi
  case "$PICK" in
    fedora) install_dev_fedora ;;
    arch)   install_dev_arch ;;
    debian) install_dev_debian ;;
    nix)    install_dev_nix ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════
# 3) SSH
# ═══════════════════════════════════════════════════════════════════

do_ssh() {
  pick "SSH Mode:" serial ssh rescue reset kill-watchdog
  _mode="$PICK"
  pick "VM:" gcp-proxy gcp-t4
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

# ═══════════════════════════════════════════════════════════════════
# 4) GIT CLONE
# ═══════════════════════════════════════════════════════════════════

do_git_clone() {
  _target="${1:-$HOME/git}"
  mkdir -p "$_target"
  echo "=== Cloning all repos to $_target ==="
  echo "$REPOS" | while IFS=: read -r _name _url; do
    _url="${_name#*:}"; _url="https:${_url}"  # reconstruct URL after IFS split
    _name="${_name%%:*}"
    # Fix: re-read properly
    true
  done
  # Simpler approach: iterate lines
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

# ═══════════════════════════════════════════════════════════════════
# 5) INFO — show installed tools
# ═══════════════════════════════════════════════════════════════════

do_info() { set +x 2>/dev/null
  show_banner
  echo "=== Installed Tools ==="
  for t in fish git node npm python3 rust cargo go docker podman gcloud oci aws \
           terraform claude wrangler gh jq yq rg fd bat eza fzf zoxide tmux \
           starship sops age nix rsync curl wget; do
    if command -v "$t" >/dev/null 2>&1; then
      _ver=$("$t" --version 2>/dev/null | head -1 || echo "ok")
      printf "  ✓ %-12s %s\n" "$t" "$_ver"
    else
      printf "  ✗ %-12s not installed\n" "$t"
    fi
  done
  echo ""
  echo "=== Fish Aliases ==="
  echo "  ls→eza  ll→eza -alF  cat→bat  grep→rg  find→fd  df→duf  du→ncdu"
  echo "  cc→claude  py→python3  c→clear  h→history  ports→ss  myip→curl"
  echo ""
  echo "=== Repos ==="
  echo "$REPOS" | while read -r _line; do echo "  ${_line%%:*}"; done
}

# ═══════════════════════════════════════════════════════════════════
# ENTRY POINT — set -x starts here (after quiet setup)
# ═══════════════════════════════════════════════════════════════════
set -x

if [ $# -ge 1 ]; then
  case "$1" in
    commands)       do_commands "${2:-}" ;;
    fix-journal)    do_commands 14 ;;
    full-rescue)    do_commands 15 ;;
    docker-start)   do_docker_start ;;
    install)        do_install ;;
    ssh)            do_ssh ;;
    git-clone)      do_git_clone "${2:-$HOME/git}" ;;
    info)           do_info ;;
    *)              echo "Usage: $0 {commands|docker-start|install|ssh|git-clone|info}"; exit 1 ;;
  esac
else
  show_banner
  pick "What do you need?" commands docker-start install ssh git-clone info
  case "$PICK" in
    commands)       do_commands ;;
    docker-start)   do_docker_start ;;
    install)        do_install ;;
    ssh)            do_ssh ;;
    git-clone)      do_git_clone ;;
    info)           do_info ;;
  esac
fi
