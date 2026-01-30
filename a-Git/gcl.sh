#!/bin/sh
# gcl.sh - Git Clone/Pull/Push Manager
# POSIX-compliant engine with optional Python TUI
#
# Usage:
#   ./gcl.sh              # Launch TUI (Python if available, else shell)
#   ./gcl.sh --sh         # Force shell TUI
#   ./gcl.sh --py         # Force Python TUI
#   ./gcl.sh <command>    # CLI mode (sync|pull|push|status|fetch)
#   ./gcl.sh --help       # Show help

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/gcl.json"
PYTHON_TUI="$SCRIPT_DIR/gcl/gcl.py"

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
    C_BG_BLUE="\033[44m"
else
    C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_DIM='' C_BG_BLUE=''
fi

# Symbols
OK="${C_GREEN}✓${C_RESET}"
FAIL="${C_RED}✗${C_RESET}"
WARN="${C_YELLOW}!${C_RESET}"
INFO="${C_BLUE}→${C_RESET}"

# =============================================================================
# CONFIG PARSER (reads gcl.json)
# =============================================================================

# Parse JSON config file - extracts workdir and repos
# Uses grep/sed for POSIX compatibility (no jq dependency)
parse_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        printf "$FAIL ${C_RED}Config file not found: $CONFIG_FILE${C_RESET}\n"
        exit 1
    fi

    # Extract workdir (match "workdir": "/path" pattern - path starts with /)
    WORKDIR=$(grep -E '"workdir"[[:space:]]*:[[:space:]]*"/[^"]*"' "$CONFIG_FILE" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

    # Extract all repos (public + private) as "name:url" pairs
    REPOS=$(grep -E '^\s*"[^_][^"]*":\s*"git@' "$CONFIG_FILE" | \
            sed 's/.*"\([^"]*\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1:\2/')

    REPO_COUNT=$(echo "$REPOS" | grep -c ':' || echo 0)
}

# Get list of repo names
get_repo_names() {
    echo "$REPOS" | cut -d: -f1
}

# Get repo URL by name
get_repo_url() {
    echo "$REPOS" | grep "^$1:" | cut -d: -f2-
}

# =============================================================================
# GIT ENGINE (POSIX shell)
# =============================================================================

