#!/bin/sh
# 23a — Install Fish + ALL CLI tools from desktop flake + fetch configs
# Requires: sudo access, package manager (apt/dnf/pacman/apk)
set -eu

SUDO="sudo"
[ "$(id -u)" = "0" ] && SUDO=""
FISH_DIR="${HOME}/.config/fish"
STARSHIP_DIR="${HOME}/.config"
RAW="https://raw.githubusercontent.com/diegonmarcos/unix/main/ba_flakes_desktop/src/modules/programs/shells/fish"

echo "=== Fish Shell + Tools Setup (23a) ==="

# ═══════════════════════════════════════════════════════════════════
# PACKAGE MANAGER DETECTION
# ═══════════════════════════════════════════════════════════════════

_PM=""
_PM_INSTALL=""
_PM_UPDATE=""
if command -v apt-get >/dev/null 2>&1; then
    _PM="apt"; _PM_INSTALL="$SUDO apt-get install -y -qq"; _PM_UPDATE="$SUDO apt-get update -qq"
elif command -v dnf >/dev/null 2>&1; then
    _PM="dnf"; _PM_INSTALL="$SUDO dnf install -y"; _PM_UPDATE="true"
elif command -v pacman >/dev/null 2>&1; then
    _PM="pacman"; _PM_INSTALL="$SUDO pacman -S --noconfirm"; _PM_UPDATE="$SUDO pacman -Sy"
elif command -v apk >/dev/null 2>&1; then
    _PM="apk"; _PM_INSTALL="$SUDO apk add"; _PM_UPDATE="$SUDO apk update"
else
    echo "[!] No supported package manager found"; exit 1
fi
echo "[OK] Package manager: $_PM"

# ═══════════════════════════════════════════════════════════════════
# DEPENDENCY SOLVER — install tool, skip gracefully if unavailable
# ═══════════════════════════════════════════════════════════════════

_ok=0; _skip=0; _fail=0

