#!/bin/sh
# gcl.sh - Unified launcher for gcl
# Usage:
#   ./gcl.sh [command]              # Run natively (default)
#   ./gcl.sh --venv [command]       # Use venv mode
#   ./gcl.sh --py_docker [command]  # Use Docker mode
#   ./gcl.sh --sh [command]         # Use shell POSIX script
#   ./gcl.sh --help                 # Show help

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_PURPLE="\033[38;5;141m"
C_GRAY="\033[90m"

# Show help
show_help() {
    printf "\n"
    printf "${C_BOLD}${C_CYAN}╔════════════════════════════════════════════════════════════╗${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}║                                                            ║${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}║     gcl.sh - Git Clone/Pull/Push Manager Launcher          ║${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}║                                                            ║${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}╚════════════════════════════════════════════════════════════╝${C_RESET}\n\n"

    printf "${C_BOLD}SYNTAX${C_RESET}\n"
    printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "  sh gcl.sh [${C_YELLOW}--MODE${C_RESET}] [${C_PURPLE}ACTIONS${C_RESET}]\n\n"

    printf "${C_BOLD}MODES${C_RESET}\n"
    printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "  ${C_GREEN}(no mode)${C_RESET}\t\t\t${C_GRAY}Run directly with Python (default)${C_RESET}\n"
    printf "  ${C_YELLOW}--venv${C_RESET}\t\t\t${C_GRAY}Run in Python virtual environment (auto-setups if needed)${C_RESET}\n"
    printf "  ${C_YELLOW}--py_docker${C_RESET}\t\t\t${C_GRAY}Run in Docker container (auto-builds if needed)${C_RESET}\n"
    printf "  ${C_YELLOW}--sh${C_RESET}\t\t\t\t${C_GRAY}Run the shell POSIX script${C_RESET}\n\n"

    printf "${C_BOLD}ACTIONS${C_RESET}\n"
    printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "  ${C_PURPLE}(no command)${C_RESET}\t\t\t${C_GRAY}Launch interactive TUI${C_RESET}\n\n"
    printf "  ${C_PURPLE}sync${C_RESET}\t\t\t\t${C_GRAY}Sync (Commit Local, Fetch, Pull w/ Strategy, Commit Merge, Push)${C_RESET}\n"
    printf "  ${C_PURPLE}fetch${C_RESET}\t\t\t\t${C_GRAY}Fetch from remote${C_RESET}\n"
    printf "  ${C_PURPLE}push${C_RESET}\t\t\t\t${C_GRAY}Push changes with Merge Strategy Default${C_RESET}\n"
    printf "  ${C_PURPLE}pull${C_RESET}\t\t\t\t${C_GRAY}Pull changes with Merge Strategy Default${C_RESET}\n\n"
    printf "  ${C_PURPLE}status${C_RESET}\t\t\t${C_GRAY}Check repository status${C_RESET}\n"
    printf "  ${C_PURPLE}untracked${C_RESET}\t\t\t${C_GRAY}List untracked files${C_RESET}\n"
    printf "  ${C_PURPLE}ignored${C_RESET}\t\t\t${C_GRAY}List ignored files${C_RESET}\n\n\n"

    printf "${C_BOLD}EXAMPLES${C_RESET}\n"
    printf "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "  ./gcl.sh\t\t\t${C_GRAY}# Run TUI natively${C_RESET}\n"
    printf "  ./gcl.sh --venv\t\t${C_GRAY}# Run TUI natively (venv)${C_RESET}\n"
    printf "  ./gcl.sh --py_docker\t\t${C_GRAY}# Run TUI in Docker${C_RESET}\n"
    printf "  ./gcl.sh --sh\t\t\t${C_GRAY}# Run TUI in sh Posix${C_RESET}\n\n"
    printf "  ./gcl.sh status\t\t${C_GRAY}# Check status (native)${C_RESET}\n"
    printf "  ./gcl.sh --venv status\t${C_GRAY}# Check status (venv)${C_RESET}\n\n\n"

    printf "${C_BOLD}OPTIONS${C_RESET}\n"
    printf "${C_GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "  ${C_GREEN}--help, -h${C_RESET}\t\t\t${C_GRAY}Show this help message${C_RESET}\n"
    printf "  ${C_GREEN}--install${C_RESET}\t\t\t${C_GRAY}This will fetch the bin files from the remoto repo${C_RESET}\n"
    printf "  ${C_GREEN}--install_dev${C_RESET}\t\t\t${C_GRAY}Fetch the repo tools and symlink it${C_RESET}\n\n"

    printf "${C_BOLD}SETUP${C_RESET}\n"
    printf "${C_GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
    printf "  --venv\t\t\t${C_GRAY}Mode will setup the virtual environment on first run${C_RESET}\n"
    printf "  --py_docker\t\t\t${C_GRAY}Mode will automatically build the image on first run${C_RESET}\n"
    printf "  (no mode)\t\t\t${C_GRAY}Requires Python 3 to be installed on your system${C_RESET}\n"
    printf "  MERGE\t\t\t\t${C_GRAY}Merge Strategy Default is: remote (theirs)${C_RESET}\n"
    printf "  UI\t\t\t\t${C_GRAY}Designed for Half-Full-screen (80x24 terminal, 640x400 px)${C_RESET}\n\n"
}