# Check repo status (local changes, unpushed commits)
repo_status() {
    repo_dir="$1"

    if [ ! -d "$repo_dir" ]; then
        printf "${C_RED}Not Cloned${C_RESET}"
        return
    fi

    if [ ! -d "$repo_dir/.git" ]; then
        printf "${C_RED}Not a Repo${C_RESET}"
        return
    fi

    # Check for uncommitted changes
    if [ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]; then
        printf "${C_YELLOW}Uncommitted${C_RESET}"
        return
    fi

    # Check if tracking remote
    if ! git -C "$repo_dir" rev-parse @{u} >/dev/null 2>&1; then
        printf "${C_YELLOW}No Upstream${C_RESET}"
        return
    fi

    # Check for unpushed commits
    unpushed=$(git -C "$repo_dir" log @{u}.. --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$unpushed" -gt 0 ]; then
        printf "${C_YELLOW}${unpushed} Unpushed${C_RESET}"
        return
    fi

    # Check for unpulled commits
    unpulled=$(git -C "$repo_dir" log ..@{u} --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$unpulled" -gt 0 ]; then
        printf "${C_CYAN}${unpulled} To Pull${C_RESET}"
        return
    fi

    printf "${C_GREEN}OK${C_RESET}"
}

# Clone a repository
repo_clone() {
    repo_name="$1"
    repo_url="$2"
    repo_dir="$WORKDIR/$repo_name"

    printf "$INFO Cloning ${C_BOLD}$repo_name${C_RESET}...\n"

    if git clone "$repo_url" "$repo_dir" 2>&1; then
        printf "$OK ${C_GREEN}Cloned${C_RESET}\n"
        return 0
    else
        printf "$FAIL ${C_RED}Clone failed${C_RESET}\n"
        return 1
    fi
}

# Pull changes
repo_pull() {
    repo_name="$1"
    strategy="${2:-theirs}"  # default: remote wins
    repo_dir="$WORKDIR/$repo_name"

    if [ ! -d "$repo_dir" ]; then
        repo_clone "$repo_name" "$(get_repo_url "$repo_name")"
        return
    fi

    printf "$INFO Pulling ${C_BOLD}$repo_name${C_RESET} (strategy: $strategy)...\n"

    # Stash local changes if any
    if [ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]; then
        printf "  ${C_DIM}Stashing local changes...${C_RESET}\n"
        git -C "$repo_dir" stash -q
        STASHED=1
    else
        STASHED=0
    fi

    # Pull with strategy
    if git -C "$repo_dir" pull --no-rebase --strategy-option="$strategy" 2>&1; then
        printf "$OK ${C_GREEN}Pulled${C_RESET}\n"
    else
        printf "$FAIL ${C_RED}Pull failed${C_RESET}\n"
    fi

    # Restore stashed changes
    if [ "$STASHED" = "1" ]; then
        printf "  ${C_DIM}Restoring local changes...${C_RESET}\n"
        git -C "$repo_dir" stash pop -q 2>/dev/null || true
    fi
}

# Push changes
repo_push() {
    repo_name="$1"
    repo_dir="$WORKDIR/$repo_name"

    if [ ! -d "$repo_dir" ]; then
        printf "$FAIL ${C_RED}$repo_name not cloned${C_RESET}\n"
        return 1
    fi

    printf "$INFO Pushing ${C_BOLD}$repo_name${C_RESET}...\n"

    if git -C "$repo_dir" push 2>&1; then
        printf "$OK ${C_GREEN}Pushed${C_RESET}\n"
    else
        printf "$FAIL ${C_RED}Push failed${C_RESET}\n"
    fi
}

# Sync: commit local, pull, push
repo_sync() {
    repo_name="$1"
    strategy="${2:-theirs}"
    repo_dir="$WORKDIR/$repo_name"

    if [ ! -d "$repo_dir" ]; then
        repo_clone "$repo_name" "$(get_repo_url "$repo_name")"
        return
    fi

    printf "$INFO Syncing ${C_BOLD}$repo_name${C_RESET}...\n"

    # Stage and commit local changes
    if [ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]; then
        printf "  ${C_DIM}Committing local changes...${C_RESET}\n"
        git -C "$repo_dir" add -A
        git -C "$repo_dir" commit -q -m "sync: auto-commit" 2>/dev/null || true
    fi

    # Fetch and pull
    git -C "$repo_dir" fetch -q 2>/dev/null || true

    if git -C "$repo_dir" pull --no-rebase --strategy-option="$strategy" -q 2>&1; then
        printf "$OK ${C_GREEN}Pulled${C_RESET}\n"
    else
        printf "$WARN ${C_YELLOW}Pull had conflicts${C_RESET}\n"
    fi

    # Push
    if git -C "$repo_dir" push -q 2>&1; then
        printf "$OK ${C_GREEN}Pushed${C_RESET}\n"
    else
        printf "$WARN ${C_YELLOW}Push failed${C_RESET}\n"
    fi
}

# Fetch all repos
repo_fetch() {
    repo_name="$1"
    repo_dir="$WORKDIR/$repo_name"

    if [ ! -d "$repo_dir" ]; then
        printf "$FAIL ${C_RED}$repo_name not cloned${C_RESET}\n"
        return
    fi

    printf "$INFO Fetching ${C_BOLD}$repo_name${C_RESET}..."

    if git -C "$repo_dir" fetch -q 2>&1; then
        printf " $OK\n"
    else
        printf " $FAIL\n"
    fi
}

# =============================================================================
# DETAILED STATUS FUNCTIONS
# =============================================================================

# Check if repo is cloned
check_cloned() {
    [ -d "$1/.git" ] && echo "1" || echo "0"
}

# Check for uncommitted changes
check_uncommitted() {
    repo_dir="$1"
    [ ! -d "$repo_dir/.git" ] && echo "-" && return
    if [ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]; then
        echo "1"
    else
        echo "0"
    fi
}

# Check for unpushed commits
check_unpushed() {
    repo_dir="$1"
    [ ! -d "$repo_dir/.git" ] && echo "-" && return
    if ! git -C "$repo_dir" rev-parse @{u} >/dev/null 2>&1; then
        echo "?"  # No upstream
        return
    fi
    count=$(git -C "$repo_dir" log @{u}.. --oneline 2>/dev/null | wc -l | tr -d ' ')
    echo "$count"
}

# Check for unpulled commits (requires fetch first)
check_unpulled() {
    repo_dir="$1"
    [ ! -d "$repo_dir/.git" ] && echo "-" && return
    if ! git -C "$repo_dir" rev-parse @{u} >/dev/null 2>&1; then
        echo "?"  # No upstream
        return
    fi
    count=$(git -C "$repo_dir" log ..@{u} --oneline 2>/dev/null | wc -l | tr -d ' ')
    echo "$count"
}

# Check GitHub Actions status (requires gh CLI)
check_gh_actions() {
    repo_dir="$1"
    repo_name="$2"

    [ ! -d "$repo_dir/.git" ] && echo "-" && return

    # Check if gh is available
    if ! command -v gh >/dev/null 2>&1; then
        echo "?"
        return
    fi

    # Get remote URL and extract owner/repo
    remote_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null)
    if [ -z "$remote_url" ]; then
        echo "?"
        return
    fi

    # Extract owner/repo from git@github.com:owner/repo.git
    gh_repo=$(echo "$remote_url" | sed 's/.*github.com[:/]\([^/]*\/[^.]*\).*/\1/')

    # Get last workflow run status
    status=$(gh run list --repo "$gh_repo" --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null)

    case "$status" in
        success) echo "✓" ;;
        failure) echo "✗" ;;
        cancelled) echo "○" ;;
        "") echo "-" ;;
        *) echo "?" ;;
    esac
}

