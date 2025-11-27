#!/bin/sh

#=====================================
# MAIN BUILD ORCHESTRATOR
#=====================================
# This script orchestrates builds for all sub-projects
# and replicates the GitHub Actions workflow locally.
#
# Usage: ./1.ops/build_main.sh <action> [options]
#
# POSIX-compliant shell script

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# PID file for tracking background processes
PID_FILE="${PROJECT_ROOT}/1.ops/.dev-servers.pid"

# Server URLs mapping (sequential ports starting at 8000)
URL_ROOT="http://localhost:8000/"
URL_LINKTREE="http://localhost:8001/"
URL_CV_WEB="http://localhost:8002/"
URL_MYFEED="http://localhost:8003/"
URL_MYPROFILE="http://localhost:8004/"
URL_NEXUS="http://localhost:8005/"
URL_CLOUD="http://localhost:8006/"
URL_FEED="http://localhost:8007/"
URL_OTHERS="http://localhost:8008/"
URL_HEALTH="http://localhost:8009/"
URL_MARKET="http://localhost:8010/"

# Banner function
print_banner() {
    printf "${CYAN}\n"
    printf "=====================================\n"
    printf "  MAIN BUILD ORCHESTRATOR\n"
    printf "=====================================\n"
    printf "${NC}\n"
}

# Get running servers status
get_running_servers() {
    _servers=""
    _count=0

    # Check live-server processes by port
    if pgrep -f "live-server.*8000" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Root               ${BLUE}${URL_ROOT}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8001" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Linktree           ${BLUE}${URL_LINKTREE}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8002" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} CV Web             ${BLUE}${URL_CV_WEB}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8003" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} MyFeed             ${BLUE}${URL_MYFEED}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8004" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} MyProfile          ${BLUE}${URL_MYPROFILE}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8005" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Nexus              ${BLUE}${URL_NEXUS}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8006" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Cloud              ${BLUE}${URL_CLOUD}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8007" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Feed Yourself      ${BLUE}${URL_FEED}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8008" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Others             ${BLUE}${URL_OTHERS}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8009" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Health Tracker     ${BLUE}${URL_HEALTH}${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "live-server.*8010" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Market Watch       ${BLUE}${URL_MARKET}${NC}\n"
        _count=$((_count + 1))
    fi
    # Generic live-server check (fallback for other ports)
    if pgrep -f "live-server" >/dev/null 2>&1; then
        _other_live=$(pgrep -f "live-server" 2>/dev/null | while read pid; do
            ps -p "$pid" -o args= 2>/dev/null | grep -v "800[0-9]" || true
        done)
        if [ -n "$_other_live" ]; then
            _servers="${_servers}  ${GREEN}*${NC} live-server        ${BLUE}(check terminal)${NC}\n"
            _count=$((_count + 1))
        fi
    fi

    # Check Vite dev servers
    if pgrep -f "vite.*myfeed" >/dev/null 2>&1 || pgrep -f "node.*myfeed.*vite" >/dev/null 2>&1; then
        _servers="${_servers}  ${CYAN}*${NC} MyFeed (Vite)      ${BLUE}http://localhost:5173${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "vite.*myprofile" >/dev/null 2>&1 || pgrep -f "node.*myprofile.*vite" >/dev/null 2>&1; then
        _servers="${_servers}  ${CYAN}*${NC} MyProfile (Vite)   ${BLUE}http://localhost:5174${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "vite.*nexus" >/dev/null 2>&1 || pgrep -f "node.*nexus.*vite" >/dev/null 2>&1; then
        _servers="${_servers}  ${CYAN}*${NC} Nexus (Vite)       ${BLUE}http://localhost:5175${NC}\n"
        _count=$((_count + 1))
    fi
    # Generic Vite check (fallback - only if no specific vite detected)
    if pgrep -f "node.*vite" >/dev/null 2>&1; then
        # Check if any vite process is NOT from known projects
        _unknown_vite=$(pgrep -f "node.*vite" 2>/dev/null | while read pid; do
            _cmd=$(ps -p "$pid" -o args= 2>/dev/null)
            echo "$_cmd" | grep -qE "myfeed|myprofile|nexus" || echo "$_cmd"
        done)
        if [ -n "$_unknown_vite" ]; then
            _servers="${_servers}  ${CYAN}*${NC} Vite Server        ${BLUE}(check terminal)${NC}\n"
            _count=$((_count + 1))
        fi
    fi

    # Check Python http.server
    if pgrep -f "python.*http.server" >/dev/null 2>&1; then
        _servers="${_servers}  ${GREEN}*${NC} Python HTTP        ${BLUE}(check terminal)${NC}\n"
        _count=$((_count + 1))
    fi

    # Check watch processes (Sass/TypeScript)
    if pgrep -f "sass.*--watch" >/dev/null 2>&1; then
        _servers="${_servers}  ${YELLOW}~${NC} Sass Watch         ${YELLOW}(file watcher)${NC}\n"
        _count=$((_count + 1))
    fi
    if pgrep -f "tsc.*--watch" >/dev/null 2>&1; then
        _servers="${_servers}  ${YELLOW}~${NC} TypeScript Watch   ${YELLOW}(file watcher)${NC}\n"
        _count=$((_count + 1))
    fi

    # Check tmux sessions
    if command -v tmux >/dev/null 2>&1; then
        for session in build-root-sass build-root-ts build-linktree build-cv-web build-myfeed build-myprofile build-nexus build-cloud build-feed build-others build-health build-market; do
            if tmux has-session -t "$session" 2>/dev/null; then
                case "$session" in
                    build-root-sass)  _servers="${_servers}  ${GREEN}*${NC} Root (tmux)        ${BLUE}${URL_ROOT}${NC}\n" ;;
                    build-root-ts)    _servers="${_servers}  ${YELLOW}~${NC} Root TS (tmux)     ${YELLOW}(watcher)${NC}\n" ;;
                    build-linktree)   _servers="${_servers}  ${GREEN}*${NC} Linktree (tmux)    ${BLUE}${URL_LINKTREE}${NC}\n" ;;
                    build-cv-web)     _servers="${_servers}  ${GREEN}*${NC} CV Web (tmux)      ${BLUE}${URL_CV_WEB}${NC}\n" ;;
                    build-myfeed)     _servers="${_servers}  ${GREEN}*${NC} MyFeed (tmux)      ${BLUE}${URL_MYFEED}${NC}\n" ;;
                    build-myprofile)  _servers="${_servers}  ${GREEN}*${NC} MyProfile (tmux)   ${BLUE}${URL_MYPROFILE}${NC}\n" ;;
                    build-nexus)      _servers="${_servers}  ${GREEN}*${NC} Nexus (tmux)       ${BLUE}${URL_NEXUS}${NC}\n" ;;
                    build-cloud)      _servers="${_servers}  ${GREEN}*${NC} Cloud (tmux)       ${BLUE}${URL_CLOUD}${NC}\n" ;;
                    build-feed)       _servers="${_servers}  ${GREEN}*${NC} Feed (tmux)        ${BLUE}${URL_FEED}${NC}\n" ;;
                    build-others)     _servers="${_servers}  ${GREEN}*${NC} Others (tmux)      ${BLUE}${URL_OTHERS}${NC}\n" ;;
                    build-health)     _servers="${_servers}  ${GREEN}*${NC} Health (tmux)      ${BLUE}${URL_HEALTH}${NC}\n" ;;
                    build-market)     _servers="${_servers}  ${GREEN}*${NC} Market (tmux)      ${BLUE}${URL_MARKET}${NC}\n" ;;
                esac
                _count=$((_count + 1))
            fi
        done
    fi

    RUNNING_SERVERS="$_servers"
    RUNNING_COUNT="$_count"
}