# Run natively
run_native() {
    # Check if command is valid (if provided)
    if [ $# -gt 0 ]; then
        case "${1}" in
            sync|fetch|push|pull|status|untracked|ignored|help)
                # Valid command, proceed
                ;;
            *)
                # Unknown command, show help
                printf "\n${C_BOLD}${C_YELLOW}Unknown command: ${1}${C_RESET}\n\n"
                show_help
                exit 1
                ;;
        esac
    fi

    # Check terminal size for TUI mode
    if [ $# -eq 0 ]; then
        # Only check terminal for TUI mode (no args)
        if ! command -v tput > /dev/null 2>&1; then
            printf "Warning: tput not found, terminal check skipped\n" >&2
        else
            TERM_ROWS=$(tput lines 2>/dev/null || echo 0)
            TERM_COLS=$(tput cols 2>/dev/null || echo 0)
            if [ "$TERM_ROWS" -lt 24 ] || [ "$TERM_COLS" -lt 80 ]; then
                printf "Error: Terminal too small for TUI (need 24x80, got ${TERM_ROWS}x${TERM_COLS})\n" >&2
                printf "Try: ./gcl.sh status  (to run CLI mode instead)\n" >&2
                exit 1
            fi
        fi

        # Set TERM if not set
        if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
            export TERM=xterm-256color
        fi
    fi

    python3 "$SCRIPT_DIR/gcl/gcl.py" "$@"
}

# Run via Docker
run_docker() {
    cd "$SCRIPT_DIR/gcl/gcl_py-docker"
    if docker compose version > /dev/null 2>&1; then
        docker compose run --rm gcl "$@"
    else
        docker-compose run --rm gcl "$@"
    fi
}

# Run via venv
run_venv() {
    VENV_DIR="$SCRIPT_DIR/gcl/gcl_py-venv/venv"
    VENV_SCRIPT="$SCRIPT_DIR/gcl/gcl_py-venv/gcl-venv.sh"

    # Check if venv exists, if not, run setup
    if [ ! -d "$VENV_DIR" ]; then
        printf "${C_CYAN}==>${C_RESET} ${C_BOLD}Virtual environment not found. Setting up...${C_RESET}\n"
        "$VENV_SCRIPT" setup
        printf "\n"
    fi

    # Now run with venv
    "$VENV_SCRIPT" run "$@"
}

# Run via shell script
run_sh() {
    "$SCRIPT_DIR/gcl/gcl.sh" "$@"
}

# Run via shell script
run_sh() {
    "$SCRIPT_DIR/gcl/gcl.sh" "$@"
}