# Format cell with color based on value
format_cell() {
    value="$1"
    type="$2"  # cloned, uncommitted, unpushed, unpulled, actions

    case "$type" in
        cloned)
            if [ "$value" = "1" ]; then
                printf "${C_GREEN}Yes${C_RESET}"
            else
                printf "${C_RED}No${C_RESET}"
            fi
            ;;
        uncommitted)
            case "$value" in
                "-") printf "${C_DIM}--${C_RESET}" ;;
                "0") printf "${C_GREEN}Clean${C_RESET}" ;;
                "1") printf "${C_YELLOW}Dirty${C_RESET}" ;;
                *) printf "${C_DIM}?${C_RESET}" ;;
            esac
            ;;
        unpushed)
            case "$value" in
                "-") printf "${C_DIM}--${C_RESET}" ;;
                "?") printf "${C_DIM}?${C_RESET}" ;;
                "0") printf "${C_GREEN}0${C_RESET}" ;;
                *) printf "${C_YELLOW}${value}${C_RESET}" ;;
            esac
            ;;
        unpulled)
            case "$value" in
                "-") printf "${C_DIM}--${C_RESET}" ;;
                "?") printf "${C_DIM}?${C_RESET}" ;;
                "0") printf "${C_GREEN}0${C_RESET}" ;;
                *) printf "${C_CYAN}${value}${C_RESET}" ;;
            esac
            ;;
        actions)
            case "$value" in
                "-") printf "${C_DIM}--${C_RESET}" ;;
                "?") printf "${C_DIM}?${C_RESET}" ;;
                "✓") printf "${C_GREEN}✓${C_RESET}" ;;
                "✗") printf "${C_RED}✗${C_RESET}" ;;
                "○") printf "${C_YELLOW}○${C_RESET}" ;;
                *) printf "${C_DIM}?${C_RESET}" ;;
            esac
            ;;
    esac
}

# =============================================================================
# CLI COMMANDS
# =============================================================================