# Print status box
print_status_box() {
    get_running_servers

    printf "\n"
    printf "${MAGENTA}+----------------------------------------------------------+${NC}\n"
    printf "${MAGENTA}|${NC}  ${CYAN}SERVER STATUS${NC}                                           ${MAGENTA}|${NC}\n"
    printf "${MAGENTA}+----------------------------------------------------------+${NC}\n"

    if [ "$RUNNING_COUNT" -eq 0 ]; then
        printf "${MAGENTA}|${NC}  ${YELLOW}No servers currently running${NC}                            ${MAGENTA}|${NC}\n"
    else
        printf "${MAGENTA}|${NC}  ${GREEN}$RUNNING_COUNT server(s)/watcher(s) running:${NC}                         ${MAGENTA}|${NC}\n"
        printf "${MAGENTA}|${NC}                                                          ${MAGENTA}|${NC}\n"
        printf "%b" "$RUNNING_SERVERS" | while IFS= read -r line; do
            printf "${MAGENTA}|${NC}%-58b${MAGENTA}|${NC}\n" "$line"
        done
    fi

    printf "${MAGENTA}+----------------------------------------------------------+${NC}\n"
    printf "\n"
}

# Usage information
print_usage() {
    printf "${BLUE}===============================================================================${NC}\n"
    printf "${CYAN}                        MAIN BUILD ORCHESTRATOR                                ${NC}\n"
    printf "${BLUE}===============================================================================${NC}\n"
    printf "\n"
    printf "${YELLOW}USAGE:${NC}  ./1.ops/build_main.sh <action> [options]\n"
    printf "\n"
    printf "${YELLOW}BUILD:${NC}\n"
    printf "  ${GREEN}build${NC}              # All projects\n"
    printf "  ${GREEN}build-root${NC}         # Root - Sass + TypeScript\n"
    printf "  ${GREEN}build-linktree${NC}     # Linktree - Static HTML/CSS/JS\n"
    printf "  ${GREEN}build-cv-web${NC}       # CV Web - Sass\n"
    printf "  ${GREEN}build-myfeed${NC}       # MyFeed - Vue 3 + Vite\n"
    printf "  ${GREEN}build-myprofile${NC}    # MyProfile - SvelteKit\n"
    printf "  ${GREEN}build-nexus${NC}        # Nexus - Vue 3 + Tailwind\n"
    printf "  ${GREEN}build-cloud${NC}        # Cloud - Sass + TypeScript\n"
    printf "  ${GREEN}build-feed${NC}         # Feed Yourself - Static HTML\n"
    printf "  ${GREEN}build-others${NC}       # Others - Python\n"
    printf "  ${GREEN}build-health${NC}       # Health Tracker - Static HTML\n"
    printf "  ${GREEN}build-market${NC}       # Market Watch - Sass + TypeScript\n"
    printf "\n"
    printf "${YELLOW}DEV SERVER:${NC}\n"
    printf "  ${GREEN}dev${NC}                # All - Start all servers\n"
    printf "  ${GREEN}dev-root${NC}           # Root - npm-live :8000\n"
    printf "  ${GREEN}dev-linktree${NC}       # Linktree - npm-live :8001\n"
    printf "  ${GREEN}dev-cv-web${NC}         # CV Web - npm-live :8002\n"
    printf "  ${GREEN}dev-myfeed${NC}         # MyFeed - Vite :8003\n"
    printf "  ${GREEN}dev-myprofile${NC}      # MyProfile - Vite :8004\n"
    printf "  ${GREEN}dev-nexus${NC}          # Nexus - Vite :8005\n"
    printf "  ${GREEN}dev-cloud${NC}          # Cloud - npm-live :8006\n"
    printf "  ${GREEN}dev-feed${NC}           # Feed Yourself - npm-live :8007\n"
    printf "  ${GREEN}dev-others${NC}         # Others - npm-live :8008\n"
    printf "  ${GREEN}dev-health${NC}         # Health Tracker - npm-live :8009\n"
    printf "  ${GREEN}dev-market${NC}         # Market Watch - npm-live :8010\n"
    printf "\n"
    printf "${YELLOW}UTILITY:${NC}\n"
    printf "  ${GREEN}list${NC}               # List running servers/watchers\n"
    printf "  ${GREEN}kill${NC}               # Kill all dev servers\n"
    printf "  ${GREEN}clean${NC}              # Clean build artifacts\n"
    printf "  ${GREEN}clean-all${NC}          # Clean artifacts + node_modules\n"
    printf "  ${GREEN}test${NC}               # Run all tests\n"
    printf "  ${GREEN}help${NC}               # Show this help\n"
    printf "\n"
    printf "${YELLOW}OPTIONS:${NC}  ${GREEN}-v, --verbose${NC}  |  ${GREEN}-f, --force${NC}\n"
    printf "\n"
    printf "${YELLOW}PROJECT STRUCTURE:${NC}\n"
    printf "${BLUE}------------------------------------------------------------------------------------------------------${NC}\n"
    printf "  ${MAGENTA}%-13s  %-10s  %-10s  %-10s  %-15s  %s${NC}\n" "Project" "Framework" "CSS" "JavaScript" "Dev Server" "Watch"
    printf "${BLUE}------------------------------------------------------------------------------------------------------${NC}\n"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "Root" "-" "Sass" "TypeScript" "npm-live :8000" "Sass, TS"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "Linktree" "-" "Vanilla" "Vanilla" "npm-live :8001" "-"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "CV Web" "-" "Sass" "-" "npm-live :8002" "Sass"
    printf "  ${CYAN}%-13s${NC}  ${GREEN}%-10s${NC}  %-10s  %-10s  ${CYAN}%-15s${NC}  ${YELLOW}%s${NC}\n" "MyFeed" "Vue 3" "Sass" "TypeScript" "Vite :8003" "HMR"
    printf "  ${CYAN}%-13s${NC}  ${GREEN}%-10s${NC}  %-10s  %-10s  ${CYAN}%-15s${NC}  ${YELLOW}%s${NC}\n" "MyProfile" "SvelteKit" "Sass" "TypeScript" "Vite :8004" "HMR"
    printf "  ${CYAN}%-13s${NC}  ${GREEN}%-10s${NC}  %-10s  %-10s  ${CYAN}%-15s${NC}  ${YELLOW}%s${NC}\n" "Nexus" "Vue 3" "Tailwind" "TypeScript" "Vite :8005" "HMR"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "Cloud" "-" "Sass" "TypeScript" "npm-live :8006" "Sass, TS"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "Feed Yourself" "-" "Embedded" "Embedded" "npm-live :8007" "-"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "Others" "-" "-" "Python" "npm-live :8008" "-"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "HealthTracker" "-" "Tailwind" "Vanilla" "npm-live :8009" "-"
    printf "  ${CYAN}%-13s${NC}  %-10s  %-10s  %-10s  ${GREEN}%-15s${NC}  ${YELLOW}%s${NC}\n" "MarketWatch" "-" "Sass" "TypeScript" "npm-live :8010" "Sass, TS"
    printf "${BLUE}------------------------------------------------------------------------------------------------------${NC}\n"

    # Show status box in help
    print_status_box
}

