#!/bin/sh
# ai-cli — Unified AI Agent launcher (Goose + MCP)
# Source: ~/git/tools/b-scripts/ai-cli/
# POSIX-compliant
set -eu

VERSION="1.0.0"
CONFIG="${AI_CLI_CONFIG:-${HOME}/.config/goose/config.yaml}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_CLI_JSON="${SCRIPT_DIR}/ai-cli.json"

show_help() {
    printf '\033[1;36m'
    cat <<'BANNER'

    ╔═══╗ ╔══╗        ╔═══╗ ╦    ╔══╗
    ╠═══╣  ║   ═══    ║    ║     ║
    ║   ║ ╚══╝        ╚═══╝ ╩══╝ ╩
BANNER
    printf '\033[0m'
    GOOSE_VER=$(goose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo '?')
    printf '\033[1;37m    Unified AI Agent Launcher v%s\033[0m\n' "$VERSION"
    printf '\033[2m    goose v%s · block/goose · MCP-native\033[0m\n' "$GOOSE_VER"
    echo ""
    printf '\033[1;33m  ── Cloud Models (Anthropic API) ─────────────────────────────────────\033[0m\n'
    echo ""
    printf '\033[32m    (default)  \033[1;37mHaiku  4.5  \033[0m 200K ctx  \033[2m$0.80/$4.00   batch $0.40/$2.00\033[0m\n'
    printf '\033[32m    sonnet     \033[1;37mSonnet 4.6  \033[0m 200K ctx  \033[2m$3.00/$15.00  batch $1.50/$7.50\033[0m\n'
    printf '\033[32m    opus       \033[1;37mOpus   4.6  \033[0m   1M ctx  \033[2m$15.00/$75.00 batch $7.50/$37.50\033[0m\n'
    echo ""
    printf '\033[1;33m  ── Local Models (Ollama · oci-apps ARM) ────────────────────────────\033[0m\n'
    echo ""
    printf '\033[36m    local      \033[1;37mQwen   1.5B \033[0m   4K ctx  \033[2mfree · Q4_K_M · ~12s/msg\033[0m\n'
    echo ""
    printf '\033[1;33m  ── MCP Extensions ───────────────────────────────────────────────────\033[0m\n'
    echo ""
    printf '\033[2m'
    echo "    cloud-services         Mattermost, Mail, Dagu, GHA, Ollama, ntfy"
    echo "    cloud-infra            SSH, Docker, health checks, builds, deploys"
    echo "    cloud-cgc-mcp          Infra knowledge graph, octocode semantic search"
    echo "    google-workspace       Gmail, Calendar, Drive, Docs, Sheets"
    echo "    diego-personal-data    Vault, identity, finance (read-only)"
    printf '\033[0m'
    echo "    Enable: goose configure → Extensions"
    echo ""
    printf '\033[1;33m  ── Usage ────────────────────────────────────────────────────────────\033[0m\n'
    echo ""
    echo "    ai-cli                 Launch with Haiku 4.5 (default)"
    echo "    ai-cli sonnet          Launch with Sonnet 4.6"
    echo "    ai-cli opus            Launch with Opus 4.6"
    echo "    ai-cli local           Launch with local Qwen (free)"
    echo "    ai-cli -h              This help"
    echo ""
    printf '\033[2m    Config:  %s\033[0m\n' "$CONFIG"
    printf '\033[2m    Models:  %s\033[0m\n' "$AI_CLI_JSON"
    echo ""
}

case "${1:-}" in
    -h|--help|help|models)
        show_help
        exit 0
        ;;
    sonnet)
        shift
        GOOSE_PROVIDER=anthropic GOOSE_MODEL=claude-sonnet-4-6 exec goose "$@"
        ;;
    opus)
        shift
        GOOSE_PROVIDER=anthropic GOOSE_MODEL=claude-opus-4-6 exec goose "$@"
        ;;
    local|qwen)
        shift
        GOOSE_PROVIDER=ollama GOOSE_MODEL=qwen2.5-4k exec goose "$@"
        ;;
    haiku)
        shift
        GOOSE_PROVIDER=anthropic GOOSE_MODEL=claude-haiku-4-5-20251001 exec goose "$@"
        ;;
    "")
        GOOSE_PROVIDER=anthropic GOOSE_MODEL=claude-haiku-4-5-20251001 exec goose
        ;;
    *)
        GOOSE_PROVIDER=anthropic GOOSE_MODEL=claude-haiku-4-5-20251001 exec goose "$@"
        ;;
esac
