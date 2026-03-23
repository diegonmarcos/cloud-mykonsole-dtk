# ---------------------------------------------------------------------------
# Dependency resolver — install claude if not found
# ---------------------------------------------------------------------------

deps_solve() {
    log "deps_solve: claude not found natively, attempting install..."

    _ds_npm=$(find_bin npm) || _ds_npm=""
    _ds_node=$(find_bin node) || _ds_node=""

    if [ -z "$_ds_node" ]; then
        log "deps_solve: node not found anywhere"
        return 1
    fi

    _ds_major=$(node_major "$_ds_node") || _ds_major=0
    if [ "$_ds_major" -lt 18 ]; then
        log "deps_solve: node $("$_ds_node" --version) < 18.0.0 required"
        return 1
    fi

    if [ -z "$_ds_npm" ]; then
        log "deps_solve: npm not found anywhere"
        return 1
    fi

    log "deps_solve: found npm=$_ds_npm node=$_ds_node"
    ensure_npm_prefix

    # Try user-level install
    if "$_ds_npm" install -g "$PKG" >/dev/null 2>&1; then
        log "deps_solve: npm install -g succeeded"
        return 0
    fi

    # Try sudo
    log "deps_solve: npm install -g failed (permissions?), trying sudo..."
    if sudo -n "$_ds_npm" install -g "$PKG" >/dev/null 2>&1; then
        log "deps_solve: sudo npm install -g succeeded"
        return 0
    fi

    # Manual fallback
    printf '\n'
    log "deps_solve: automatic install failed"
    printf '  Run manually:  sudo %s install -g %s\n\n' "$_ds_npm" "$PKG"
    printf '  Continue with npx instead? [y/N] '
    read -r _ds_answer </dev/tty
    case "$_ds_answer" in
        [yY]|[yY][eE][sS]) return 1 ;;
        *) log "deps_solve: user declined npx fallback"; exit 1 ;;
    esac
}