# Logging functions
log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

log_section() {
    printf "\n${MAGENTA}========================================${NC}\n"
    printf "${MAGENTA}  %s${NC}\n" "$1"
    printf "${MAGENTA}========================================${NC}\n\n"
}

# Print server started message with URL
print_server_started() {
    _name="$1"
    _url="$2"
    _type="${3:-server}"

    printf "\n"
    printf "${GREEN}+----------------------------------------------------------+${NC}\n"
    printf "${GREEN}|${NC}  ${CYAN}%s STARTED${NC}\n" "$_name"
    printf "${GREEN}+----------------------------------------------------------+${NC}\n"
    if [ "$_type" = "watcher" ]; then
        printf "${GREEN}|${NC}  ${YELLOW}Type:${NC} File Watcher (no HTTP server)\n"
    else
        printf "${GREEN}|${NC}  ${YELLOW}URL:${NC}  ${BLUE}%s${NC}\n" "$_url"
    fi
    printf "${GREEN}|${NC}  ${YELLOW}Stop:${NC} ./1.ops/build_main.sh kill\n"
    printf "${GREEN}+----------------------------------------------------------+${NC}\n"
    printf "\n"
}

# Check if build.sh exists in a directory
check_build_script() {
    _dir="$1"
    _build_script="$PROJECT_ROOT/$_dir/1.ops/build.sh"

    if [ -f "$_build_script" ]; then
        return 0
    else
        return 1
    fi
}

# Execute build script
execute_build() {
    _project="$1"
    _action="$2"
    _build_script="$PROJECT_ROOT/$_project/1.ops/build.sh"

    # Special case for myprofile which uses 1.1.ops
    if [ "$_project" = "myprofile" ]; then
        _build_script="$PROJECT_ROOT/$_project/1.1.ops/build.sh"
    fi

    log_section "Building: $_project"

    if [ -f "$_build_script" ]; then
        log_info "Executing: $_build_script $_action"
        if sh "$_build_script" "$_action"; then
            log_success "$_project build completed"
            return 0
        else
            log_error "$_project build failed"
            return 1
        fi
    else
        log_warning "Build script not found: $_build_script"
        return 1
    fi
}

# Build all projects
build_all() {
    _force="${1:-false}"

    log_section "Building All Projects"

    if [ "$_force" = "true" ]; then
        log_info "Force rebuild enabled - cleaning first..."
        clean_all_builds
    fi

    _failed=0

    # Build root Sass
    log_info "Building root Sass..."
    if [ -d "$PROJECT_ROOT/3.sass" ]; then
        (cd "$PROJECT_ROOT/3.sass" && npm install > /dev/null 2>&1 && npm run sass:build) || _failed=$((_failed + 1))
    fi

    # Build root TypeScript
    log_info "Building root TypeScript..."
    if [ -d "$PROJECT_ROOT/4.ts" ]; then
        (cd "$PROJECT_ROOT/4.ts" && npm install > /dev/null 2>&1 && npm run ts:build) || _failed=$((_failed + 1))
    fi

    # Build each sub-project
    execute_build "linktree" "build" || _failed=$((_failed + 1))
    execute_build "cv_web" "build" || _failed=$((_failed + 1))
    execute_build "myfeed" "build" || _failed=$((_failed + 1))
    execute_build "myprofile" "build" || _failed=$((_failed + 1))
    execute_build "cloud" "build" || _failed=$((_failed + 1))
    execute_build "feed_yourself" "build" || _failed=$((_failed + 1))
    execute_build "others" "build" || _failed=$((_failed + 1))
    execute_build "health_tracker" "build" || _failed=$((_failed + 1))
    execute_build "market_watch" "build" || _failed=$((_failed + 1))

    if [ "$_failed" -eq 0 ]; then
        log_success "All builds completed successfully!"
        return 0
    else
        log_error "$_failed build(s) failed"
        return 1
    fi
}