cmd_status() {
    printf "${C_BOLD}=== Repository Status ===${C_RESET}\n"
    printf "${C_DIM}Workdir: $WORKDIR${C_RESET}\n\n"

    # Header
    printf "${C_BOLD}%-20s  %-8s  %-8s  %-8s  %-8s  %-4s${C_RESET}\n" \
        "Repository" "Cloned" "Local" "Unpushed" "To Pull" "CI"
    printf "${C_DIM}────────────────────  ────────  ────────  ────────  ────────  ────${C_RESET}\n"

    for repo_name in $(get_repo_names); do
        repo_dir="$WORKDIR/$repo_name"

        # Get all statuses
        cloned=$(check_cloned "$repo_dir")
        uncommitted=$(check_uncommitted "$repo_dir")
        unpushed=$(check_unpushed "$repo_dir")
        unpulled=$(check_unpulled "$repo_dir")
        actions=$(check_gh_actions "$repo_dir" "$repo_name")

        # Print repo name (padded)
        printf "%-20s  " "$repo_name"

        # Cloned column (8 chars)
        if [ "$cloned" = "1" ]; then
            printf "${C_GREEN}%-8s${C_RESET}" "Yes"
        else
            printf "${C_RED}%-8s${C_RESET}" "No"
        fi
        printf "  "

        # Local column (8 chars)
        case "$uncommitted" in
            "-") printf "${C_DIM}%-8s${C_RESET}" "--" ;;
            "0") printf "${C_GREEN}%-8s${C_RESET}" "Clean" ;;
            "1") printf "${C_YELLOW}%-8s${C_RESET}" "Dirty" ;;
            *) printf "${C_DIM}%-8s${C_RESET}" "?" ;;
        esac
        printf "  "

        # Unpushed column (8 chars)
        case "$unpushed" in
            "-") printf "${C_DIM}%-8s${C_RESET}" "--" ;;
            "?") printf "${C_DIM}%-8s${C_RESET}" "?" ;;
            "0") printf "${C_GREEN}%-8s${C_RESET}" "0" ;;
            *) printf "${C_YELLOW}%-8s${C_RESET}" "$unpushed" ;;
        esac
        printf "  "

        # To Pull column (8 chars)
        case "$unpulled" in
            "-") printf "${C_DIM}%-8s${C_RESET}" "--" ;;
            "?") printf "${C_DIM}%-8s${C_RESET}" "?" ;;
            "0") printf "${C_GREEN}%-8s${C_RESET}" "0" ;;
            *) printf "${C_CYAN}%-8s${C_RESET}" "$unpulled" ;;
        esac
        printf "  "

        # CI column (4 chars)
        case "$actions" in
            "-") printf "${C_DIM}%-4s${C_RESET}" "--" ;;
            "?") printf "${C_DIM}%-4s${C_RESET}" "?" ;;
            "✓") printf "${C_GREEN}%-4s${C_RESET}" "✓" ;;
            "✗") printf "${C_RED}%-4s${C_RESET}" "✗" ;;
            "○") printf "${C_YELLOW}%-4s${C_RESET}" "○" ;;
            *) printf "${C_DIM}%-4s${C_RESET}" "?" ;;
        esac

        printf "\n"
    done

    printf "\n${C_DIM}Legend: Local=uncommitted changes, CI=GitHub Actions${C_RESET}\n"
}

cmd_status_fetch() {
    printf "${C_BOLD}=== Repository Status (with fetch) ===${C_RESET}\n"
    printf "${C_DIM}Workdir: $WORKDIR${C_RESET}\n"
    printf "${C_DIM}Fetching from remotes...${C_RESET}\n\n"

    # Fetch all repos first
    for repo_name in $(get_repo_names); do
        repo_dir="$WORKDIR/$repo_name"
        if [ -d "$repo_dir/.git" ]; then
            git -C "$repo_dir" fetch -q 2>/dev/null &
        fi
    done
    wait

    # Now show status
    cmd_status
}

