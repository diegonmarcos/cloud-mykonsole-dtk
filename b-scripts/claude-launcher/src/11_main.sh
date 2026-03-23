# ---------------------------------------------------------------------------
# Main — CLI parser and dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
    -h|--help)
        cmd_help
        ;;
    -V|--version)
        printf 'claude-launcher %s\n' "$CLAUDE_LAUNCHER_VERSION"
        ;;
    status)
        cmd_status
        ;;
    -s|--sandbox)
        shift
        run_sandbox "$@"
        ;;
    -m|--mirror)
        shift
        run_mirror "$@"
        ;;
    docker)
        shift
        run_container docker "$@"
        ;;
    podman)
        shift
        run_container podman "$@"
        ;;
    browser)
        shift
        run_browser "$@"
        ;;
    --)
        shift
        run_native "$@"
        ;;
    *)
        run_native "$@"
        ;;
esac