# Clean build artifacts
clean_all_builds() {
    log_section "Cleaning Build Artifacts"

    # Clean root
    log_info "Cleaning root build artifacts..."
    rm -rf "$PROJECT_ROOT/style.css" "$PROJECT_ROOT/style.css.map"
    rm -rf "$PROJECT_ROOT/script.js" "$PROJECT_ROOT/script.js.map"

    # Clean sub-projects
    execute_build "linktree" "clean" || true
    execute_build "cv_web" "clean" || true
    execute_build "myfeed" "clean" || true
    execute_build "myprofile" "clean" || true
    execute_build "cloud" "clean" || true
    execute_build "feed_yourself" "clean" || true
    execute_build "others" "clean" || true
    execute_build "health_tracker" "clean" || true
    execute_build "market_watch" "clean" || true

    log_success "All build artifacts cleaned"
}

# Deep clean (including node_modules)
clean_deep() {
    log_section "Deep Cleaning (including node_modules)"

    clean_all_builds

    log_info "Removing node_modules..."
    find "$PROJECT_ROOT" -name "node_modules" -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "package-lock.json" -type f -delete 2>/dev/null || true

    log_success "Deep clean completed"
}

# List running servers
list_servers() {
    log_section "Running Servers & Watchers"
    print_status_box

    # Additional details
    printf "${YELLOW}Process Details:${NC}\n"
    printf "${BLUE}-------------------------------------------------------------------------------${NC}\n"

    # live-server processes
    _live_pids=$(pgrep -f "live-server" 2>/dev/null || true)
    if [ -n "$_live_pids" ]; then
        printf "${CYAN}live-server Processes:${NC}\n"
        ps -p $(echo "$_live_pids" | tr '\n' ',') -o pid,args 2>/dev/null | tail -n +2 || true
        printf "\n"
    fi

    # Sass watchers
    _sass_pids=$(pgrep -f "sass.*--watch" 2>/dev/null || true)
    if [ -n "$_sass_pids" ]; then
        printf "${CYAN}Sass Watchers:${NC}\n"
        ps -p $(echo "$_sass_pids" | tr '\n' ',') -o pid,args 2>/dev/null | tail -n +2 || true
        printf "\n"
    fi

    # TypeScript watchers
    _tsc_pids=$(pgrep -f "tsc.*--watch" 2>/dev/null || true)
    if [ -n "$_tsc_pids" ]; then
        printf "${CYAN}TypeScript Watchers:${NC}\n"
        ps -p $(echo "$_tsc_pids" | tr '\n' ',') -o pid,args 2>/dev/null | tail -n +2 || true
        printf "\n"
    fi

    # Tmux sessions
    if command -v tmux >/dev/null 2>&1; then
        _tmux_sessions=$(tmux list-sessions 2>/dev/null | grep "^build-" || true)
        if [ -n "$_tmux_sessions" ]; then
            printf "${CYAN}Tmux Sessions:${NC}\n"
            printf "%s\n" "$_tmux_sessions"
            printf "\n"
        fi
    fi

    printf "${BLUE}-------------------------------------------------------------------------------${NC}\n"
    printf "${YELLOW}To stop all:${NC} ./1.ops/build_main.sh kill\n"
    printf "\n"
}

