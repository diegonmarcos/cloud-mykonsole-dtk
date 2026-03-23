# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

cmd_help() {
    cat <<HELP
claude-launcher v${CLAUDE_LAUNCHER_VERSION} — Unified Claude Code launcher

USAGE
  claude.sh [MODE] [OPTIONS] [-- claude-args...]

MODES
  (default)              Native tiered execution
  -s, --sandbox          Bwrap isolated sandbox (restricted mounts)
  -m, --mirror           Full home access (no isolation)
  docker [args]          Run in Docker container
  podman [args]          Run in Podman container
  browser <URL>          Open URL in Carbonyl TTY browser

COMMANDS
  status                 Show versions, paths, drift detection
  -h, --help             This help message
  -V, --version          Show version

NATIVE EXECUTION TIERS (in order)
  1. Native binary       ~/.npm-global/bin/claude, ~/.nix-profile/bin/claude, PATH
  2. Dependency solver   npm install -g (user → sudo → prompt)
  3. npx                 npx --yes @anthropic-ai/claude-code
  4. nix-shell           nix-shell -p nodejs --run "npx ..."

SANDBOX MODE (--sandbox)
  Uses bubblewrap (bwrap) to isolate Claude with:
    Read-only:   /nix, /usr, /etc/ssl, ~/.ssh, ~/.gitconfig
    Read-write:  ~/.claude, ~/.config, ~/.npm-global, ~/mnt_git
    Isolated:    PID namespace, per-session /tmp
    Env:         CLAUDE_SANDBOXED=1

CONTAINER MODE (docker / podman)
  Runs in node:20-slim with mounts:
    ~/.claude      → /home/node/.claude
    ~/.claude.json → /home/node/.claude.json (ro)
    cwd            → /workspace

BROWSER (Carbonyl)
  Terminal web browser for OAuth flows in headless/SSH sessions.
  Fallback: native → npx → docker/podman → nix-shell

EXAMPLES
  claude.sh                          Run normally (auto-detect best method)
  claude.sh --sandbox                Run in bwrap sandbox
  claude.sh --mirror                 Run with full access
  claude.sh docker                   Run in Docker
  claude.sh podman -- --version      Run in Podman, pass --version to claude
  claude.sh browser https://auth.example.com   Open auth page in terminal
  claude.sh status                   Show diagnostics

LOGGING
  All actions logged to ~/claude.log

HELP
}