cmd_clone_menu() {
    printf "${C_BOLD}=== Clone Repositories ===${C_RESET}\n"
    printf "${C_DIM}Workdir: $WORKDIR${C_RESET}\n\n"

    # Build list of uncloned repos
    uncloned=""
    idx=1
    for repo_name in $(get_repo_names); do
        repo_dir="$WORKDIR/$repo_name"
        if [ ! -d "$repo_dir/.git" ]; then
            uncloned="$uncloned$idx:$repo_name\n"
            printf "  ${C_CYAN}%2d${C_RESET}) %s\n" "$idx" "$repo_name"
            idx=$((idx + 1))
        fi
    done

    if [ -z "$uncloned" ]; then
        printf "${C_GREEN}All repositories are already cloned.${C_RESET}\n"
        return
    fi

    printf "\n  ${C_CYAN} a${C_RESET}) Clone ALL uncloned repos\n"
    printf "  ${C_CYAN} q${C_RESET}) Cancel\n"
    printf "\n${C_BOLD}Select repos to clone (comma-separated, e.g., 1,3,5):${C_RESET} "
    read -r selection

    case "$selection" in
        q|Q|"") return ;;
        a|A)
            # Clone all uncloned
            for repo_name in $(get_repo_names); do
                repo_dir="$WORKDIR/$repo_name"
                if [ ! -d "$repo_dir/.git" ]; then
                    repo_url=$(get_repo_url "$repo_name")
                    repo_clone "$repo_name" "$repo_url"
                    echo ""
                fi
            done
            ;;
        *)
            # Parse comma-separated numbers
            echo "$selection" | tr ',' '\n' | while read -r num; do
                num=$(echo "$num" | tr -d ' ')
                [ -z "$num" ] && continue

                # Find repo by index
                repo_name=$(printf "$uncloned" | grep "^$num:" | cut -d: -f2)
                if [ -n "$repo_name" ]; then
                    repo_url=$(get_repo_url "$repo_name")
                    repo_clone "$repo_name" "$repo_url"
                    echo ""
                else
                    printf "$WARN ${C_YELLOW}Invalid selection: $num${C_RESET}\n"
                fi
            done
            ;;
    esac
}

cmd_sync() {
    strategy="${1:-theirs}"
    printf "${C_BOLD}=== Syncing All Repos ===${C_RESET}\n\n"

    for repo_name in $(get_repo_names); do
        repo_sync "$repo_name" "$strategy"
        echo ""
    done
}

cmd_pull() {
    strategy="${1:-theirs}"
    printf "${C_BOLD}=== Pulling All Repos ===${C_RESET}\n\n"

    for repo_name in $(get_repo_names); do
        repo_pull "$repo_name" "$strategy"
        echo ""
    done
}

cmd_push() {
    printf "${C_BOLD}=== Pushing All Repos ===${C_RESET}\n\n"

    for repo_name in $(get_repo_names); do
        repo_push "$repo_name"
        echo ""
    done
}

cmd_fetch() {
    printf "${C_BOLD}=== Fetching All Repos ===${C_RESET}\n\n"

    for repo_name in $(get_repo_names); do
        repo_fetch "$repo_name"
    done
}

# =============================================================================
# SHELL TUI (fallback)
# =============================================================================

tui_shell() {
    # Simple interactive menu using shell
    while true; do
        clear
        printf "${C_BOLD}${C_CYAN}╔════════════════════════════════════════╗${C_RESET}\n"
        printf "${C_BOLD}${C_CYAN}║       gcl - Git Manager (Shell TUI)    ║${C_RESET}\n"
        printf "${C_BOLD}${C_CYAN}╚════════════════════════════════════════╝${C_RESET}\n\n"

        printf "${C_DIM}Workdir: $WORKDIR${C_RESET}\n"
        printf "${C_DIM}Repos:   $REPO_COUNT${C_RESET}\n\n"

        printf "${C_BOLD}Commands:${C_RESET}\n"
        printf "  ${C_CYAN}1${C_RESET}) Status   - Show repo status\n"
        printf "  ${C_CYAN}2${C_RESET}) Sync     - Commit, pull, push all\n"
        printf "  ${C_CYAN}3${C_RESET}) Pull     - Pull all repos\n"
        printf "  ${C_CYAN}4${C_RESET}) Push     - Push all repos\n"
        printf "  ${C_CYAN}5${C_RESET}) Fetch    - Fetch all repos\n"
        printf "  ${C_CYAN}q${C_RESET}) Quit\n\n"

        printf "Choice: "
        read -r choice

        case "$choice" in
            1) cmd_status; printf "\nPress Enter..."; read -r _ ;;
            2) cmd_sync; printf "\nPress Enter..."; read -r _ ;;
            3) cmd_pull; printf "\nPress Enter..."; read -r _ ;;
            4) cmd_push; printf "\nPress Enter..."; read -r _ ;;
            5) cmd_fetch; printf "\nPress Enter..."; read -r _ ;;
            q|Q) exit 0 ;;
            *) ;;
        esac
    done
}

