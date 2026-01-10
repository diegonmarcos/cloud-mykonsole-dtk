#!/bin/sh

# restore-spec-symlinks.sh - Simple script to restore symlinks in 0.spec folders
# Looks for 0.spec folders and creates symlinks from specific files

C_RESET="\033[0m"; C_BOLD="\033[1m"; C_RED="\033[31m"; C_GREEN="\033[32m";
C_YELLOW="\033[33m"; C_CYAN="\033[36m";

_log() { printf "${C_CYAN}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$1"; }
_success() { printf "${C_GREEN}  ✓ %s${C_RESET}\n" "$1"; }
_error() { printf "${C_RED}  ✗ %s${C_RESET}\n" "$1"; }
_warn() { printf "${C_YELLOW}  ⚠ %s${C_RESET}\n" "$1"; }

# Default repo path
REPO_PATH="${1:-/home/diego/Documents/Git/front-Notes_md}"

# Files to look for in 0.spec folders
SPEC_FILES="index.md spec.md spec_ops.md readme.md README.md"

_log "Searching for 0.spec folders in: $REPO_PATH"

if [ ! -d "$REPO_PATH" ]; then
    _error "Directory not found: $REPO_PATH"
    exit 1
fi

# Find all 0.spec folders
find "$REPO_PATH" -type d -name "0.spec" | while read -r spec_dir; do
    _log "Processing: $spec_dir"

    # Check each specified file
    for filename in $SPEC_FILES; do
        filepath="$spec_dir/$filename"

        # Skip if file doesn't exist
        if [ ! -f "$filepath" ]; then
            continue
        fi

        # Skip if already a symlink
        if [ -L "$filepath" ]; then
            _warn "Already a symlink: $filename"
            continue
        fi

        # Read the first line as the target path
        target=$(head -n 1 "$filepath")

        # Skip if empty
        if [ -z "$target" ]; then
            _warn "Empty file: $filename"
            continue
        fi

        # Skip if file has multiple lines (it's actual content, not a symlink path)
        line_count=$(wc -l < "$filepath")
        if [ "$line_count" -gt 1 ]; then
            _warn "Multi-line content (not a symlink path): $filename"
            continue
        fi

        printf "  ${C_CYAN}Creating symlink:${C_RESET} $filename\n"
        printf "    ${C_YELLOW}Target:${C_RESET} $target\n"

        # Backup the original file
        cp "$filepath" "${filepath}.backup"

        # Remove the text file
        rm "$filepath"

        # Create the symlink
        if ln -s "$target" "$filepath" 2>/dev/null; then
            _success "Created: $filename -> $target"
            # Remove backup on success
            rm "${filepath}.backup"
        else
            _error "Failed to create symlink: $filename"
            # Restore from backup
            mv "${filepath}.backup" "$filepath"
        fi
    done

    echo ""
done

_log "Done!"