# Run installer
run_install() {
    printf "${C_CYAN}==>${C_RESET} ${C_BOLD}Starting gcl installation...${C_RESET}\n"

    REPO_URL="git@github.com:diegonmarcos/ops-Tooling.git"
    INSTALL_DIR="gcl_install_temp"

    # Clone the repo
    printf "Cloning repository from ${REPO_URL}...\n"
    if ! git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
        printf "Error: Failed to clone repository. Make sure you have SSH access and the repository exists.\n" >&2
        exit 1
    fi

    # Check if the gcl folder exists in the cloned repo
    if [ ! -d "$INSTALL_DIR/Git/gcl" ]; then
        printf "Error: 'Git/gcl' directory not found in the cloned repository. Expected structure: ops-Tooling/Git/gcl\n" >&2
        rm -rf "$INSTALL_DIR"
        exit 1
    fi

    # Move the gcl folder
    printf "Installing gcl...\n"
    rm -rf ./gcl
    mv "$INSTALL_DIR/Git/gcl" ./gcl

    # Cleanup
    printf "Cleaning up...\n"
    rm -rf "$INSTALL_DIR"

    printf "${C_GREEN}==>${C_RESET} ${C_BOLD}gcl installed successfully.${C_RESET}\n"
}


# Run developer installer
run_install_dev() {
    printf "${C_CYAN}==>${C_RESET} ${C_BOLD}Setting up developer environment (symlink mode)...${C_RESET}\n"

    REPO_URL="git@github.com:diegonmarcos/ops-Tooling.git"
    CLONE_DIR_NAME="ops-Tooling-dev"
    # Place it in the parent of SCRIPT_DIR
    CLONE_DIR_PATH="$(dirname "$SCRIPT_DIR")/$CLONE_DIR_NAME"

    if [ -d "$CLONE_DIR_PATH" ]; then
        printf "Dev repository already exists. Pulling latest changes from ${REPO_URL}...\n"
        if ! git -C "$CLONE_DIR_PATH" pull; then
            printf "Error: Failed to pull latest changes. Please check for conflicts in ${CLONE_DIR_PATH}\n" >&2
            exit 1
        fi
    else
        printf "Cloning dev repository from ${REPO_URL} into ${CLONE_DIR_PATH}...\n"
        if ! git clone "$REPO_URL" "$CLONE_DIR_PATH"; then
            printf "Error: Failed to clone repository. Make sure you have SSH access and the repository exists.\n" >&2
            exit 1
        fi
    fi

    # The gcl.sh to link to, inside the cloned repo
    TARGET_GCL_SH="$CLONE_DIR_PATH/Git/gcl.sh"
    # The symlink we want to create
    SYMLINK_PATH="$SCRIPT_DIR/gcl.sh"

    # Check if the target file exists
    if [ ! -f "$TARGET_GCL_SH" ]; then
        printf "Error: Target file not found in cloned repository: ${TARGET_GCL_SH}\n" >&2
        exit 1
    fi

    printf "Creating symlink to development version of gcl.sh...\n"

    # Remove the original file only if it is not a symlink.
    if [ -f "$SYMLINK_PATH" ] && [ ! -L "$SYMLINK_PATH" ]; then
        printf "Removing original gcl.sh file...\n"
        rm "$SYMLINK_PATH"
    elif [ -L "$SYMLINK_PATH" ]; then
        # If it's already a symlink, remove it to update it.
        rm "$SYMLINK_PATH"
    fi

    # Create a relative symlink from the current script dir
    printf "Symlinking ./gcl.sh -> ../${CLONE_DIR_NAME}/Git/gcl.sh\n"
    cd "$SCRIPT_DIR"
    ln -s "../${CLONE_DIR_NAME}/Git/gcl.sh" "gcl.sh"

    printf "${C_GREEN}==>${C_RESET} ${C_BOLD}Developer environment setup complete.${C_RESET}\n"
    printf "'gcl.sh' is now a symlink. Run it to use the development version.\n"
}

# Main
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --install)
        run_install
        exit 0
        ;;
    --install_dev)
        run_install_dev
        exit 0
        ;;
    --py_docker|--docker)
        shift
        run_docker "$@"
        ;;
    --venv)
        shift
        run_venv "$@"
        ;;
    --sh)
        shift
        run_sh "$@"
        ;;
    --native)
        shift
        run_native "$@"
        ;;
    *)
        # Default to native with all args
        run_native "$@"
        ;;
esac