# Start development servers
dev_all() {
    _verbose="${1:-false}"

    log_section "Starting All Development Servers"

    log_warning "This will start multiple development servers concurrently."
    printf "\n"

    # Use tmux if available
    if command -v tmux >/dev/null 2>&1; then
        log_info "Starting servers in tmux sessions..."

        tmux new-session -d -s build-root-sass "cd $PROJECT_ROOT/3.sass && npm install && npm run sass:watch" 2>/dev/null || true
        tmux new-session -d -s build-root-ts "cd $PROJECT_ROOT/4.ts && npm install && npm run ts:watch" 2>/dev/null || true
        tmux new-session -d -s build-linktree "cd $PROJECT_ROOT/linktree/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-cv-web "cd $PROJECT_ROOT/cv_web/3.sass && npm install && npm run sass:watch" 2>/dev/null || true
        tmux new-session -d -s build-myfeed "cd $PROJECT_ROOT/myfeed/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-myprofile "cd $PROJECT_ROOT/myprofile/1.1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-nexus "cd $PROJECT_ROOT/nexus/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-cloud "cd $PROJECT_ROOT/cloud/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-feed "cd $PROJECT_ROOT/feed_yourself/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-others "cd $PROJECT_ROOT/others/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-health "cd $PROJECT_ROOT/health_tracker/1.ops && sh build.sh dev" 2>/dev/null || true
        tmux new-session -d -s build-market "cd $PROJECT_ROOT/market_watch/1.ops && sh build.sh dev" 2>/dev/null || true

        log_success "All servers started in tmux sessions!"
        printf "\n"
        printf "${GREEN}============================================================${NC}\n"
        printf "${CYAN}  Development Servers Running (live-server):${NC}\n"
        printf "${GREEN}============================================================${NC}\n"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Root" "$URL_ROOT"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Linktree" "$URL_LINKTREE"
        printf "  ${CYAN}%-15s${NC}  %s\n" "CV Web" "$URL_CV_WEB"
        printf "  ${CYAN}%-15s${NC}  %s\n" "MyFeed" "$URL_MYFEED"
        printf "  ${CYAN}%-15s${NC}  %s\n" "MyProfile" "$URL_MYPROFILE"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Nexus" "$URL_NEXUS"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Cloud" "$URL_CLOUD"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Feed Yourself" "$URL_FEED"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Others" "$URL_OTHERS"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Health Tracker" "$URL_HEALTH"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Market Watch" "$URL_MARKET"
        printf "${GREEN}============================================================${NC}\n"
        printf "\n"
        log_info "Tmux Sessions: build-root-sass, build-root-ts, build-linktree, etc."
        log_info "To view logs: tmux attach -t <session-name>"
        log_info "To kill all servers: ./1.ops/build_main.sh kill"
        printf "\n"
        log_success "Returning to prompt. Dev servers are running in background."

    else
        log_warning "tmux not found. Starting servers in background..."
        log_info "Install tmux for better session management: sudo apt-get install tmux"
        printf "\n"

        # Create log directory
        mkdir -p "$PROJECT_ROOT/1.ops/logs"

        # Start servers in background
        log_info "Starting root Sass..."
        (cd "$PROJECT_ROOT/3.sass" && nohup npm run sass:watch > "$PROJECT_ROOT/1.ops/logs/sass-dev.log" 2>&1 &)

        log_info "Starting root TypeScript..."
        (cd "$PROJECT_ROOT/4.ts" && nohup npm run ts:watch > "$PROJECT_ROOT/1.ops/logs/ts-dev.log" 2>&1 &)

        log_info "Starting linktree..."
        nohup sh "$PROJECT_ROOT/linktree/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/linktree-dev.log" 2>&1 &

        log_info "Starting cv_web Sass..."
        (cd "$PROJECT_ROOT/cv_web/3.sass" && nohup npm run sass:watch > "$PROJECT_ROOT/1.ops/logs/cv-web-dev.log" 2>&1 &)

        log_info "Starting myfeed..."
        nohup sh "$PROJECT_ROOT/myfeed/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/myfeed-dev.log" 2>&1 &

        log_info "Starting myprofile..."
        nohup sh "$PROJECT_ROOT/myprofile/1.1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/myprofile-dev.log" 2>&1 &

        log_info "Starting nexus..."
        nohup sh "$PROJECT_ROOT/nexus/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/nexus-dev.log" 2>&1 &

        log_info "Starting cloud..."
        nohup sh "$PROJECT_ROOT/cloud/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/cloud-dev.log" 2>&1 &

        log_info "Starting feed_yourself..."
        nohup sh "$PROJECT_ROOT/feed_yourself/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/feed-dev.log" 2>&1 &

        log_info "Starting others..."
        nohup sh "$PROJECT_ROOT/others/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/others-dev.log" 2>&1 &

        log_info "Starting health_tracker..."
        nohup sh "$PROJECT_ROOT/health_tracker/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/health-dev.log" 2>&1 &

        log_info "Starting market_watch..."
        nohup sh "$PROJECT_ROOT/market_watch/1.ops/build.sh" dev > "$PROJECT_ROOT/1.ops/logs/market-dev.log" 2>&1 &

        sleep 3  # Give servers time to start

        log_success "All servers started in background!"
        printf "\n"
        printf "${GREEN}============================================================${NC}\n"
        printf "${CYAN}  Development Servers Running (live-server):${NC}\n"
        printf "${GREEN}============================================================${NC}\n"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Root" "$URL_ROOT"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Linktree" "$URL_LINKTREE"
        printf "  ${CYAN}%-15s${NC}  %s\n" "CV Web" "$URL_CV_WEB"
        printf "  ${CYAN}%-15s${NC}  %s\n" "MyFeed" "$URL_MYFEED"
        printf "  ${CYAN}%-15s${NC}  %s\n" "MyProfile" "$URL_MYPROFILE"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Nexus" "$URL_NEXUS"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Cloud" "$URL_CLOUD"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Feed Yourself" "$URL_FEED"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Others" "$URL_OTHERS"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Health Tracker" "$URL_HEALTH"
        printf "  ${CYAN}%-15s${NC}  %s\n" "Market Watch" "$URL_MARKET"
        printf "${GREEN}============================================================${NC}\n"
        printf "\n"
        log_info "Logs: $PROJECT_ROOT/1.ops/logs/<project>-dev.log"
        log_info "View logs: tail -f $PROJECT_ROOT/1.ops/logs/<project>-dev.log"
        log_info "Kill servers: ./1.ops/build_main.sh kill"
        printf "\n"
        log_success "Returning to prompt. Dev servers are running in background."
    fi
}

# Start single dev server and show URL
dev_single() {
    _project="$1"
    _url="$2"
    _type="${3:-server}"

    log_section "Starting: $_project"

    case "$_project" in
        root)
            log_info "Starting root Sass + TypeScript watch..."
            (cd "$PROJECT_ROOT/3.sass" && npm install && npm run sass:watch) &
            (cd "$PROJECT_ROOT/4.ts" && npm install && npm run ts:watch) &
            print_server_started "Root Sass + TypeScript" "$_url" "watcher"
            wait
            ;;
        linktree)
            execute_build "linktree" "dev" &
            sleep 2
            print_server_started "Linktree" "$_url"
            wait
            ;;
        cv-web)
            log_info "Starting cv_web Sass watch..."
            (cd "$PROJECT_ROOT/cv_web/3.sass" && npm install && npm run sass:watch) &
            print_server_started "CV Web Sass" "$_url" "watcher"
            wait
            ;;
        myfeed)
            execute_build "myfeed" "dev" &
            sleep 2
            print_server_started "MyFeed" "$_url"
            wait
            ;;
        myprofile)
            execute_build "myprofile" "dev" &
            sleep 2
            print_server_started "MyProfile" "$_url"
            wait
            ;;
        nexus)
            execute_build "nexus" "dev" &
            sleep 2
            print_server_started "Nexus" "$_url"
            wait
            ;;
        cloud)
            execute_build "cloud" "dev"
            ;;
        feed)
            execute_build "feed_yourself" "dev" &
            sleep 2
            print_server_started "Feed Yourself" "$_url"
            wait
            ;;
        others)
            execute_build "others" "dev" &
            sleep 2
            print_server_started "Others" "$_url"
            wait
            ;;
        health)
            execute_build "health_tracker" "dev" &
            sleep 2
            print_server_started "Health Tracker" "$_url"
            wait
            ;;
        market)
            execute_build "market_watch" "dev"
            ;;
    esac
}