# =============================================================================
# HELP
# =============================================================================

show_help() {
    printf "${C_BOLD}gcl - Git Clone/Pull/Push Manager${C_RESET}\n\n"

    printf "${C_BOLD}Usage:${C_RESET}\n"
    printf "  ./gcl.sh              ${C_DIM}# Launch TUI (Python or Shell)${C_RESET}\n"
    printf "  ./gcl.sh --sh         ${C_DIM}# Force shell TUI${C_RESET}\n"
    printf "  ./gcl.sh --py         ${C_DIM}# Force Python TUI${C_RESET}\n"
    printf "  ./gcl.sh <command>    ${C_DIM}# CLI mode${C_RESET}\n\n"

    printf "${C_BOLD}Commands:${C_RESET}\n"
    printf "  ${C_CYAN}status${C_RESET}    Show repository status table\n"
    printf "  ${C_CYAN}fetch${C_RESET}     Fetch + show status (checks remote)\n"
    printf "  ${C_CYAN}clone${C_RESET}     Interactive clone menu\n"
    printf "  ${C_CYAN}sync${C_RESET}      Commit local, pull, push all\n"
    printf "  ${C_CYAN}pull${C_RESET}      Pull all repositories\n"
    printf "  ${C_CYAN}push${C_RESET}      Push all repositories\n\n"

    printf "${C_BOLD}Status Columns:${C_RESET}\n"
    printf "  ${C_DIM}Cloned${C_RESET}    - Repository exists locally\n"
    printf "  ${C_DIM}Local${C_RESET}     - Uncommitted changes (Clean/Dirty)\n"
    printf "  ${C_DIM}Unpushed${C_RESET}  - Commits not pushed to remote\n"
    printf "  ${C_DIM}To Pull${C_RESET}   - Commits on remote not pulled\n"
    printf "  ${C_DIM}CI${C_RESET}        - GitHub Actions status (requires gh)\n\n"

    printf "${C_BOLD}Config:${C_RESET}\n"
    printf "  ${C_DIM}$CONFIG_FILE${C_RESET}\n\n"

    printf "${C_BOLD}Workdir:${C_RESET}\n"
    printf "  ${C_DIM}$WORKDIR${C_RESET}\n"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse config first
    parse_config

    case "${1:-}" in
        --help|-h|help)
            show_help
            ;;
        --sh|--shell)
            tui_shell
            ;;
        --py|--python)
            if [ -f "$PYTHON_TUI" ] && command -v python3 >/dev/null 2>&1; then
                python3 "$PYTHON_TUI" "${@:2}"
            else
                printf "$FAIL ${C_RED}Python TUI not available${C_RESET}\n"
                printf "Falling back to shell TUI...\n\n"
                sleep 1
                tui_shell
            fi
            ;;
        status)
            cmd_status
            ;;
        fetch)
            cmd_status_fetch
            ;;
        clone)
            cmd_clone_menu
            ;;
        sync)
            cmd_sync "${2:-theirs}"
            ;;
        pull)
            cmd_pull "${2:-theirs}"
            ;;
        push)
            cmd_push
            ;;
        "")
            # Default: try Python TUI, fallback to shell
            if [ -f "$PYTHON_TUI" ] && command -v python3 >/dev/null 2>&1; then
                python3 "$PYTHON_TUI"
            else
                tui_shell
            fi
            ;;
        *)
            printf "$FAIL ${C_RED}Unknown command: $1${C_RESET}\n\n"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