_install() {
    _cmd="$1"; _pkg="${2:-$1}"
    if command -v "$_cmd" >/dev/null 2>&1; then
        _ok=$((_ok + 1))
        return 0
    fi
    if $_PM_INSTALL "$_pkg" >/dev/null 2>&1; then
        echo "[+] $_cmd"; _ok=$((_ok + 1))
    else
        echo "[!] $_cmd ($_pkg not in $_PM repos)"; _skip=$((_skip + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════════
# STEP 1: Install Fish
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "── Step 1: Fish Shell ──"
_install fish fish

# ═══════════════════════════════════════════════════════════════════
# STEP 2: Install ALL CLI tools from desktop flake profiles
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "── Step 2: CLI Tools ──"
$_PM_UPDATE >/dev/null 2>&1 || true

# Profile 1: Shell & Core
echo "[*] Shell & Core utilities..."
_install eza eza
_install bat bat
_install fd fd-find
_install rg ripgrep
_install fzf fzf
_install zoxide zoxide
_install yazi yazi
_install btop btop
_install ncdu ncdu
_install duf duf
_install tree tree
_install jq jq
_install yq yq
_install rsync rsync
_install rclone rclone
_install curl curl
_install wget wget
_install htop htop
_install less less
_install bc bc
_install unzip unzip
_install zip zip
_install 7z p7zip-full
_install neofetch neofetch
_install lshw lshw
_install lspci pciutils
_install lsusb usbutils
_install socat socat
_install ttyd ttyd
_install gh gh
_install tmux tmux
_install xclip xclip

# Profile 2: Dev Languages
echo "[*] Development languages..."
_install go golang
_install node nodejs
_install npm npm
_install python3 python3
_install pip3 python3-pip
_install pipx pipx
_install gcc gcc
_install g++ g++
_install ruby ruby
_install java default-jdk

# Profile 3: Build & Debug
echo "[*] Build & debug tools..."
_install cmake cmake
_install ninja ninja-build
_install make make
_install gdb gdb
_install strace strace
_install shellcheck shellcheck
_install shfmt shfmt
_install pandoc pandoc
_install git-lfs git-lfs
_install delta git-delta
_install direnv direnv
_install just just
_install watchexec watchexec

# Profile 4: Containers & Cloud
echo "[*] Containers & cloud..."
_install docker docker.io
_install kubectl kubectl
_install helm helm
_install terraform terraform
_install sops sops
_install age age

# Profile 5: Security & Networking
echo "[*] Security & networking..."
_install nmap nmap
_install mtr mtr
_install tcpdump tcpdump
_install iftop iftop
_install gnupg gpg
_install openssl openssl
_install httpie httpie
_install wg wireguard-tools

# Profile 6: Data
echo "[*] Data tools..."
_install sqlite3 sqlite3
_install pgcli pgcli
_install redis-cli redis-tools

# Prompt tools
echo "[*] Prompt & integrations..."
_install starship starship

echo ""
printf "[OK] %d installed  [!] %d skipped\n" "$_ok" "$_skip"

# ═══════════════════════════════════════════════════════════════════
# STEP 3: Set fish as default shell
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "── Step 3: Default shell ──"
if command -v fish >/dev/null 2>&1; then
    FISH_PATH=$(command -v fish)
    grep -q "$FISH_PATH" /etc/shells 2>/dev/null || echo "$FISH_PATH" | $SUDO tee -a /etc/shells >/dev/null 2>&1 || true
    CURRENT_SHELL=$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f7 || echo "")
    [ "$CURRENT_SHELL" != "$FISH_PATH" ] && $SUDO chsh -s "$FISH_PATH" "$(whoami)" 2>/dev/null && echo "[+] Default shell: fish" || true
else
    echo "[!] Fish not installed — cannot set as default"
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 4: Skip if HM-managed
# ═══════════════════════════════════════════════════════════════════

if [ -L "$FISH_DIR/config.fish" ] || ! mkdir -p "$FISH_DIR" 2>/dev/null || ! touch "$FISH_DIR/.test" 2>/dev/null; then
    echo "[OK] Fish config managed by home-manager — skipping config deploy"
    exit 0
fi
rm -f "$FISH_DIR/.test"

# ═══════════════════════════════════════════════════════════════════
# STEP 5: Generate config.fish with fallback aliases
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "── Step 5: Fish config ──"
mkdir -p "$FISH_DIR/functions" "$FISH_DIR/conf.d" "$FISH_DIR/completions"

cat > "$FISH_DIR/config.fish" << 'FISHCONF'
# Generated by dtk.sh 23a — non-HM config with fallback aliases
if status is-interactive
    # Modern CLI with fallbacks
    if command -q eza
        alias ls="eza --color=auto --icons"
        alias ll="eza -alF --icons"
        alias la="eza -A --icons"
        alias l="eza -CF --icons"
        alias lh="eza -lh --icons"
        alias lt="eza --tree --level=2 --icons"
    else
        alias ls="command ls --color=auto"
        alias ll="command ls -alF --color=auto"
        alias la="command ls -A --color=auto"
        alias l="command ls -CF --color=auto"
        alias lh="command ls -lh --color=auto"
        alias lt="tree -L 2 2>/dev/null; or command ls -R"
    end
    if command -q bat;    alias cat="bat --paging=never"; end
    if command -q rg;     alias grep="rg"; end
    if command -q fd;     alias find="fd"; end
    if command -q duf;    alias df="duf";  else; alias df="command df -h"; end
    if command -q ncdu;   alias du="ncdu"; else; alias du="command du -sh"; end

    # Navigation
    alias ..="cd .."; alias ...="cd ../.."; alias ....="cd ../../.."

    # Safety
    alias rm="rm -i"; alias cp="cp -i"; alias mv="mv -i"

    # Python
    alias py="python3"; alias python="python3"; alias pip="pip3"

    # System
    alias free="free -h"
    alias ports="ss -tulanp"
    alias myip="curl -s ifconfig.me"

    # Misc
    alias c="clear"; alias cls="clear"; alias h="history"
    alias path="echo \$PATH | tr ':' '\\n'"
    alias reload="source ~/.config/fish/config.fish"

    # Custom tools
    alias dtk="bash ~/git/tools/dtk.sh"

    # Git abbreviations
    abbr -a gs "git status -sb"; abbr -a ga "git add"; abbr -a gaa "git add --all"
    abbr -a gc "git commit"; abbr -a gcm "git commit -m"
    abbr -a gp "git push"; abbr -a gpl "git pull"; abbr -a gcl "git clone"
    abbr -a gl "git log --oneline --graph --decorate -20"
    abbr -a gd "git diff"; abbr -a gco "git checkout"

    # Docker abbreviations
    abbr -a dps "docker ps"; abbr -a dpsa "docker ps -a"
    abbr -a dcu "docker compose up"; abbr -a dcd "docker compose down"

    # PATH
    fish_add_path -m ~/.cargo/bin ~/.npm-global/bin ~/go/bin ~/.local/bin ~/.nix-profile/bin

    # Integrations (only if installed)
    if command -q starship; starship init fish | source; end
    if command -q zoxide;   zoxide init fish | source; end
    if command -q fzf;      fzf --fish | source; end
    if command -q direnv;   direnv hook fish | source; end
end
FISHCONF
echo "[OK] config.fish"

# ═══════════════════════════════════════════════════════════════════
# STEP 6: Fetch functions from unix repo
# ═══════════════════════════════════════════════════════════════════

echo "[+] Fetching fish functions..."
FUNCS_URL="$RAW/functions"
for fn in fish_greeting ai-cli cloud-ai-cli gacp gcam gpsh git_current_branch \
          extract mkcd mkd serve hhelp myhelp localip duh backup cpucap qfind \
          hg fish-e fish-e-stop __fzf_search_commands; do
    _body_tmp=$(mktemp)
    if curl -sfL "$FUNCS_URL/${fn}.fish" -o "$_body_tmp" 2>/dev/null && [ -s "$_body_tmp" ]; then
        { echo "function $fn"; sed 's/^/  /' "$_body_tmp"; echo "end"; } > "$FISH_DIR/functions/${fn}.fish"
        echo "[OK] functions/${fn}.fish"
    else
        echo "[!] functions/${fn}.fish not found"
    fi
    rm -f "$_body_tmp"
done

# ═══════════════════════════════════════════════════════════════════
# STEP 7: Starship config
# ═══════════════════════════════════════════════════════════════════

mkdir -p "$STARSHIP_DIR"
cat > "$STARSHIP_DIR/starship.toml" << 'STAR'
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
echo "[OK] starship.toml"

echo ""
echo "=== Done ==="
echo "  ~/.config/fish/config.fish"
echo "  ~/.config/fish/functions/ ($(ls "$FISH_DIR/functions/" 2>/dev/null | wc -l) files)"
echo "  ~/.config/starship.toml"
echo "  Tools: $_ok installed, $_skip skipped"
echo ""
echo "Run: source ~/.config/fish/config.fish"