# Kill all running dev servers
kill_servers() {
    log_section "Killing All Development Servers"

    _killed=0

    # Kill tmux sessions if they exist
    if command -v tmux >/dev/null 2>&1; then
        for session in build-root-sass build-root-ts build-linktree build-cv-web build-myfeed build-myprofile build-nexus build-cloud build-feed build-others build-health build-market; do
            if tmux has-session -t "$session" 2>/dev/null; then
                log_info "Killing tmux session: $session"
                tmux kill-session -t "$session" 2>/dev/null && _killed=$((_killed + 1)) || true
            fi
        done
    fi

    # Kill live-server processes
    _live_pids=$(pgrep -f "live-server" 2>/dev/null || true)
    if [ -n "$_live_pids" ]; then
        log_info "Killing live-server processes..."
        echo "$_live_pids" | xargs kill -15 2>/dev/null || true
        _killed=$((_killed + $(echo "$_live_pids" | wc -w)))
        sleep 1
        _live_pids=$(pgrep -f "live-server" 2>/dev/null || true)
        if [ -n "$_live_pids" ]; then
            echo "$_live_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi

    # Kill concurrently processes
    _concurrently_pids=$(pgrep -f "node.*concurrently" 2>/dev/null || true)
    if [ -n "$_concurrently_pids" ]; then
        log_info "Killing concurrently processes..."
        echo "$_concurrently_pids" | xargs kill -15 2>/dev/null || true
        _killed=$((_killed + $(echo "$_concurrently_pids" | wc -w)))
        sleep 1
        _concurrently_pids=$(pgrep -f "node.*concurrently" 2>/dev/null || true)
        if [ -n "$_concurrently_pids" ]; then
            echo "$_concurrently_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi

    # Kill npm run processes
    _npm_pids=$(pgrep -f "npm run" 2>/dev/null || true)
    if [ -n "$_npm_pids" ]; then
        log_info "Killing npm processes..."
        echo "$_npm_pids" | xargs kill -15 2>/dev/null || true
        _killed=$((_killed + $(echo "$_npm_pids" | wc -w)))
        sleep 1
        _npm_pids=$(pgrep -f "npm run" 2>/dev/null || true)
        if [ -n "$_npm_pids" ]; then
            echo "$_npm_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi

    # Kill Sass watch processes
    _sass_pids=$(pgrep -f "sass.*--watch" 2>/dev/null || true)
    if [ -n "$_sass_pids" ]; then
        log_info "Killing Sass watch processes..."
        echo "$_sass_pids" | xargs kill -15 2>/dev/null || true
        _killed=$((_killed + $(echo "$_sass_pids" | wc -w)))
        sleep 1
        _sass_pids=$(pgrep -f "sass.*--watch" 2>/dev/null || true)
        if [ -n "$_sass_pids" ]; then
            echo "$_sass_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi

    # Kill TypeScript watch processes
    _tsc_pids=$(pgrep -f "tsc.*--watch" 2>/dev/null || true)
    if [ -n "$_tsc_pids" ]; then
        log_info "Killing TypeScript watch processes..."
        echo "$_tsc_pids" | xargs kill -15 2>/dev/null || true
        _killed=$((_killed + $(echo "$_tsc_pids" | wc -w)))
        sleep 1
        _tsc_pids=$(pgrep -f "tsc.*--watch" 2>/dev/null || true)
        if [ -n "$_tsc_pids" ]; then
            echo "$_tsc_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi

    if [ "$_killed" -gt 0 ]; then
        log_success "Killed $_killed process(es)"
    else
        log_warning "No running dev servers found"
    fi
}

# Run tests
run_tests() {
    log_section "Running Tests"

    _failed=0

    execute_build "myfeed" "test" || _failed=$((_failed + 1))
    execute_build "myprofile" "test" || _failed=$((_failed + 1))

    if [ "$_failed" -eq 0 ]; then
        log_success "All tests passed!"
        return 0
    else
        log_error "$_failed test suite(s) failed"
        return 1
    fi
}

# TUI Menu System
tui_menu() {
    # Menu items: "label|command"
    _menu_items="
BUILD ALL|build
─────────────────────────────|
Root (Sass + TS)|build-root
Linktree|build-linktree
CV Web|build-cv-web
MyFeed|build-myfeed
MyProfile|build-myprofile
Nexus|build-nexus
Cloud|build-cloud
Feed Yourself|build-feed
Others|build-others
Health Tracker|build-health
Market Watch|build-market
─────────────────────────────|
DEV ALL|dev
─────────────────────────────|
Root :8000|dev-root
Linktree :8001|dev-linktree
CV Web :8002|dev-cv-web
MyFeed :8003|dev-myfeed
MyProfile :8004|dev-myprofile
Nexus :8005|dev-nexus
Cloud :8006|dev-cloud
Feed Yourself :8007|dev-feed
Others :8008|dev-others
Health Tracker :8009|dev-health
Market Watch :8010|dev-market
─────────────────────────────|
List Servers|list
Kill Servers|kill
Clean Builds|clean
Clean All|clean-all
Run Tests|test
─────────────────────────────|
Exit|quit
"

    # Convert to arrays
    _idx=0
    _labels=""
    _commands=""
    _separators=""

    echo "$_menu_items" | while IFS='|' read -r _label _cmd; do
        [ -z "$_label" ] && continue
        if [ -z "$_cmd" ]; then
            _separators="$_separators $_idx"
        fi
        _idx=$((_idx + 1))
    done

    # Current selection
    _selected=0
    _total=0

    # Count items
    _total=$(echo "$_menu_items" | grep -c '|' 2>/dev/null || echo "0")

    # Hide cursor
    printf "\033[?25l"

    # Trap to restore cursor on exit
    trap 'printf "\033[?25h"; clear' EXIT INT TERM

    while true; do
        clear

        # Header
        printf "${CYAN}"
        printf "╔══════════════════════════════════════════════════════════╗\n"
        printf "║            MAIN BUILD ORCHESTRATOR - TUI                 ║\n"
        printf "╚══════════════════════════════════════════════════════════╝${NC}\n"
        printf "\n"

        # Server status (compact)
        get_running_servers
        if [ "$RUNNING_COUNT" -gt 0 ]; then
            printf "${GREEN}● ${RUNNING_COUNT} server(s) running${NC}\n"
        else
            printf "${YELLOW}○ No servers running${NC}\n"
        fi
        printf "\n"

        # Menu
        printf "${BLUE}┌──────────────────────────────────────────────────────────┐${NC}\n"
        printf "${BLUE}│${NC}  ${YELLOW}BUILD${NC}                                                    ${BLUE}│${NC}\n"
        printf "${BLUE}├──────────────────────────────────────────────────────────┤${NC}\n"

        _idx=0
        _section="build"
        echo "$_menu_items" | while IFS='|' read -r _label _cmd; do
            [ -z "$_label" ] && continue

            # Section headers
            if echo "$_label" | grep -q "^─"; then
                if [ "$_section" = "build" ] && [ $_idx -gt 12 ]; then
                    printf "${BLUE}├──────────────────────────────────────────────────────────┤${NC}\n"
                    printf "${BLUE}│${NC}  ${YELLOW}DEV SERVER${NC}                                               ${BLUE}│${NC}\n"
                    printf "${BLUE}├──────────────────────────────────────────────────────────┤${NC}\n"
                    _section="dev"
                elif [ "$_section" = "dev" ] && [ $_idx -gt 25 ]; then
                    printf "${BLUE}├──────────────────────────────────────────────────────────┤${NC}\n"
                    printf "${BLUE}│${NC}  ${YELLOW}UTILITY${NC}                                                  ${BLUE}│${NC}\n"
                    printf "${BLUE}├──────────────────────────────────────────────────────────┤${NC}\n"
                    _section="util"
                fi
                _idx=$((_idx + 1))
                continue
            fi

            # Menu item
            if [ $_idx -eq $_selected ]; then
                printf "${BLUE}│${NC} ${GREEN}▶ %-54s${NC} ${BLUE}│${NC}\n" "$_label"
            else
                printf "${BLUE}│${NC}   %-54s ${BLUE}│${NC}\n" "$_label"
            fi

            _idx=$((_idx + 1))
        done

        printf "${BLUE}└──────────────────────────────────────────────────────────┘${NC}\n"
        printf "\n"
        printf "${CYAN}↑/↓${NC} Navigate  ${CYAN}Enter${NC} Select  ${CYAN}q${NC} Quit  ${CYAN}h${NC} Help\n"

        # Read key
        _key=""
        IFS= read -r -s -n 1 _key

        case "$_key" in
            q|Q)
                printf "\033[?25h"
                clear
                exit 0
                ;;
            h|H)
                printf "\033[?25h"
                clear
                print_usage
                printf "\nPress any key to return to menu..."
                read -r -s -n 1
                ;;
            "")  # Enter
                # Get selected command
                _idx=0
                _selected_cmd=""
                echo "$_menu_items" | while IFS='|' read -r _label _cmd; do
                    [ -z "$_label" ] && continue
                    if [ $_idx -eq $_selected ]; then
                        echo "$_cmd"
                        break
                    fi
                    _idx=$((_idx + 1))
                done > /tmp/tui_cmd.tmp
                _selected_cmd=$(cat /tmp/tui_cmd.tmp 2>/dev/null)
                rm -f /tmp/tui_cmd.tmp

                if [ -n "$_selected_cmd" ] && [ "$_selected_cmd" != "quit" ]; then
                    printf "\033[?25h"
                    clear
                    # Execute command
                    main "$_selected_cmd"
                    printf "\n${CYAN}Press any key to return to menu...${NC}"
                    read -r -s -n 1
                elif [ "$_selected_cmd" = "quit" ]; then
                    printf "\033[?25h"
                    clear
                    exit 0
                fi
                ;;
            $'\x1b')  # Escape sequence (arrow keys)
                read -r -s -n 2 _seq
                case "$_seq" in
                    '[A')  # Up
                        _selected=$((_selected - 1))
                        [ $_selected -lt 0 ] && _selected=$((_total - 1))
                        # Skip separators
                        _check_label=$(echo "$_menu_items" | sed -n "$((_selected + 1))p" | cut -d'|' -f1)
                        while echo "$_check_label" | grep -q "^─"; do
                            _selected=$((_selected - 1))
                            [ $_selected -lt 0 ] && _selected=$((_total - 1))
                            _check_label=$(echo "$_menu_items" | sed -n "$((_selected + 1))p" | cut -d'|' -f1)
                        done
                        ;;
                    '[B')  # Down
                        _selected=$((_selected + 1))
                        [ $_selected -ge $_total ] && _selected=0
                        # Skip separators
                        _check_label=$(echo "$_menu_items" | sed -n "$((_selected + 1))p" | cut -d'|' -f1)
                        while echo "$_check_label" | grep -q "^─"; do
                            _selected=$((_selected + 1))
                            [ $_selected -ge $_total ] && _selected=0
                            _check_label=$(echo "$_menu_items" | sed -n "$((_selected + 1))p" | cut -d'|' -f1)
                        done
                        ;;
                esac
                ;;
        esac
    done
}

# Simple TUI (POSIX-compliant)
tui_simple() {
    while true; do
        clear
        print_banner

        get_running_servers
        if [ "$RUNNING_COUNT" -gt 0 ]; then
            printf "${GREEN}● ${RUNNING_COUNT} server(s) running${NC}\n\n"
        else
            printf "${YELLOW}○ No servers running${NC}\n\n"
        fi

        printf "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}\n"
        printf "${BLUE}│${NC}  ${YELLOW}BUILD${NC}                                                       ${BLUE}│${NC}\n"
        printf "${BLUE}├─────────────────────────────────────────────────────────────┤${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}1)${NC}  build           ${CYAN}Build all projects${NC}                    ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}2)${NC}  build-root      ${CYAN}Root Sass + TypeScript${NC}                ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}3)${NC}  build-cloud     ${CYAN}Cloud Dashboard${NC}                       ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}4)${NC}  build-market    ${CYAN}Market Watch${NC}                          ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}5)${NC}  build-health    ${CYAN}Health Tracker${NC}                        ${BLUE}│${NC}\n"
        printf "${BLUE}├─────────────────────────────────────────────────────────────┤${NC}\n"
        printf "${BLUE}│${NC}  ${YELLOW}DEV SERVER${NC}                                                  ${BLUE}│${NC}\n"
        printf "${BLUE}├─────────────────────────────────────────────────────────────┤${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}10)${NC} dev             ${CYAN}Start all dev servers${NC}                 ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}11)${NC} dev-root        ${CYAN}Root :8000${NC}                            ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}12)${NC} dev-linktree    ${CYAN}Linktree :8001${NC}                        ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}13)${NC} dev-cv-web      ${CYAN}CV Web :8002${NC}                          ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}14)${NC} dev-myfeed      ${CYAN}MyFeed :8003${NC}                          ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}15)${NC} dev-myprofile   ${CYAN}MyProfile :8004${NC}                       ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}16)${NC} dev-nexus       ${CYAN}Nexus :8005${NC}                           ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}17)${NC} dev-cloud       ${CYAN}Cloud :8006${NC}                           ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}18)${NC} dev-feed        ${CYAN}Feed Yourself :8007${NC}                   ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}19)${NC} dev-others      ${CYAN}Others :8008${NC}                          ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}20)${NC} dev-health      ${CYAN}Health Tracker :8009${NC}                  ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}21)${NC} dev-market      ${CYAN}Market Watch :8010${NC}                    ${BLUE}│${NC}\n"
        printf "${BLUE}├─────────────────────────────────────────────────────────────┤${NC}\n"
        printf "${BLUE}│${NC}  ${YELLOW}UTILITY${NC}                                                     ${BLUE}│${NC}\n"
        printf "${BLUE}├─────────────────────────────────────────────────────────────┤${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}30)${NC} list            ${CYAN}List running servers${NC}                  ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}31)${NC} kill            ${CYAN}Kill all servers${NC}                      ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}32)${NC} clean           ${CYAN}Clean build artifacts${NC}                 ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}33)${NC} test            ${CYAN}Run tests${NC}                             ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}h)${NC}  help            ${CYAN}Show help${NC}                             ${BLUE}│${NC}\n"
        printf "${BLUE}│${NC}  ${GREEN}q)${NC}  quit            ${CYAN}Exit TUI${NC}                              ${BLUE}│${NC}\n"
        printf "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}\n"
        printf "\n"
        printf "${GREEN}Enter choice: ${NC}"

        read -r _choice

        case "$_choice" in
            1|build)           _cmd="build" ;;
            2|build-root)      _cmd="build-root" ;;
            3|build-cloud)     _cmd="build-cloud" ;;
            4|build-market)    _cmd="build-market" ;;
            5|build-health)    _cmd="build-health" ;;
            6|build-linktree)  _cmd="build-linktree" ;;
            7|build-cv-web)    _cmd="build-cv-web" ;;
            8|build-myfeed)    _cmd="build-myfeed" ;;
            9|build-myprofile) _cmd="build-myprofile" ;;
            10|dev)            _cmd="dev" ;;
            11|dev-root)       _cmd="dev-root" ;;
            12|dev-linktree)   _cmd="dev-linktree" ;;
            13|dev-cv-web)     _cmd="dev-cv-web" ;;
            14|dev-myfeed)     _cmd="dev-myfeed" ;;
            15|dev-myprofile)  _cmd="dev-myprofile" ;;
            16|dev-nexus)      _cmd="dev-nexus" ;;
            17|dev-cloud)      _cmd="dev-cloud" ;;
            18|dev-feed)       _cmd="dev-feed" ;;
            19|dev-others)     _cmd="dev-others" ;;
            20|dev-health)     _cmd="dev-health" ;;
            21|dev-market)     _cmd="dev-market" ;;
            30|list)           _cmd="list" ;;
            31|kill)           _cmd="kill" ;;
            32|clean)          _cmd="clean" ;;
            33|test)           _cmd="test" ;;
            h|help)            _cmd="help" ;;
            q|quit|Q|exit)
                clear
                printf "${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            "")
                continue
                ;;
            *)
                printf "${RED}Invalid option: %s${NC}\n" "$_choice"
                sleep 1
                continue
                ;;
        esac

        clear
        main "$_cmd"
        printf "\n${CYAN}Press any key to continue...${NC}"
        # Read single key (POSIX-compatible)
        _old_tty=$(stty -g 2>/dev/null)
        stty -icanon min 1 time 0 2>/dev/null
        dd bs=1 count=1 >/dev/null 2>&1
        stty "$_old_tty" 2>/dev/null
        printf "\n"
    done
}

# Main execution
main() {
    # Show TUI if no argument provided
    if [ $# -eq 0 ]; then
        tui_simple
        exit 0
    fi

    # Show help for -h/--help
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        print_banner
        print_usage
        exit 0
    fi

    _action="$1"
    _force="false"
    _verbose="false"

    # Parse options
    shift 2>/dev/null || true
    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f)
                _force="true"
                shift
                ;;
            --verbose|-v)
                _verbose="true"
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    print_banner

    case "$_action" in
        build)
            build_all "$_force"
            ;;
        build-root)
            log_section "Building Root Sass"
            (cd "$PROJECT_ROOT/3.sass" && npm install && npm run sass:build)
            log_section "Building Root TypeScript"
            (cd "$PROJECT_ROOT/4.ts" && npm install && npm run ts:build)
            log_success "Root build completed"
            ;;
        build-linktree)
            execute_build "linktree" "build"
            ;;
        build-cv-web)
            execute_build "cv_web" "build"
            ;;
        build-myfeed)
            execute_build "myfeed" "build"
            ;;
        build-myprofile)
            execute_build "myprofile" "build"
            ;;
        build-nexus)
            execute_build "nexus" "build"
            ;;
        build-cloud)
            execute_build "cloud" "build"
            ;;
        build-feed)
            execute_build "feed_yourself" "build"
            ;;
        build-others)
            execute_build "others" "build"
            ;;
        build-health)
            execute_build "health_tracker" "build"
            ;;
        build-market)
            execute_build "market_watch" "build"
            ;;
        dev)
            dev_all "$_verbose"
            ;;
        dev-root)
            dev_single "root" "$URL_ROOT" "watcher"
            ;;
        dev-linktree)
            dev_single "linktree" "$URL_LINKTREE"
            ;;
        dev-cv-web)
            dev_single "cv-web" "$URL_CV_WEB" "watcher"
            ;;
        dev-myfeed)
            dev_single "myfeed" "$URL_MYFEED"
            ;;
        dev-myprofile)
            dev_single "myprofile" "$URL_MYPROFILE"
            ;;
        dev-nexus)
            dev_single "nexus" "$URL_NEXUS"
            ;;
        dev-cloud)
            dev_single "cloud" "$URL_CLOUD"
            ;;
        dev-feed)
            dev_single "feed" "$URL_FEED"
            ;;
        dev-others)
            dev_single "others" "$URL_OTHERS"
            ;;
        dev-health)
            dev_single "health" "$URL_HEALTH"
            ;;
        dev-market)
            dev_single "market" "$URL_MARKET"
            ;;
        list)
            list_servers
            ;;
        kill)
            kill_servers
            ;;
        clean)
            clean_all_builds
            ;;
        clean-all)
            clean_deep
            ;;
        test)
            run_tests
            ;;
        help)
            print_usage
            ;;
        *)
            log_error "Unknown command: $_action"
            printf "\n"
            printf "${YELLOW}Launching TUI menu...${NC}\n"
            sleep 1
            tui_simple
            ;;
    esac
}

# Run main function
main "$@"
