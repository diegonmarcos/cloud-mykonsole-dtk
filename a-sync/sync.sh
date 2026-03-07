#!/bin/sh
# sync.sh — Unified sync engine for git and rclone
#
# Usage:
#   sync [git|rclone] [status|remote|ours] "msg" [files...]
#
# Defaults:
#   backend  = git
#   action   = status
#   files    = -A (all)
#
# Examples:
#   sync                              # git status (smart)
#   sync git status                   # same
#   sync git remote "feat: firewall"  # add all + commit + fetch + rebase -X theirs + push
#   sync git ours "fix: config"       # add all + commit + fetch + rebase -X ours + push
#   sync git remote "msg" src/ lib/   # add specific files only
#   sync rclone status                # rclone sync status
#
set -eu

# ── Colors ──────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  C_R='\033[0m'
  C_B='\033[1m'
  C_G='\033[32m'
  C_Y='\033[33m'
  C_E='\033[31m'
  C_C='\033[36m'
  C_D='\033[90m'
else
  C_R='' C_B='' C_G='' C_Y='' C_E='' C_C='' C_D=''
fi

log()  { printf "${C_C}[sync]${C_R} %s\n" "$*"; }
ok()   { printf "${C_G}[sync]${C_R} %s\n" "$*"; }
warn() { printf "${C_Y}[sync]${C_R} %s\n" "$*"; }
err()  { printf "${C_E}[sync]${C_R} %s\n" "$*" >&2; }
die()  { err "$@"; exit 1; }

# ═══════════════════════════════════════════════════════════════════════════
#  GIT ENGINE
# ═══════════════════════════════════════════════════════════════════════════

# ── Conflict handler ───────────────────────────────────────────────────────

git_handle_conflict() {
  strategy="$1"

  err "Rebase conflict detected"
  printf "\n${C_B}Conflicted files:${C_R}\n"
  git diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do
    printf "  ${C_E}%s${C_R}\n" "$f"
  done

  printf "\n"
  printf "  ${C_B}1)${C_R} solve   — open editor to resolve manually\n"
  printf "  ${C_B}2)${C_R} remote  — accept all remote versions\n"
  printf "  ${C_B}3)${C_R} ours    — keep all local versions\n"
  printf "  ${C_B}4)${C_R} abort   — cancel rebase, revert to pre-sync state\n"
  printf "\n"
  printf "Choice [1-4]: "

  read -r choice

  case "$choice" in
    1|solve)
      warn "Resolve conflicts, then run:"
      printf "  git add -A && git rebase --continue && git push\n"
      exit 0
      ;;
    2|remote)
      log "Taking remote version for all conflicts..."
      git diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do
        git checkout --theirs "$f"
        git add "$f"
      done
      GIT_EDITOR=true git rebase --continue 2>/dev/null || true
      ok "Conflicts resolved (remote wins)"
      ;;
    3|ours)
      log "Keeping local version for all conflicts..."
      git diff --name-only --diff-filter=U 2>/dev/null | while read -r f; do
        git checkout --ours "$f"
        git add "$f"
      done
      GIT_EDITOR=true git rebase --continue 2>/dev/null || true
      ok "Conflicts resolved (local wins)"
      ;;
    4|abort)
      git rebase --abort 2>/dev/null || true
      warn "Rebase aborted — back to pre-sync state"
      exit 1
      ;;
    *)
      git rebase --abort 2>/dev/null || true
      die "Invalid choice — rebase aborted"
      ;;
  esac
}

# ── git sync (remote|ours) ─────────────────────────────────────────────────

git_sync() {
  strategy="$1"  # "theirs" or "ours"

  [ -z "$MSG" ] && die "Commit message required: sync git $ACTION \"your message\""

  # 1. Stage files
  log "Staging files..."
  if [ -n "$FILES" ]; then
    # shellcheck disable=SC2086
    git add $FILES
  else
    git add -A
  fi

  # 2. Check if there's anything to commit
  if git diff --cached --quiet 2>/dev/null; then
    warn "Nothing new to commit"
  else
    # Show what we're committing
    printf "\n${C_B}Changes to commit:${C_R}\n"
    git diff --cached --stat
    printf "\n"

    # 3. Commit
    log "Committing: $MSG"
    git commit -m "$MSG"
  fi

  # 4. Fetch
  log "Fetching remote..."
  git fetch --quiet 2>/dev/null || true

  # 5. Check if rebase needed
  behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)

  if [ "$behind" -gt 0 ]; then
    log "Remote is ${behind} commit(s) ahead — rebasing (strategy: $strategy)..."

    if git rebase -X "$strategy" "@{upstream}" 2>/dev/null; then
      ok "Rebase clean"
    else
      git_handle_conflict "$strategy"
    fi
  else
    ok "Already up to date with remote"
  fi

  # 6. Push
  log "Pushing..."
  if git push 2>/dev/null; then
    ok "Pushed successfully"
  else
    die "Push failed — check remote permissions"
  fi

  printf "\n"
  ok "Done: $(git log --oneline -1)"
  printf "\n"
}

# ── git status (smart) ─────────────────────────────────────────────────────

git_smart_status() {
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  remote_branch=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")

  printf "\n${C_B}Branch:${C_R} %s" "$branch"
  if [ -n "$remote_branch" ]; then
    printf " ${C_D}→ %s${C_R}" "$remote_branch"
  fi
  printf "\n"

  # Fetch silently to compare
  git fetch --quiet 2>/dev/null || true

  if [ -n "$remote_branch" ]; then
    ahead=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null || echo 0)

    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      warn "Diverged: ${ahead} ahead, ${behind} behind"
      printf "  ${C_Y}Run:${C_R} sync git remote \"msg\"  ${C_D}(remote wins conflicts)${C_R}\n"
      printf "  ${C_Y} or:${C_R} sync git ours \"msg\"    ${C_D}(local wins conflicts)${C_R}\n"
    elif [ "$ahead" -gt 0 ]; then
      ok "Ahead by ${ahead} commit(s) — ready to push"
      printf "  ${C_G}Run:${C_R} sync git remote \"msg\"  ${C_D}(push)${C_R}\n"
    elif [ "$behind" -gt 0 ]; then
      warn "Behind by ${behind} commit(s)"
      printf "  ${C_Y}Run:${C_R} sync git remote \"msg\"  ${C_D}(pull + push)${C_R}\n"
    else
      ok "Up to date with remote"
    fi
  else
    warn "No upstream branch set"
  fi

  # Working tree status
  printf "\n"
  staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  unstaged=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

  if [ "$staged" -gt 0 ] || [ "$unstaged" -gt 0 ] || [ "$untracked" -gt 0 ]; then
    printf "${C_B}Working tree:${C_R}\n"
    [ "$staged" -gt 0 ]    && printf "  ${C_G}%s staged${C_R}\n" "$staged"
    [ "$unstaged" -gt 0 ]  && printf "  ${C_Y}%s modified${C_R}\n" "$unstaged"
    [ "$untracked" -gt 0 ] && printf "  ${C_E}%s untracked${C_R}\n" "$untracked"
    git status -s 2>/dev/null | head -20
    total=$((staged + unstaged + untracked))
    if [ "$total" -gt 20 ]; then
      printf "  ${C_D}... and %s more${C_R}\n" "$((total - 20))"
    fi
  else
    ok "Working tree clean"
  fi

  printf "\n"
}

# ── git dispatch ───────────────────────────────────────────────────────────

git_dispatch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not a git repository"

  case "$ACTION" in
    status) git_smart_status ;;
    remote) git_sync "theirs" ;;
    ours)   git_sync "ours" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════
#  RCLONE ENGINE (placeholder)
# ═══════════════════════════════════════════════════════════════════════════

rclone_dispatch() {
  case "$ACTION" in
    status)
      log "rclone sync status"
      if command -v rclone >/dev/null 2>&1; then
        rclone listremotes 2>/dev/null | while read -r remote; do
          printf "  ${C_C}%s${C_R}\n" "$remote"
        done
      else
        warn "rclone not installed"
      fi
      ;;
    remote)
      die "rclone remote sync not yet implemented"
      ;;
    ours)
      die "rclone ours sync not yet implemented"
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════
#  MAIN — Parse args + dispatch
# ═══════════════════════════════════════════════════════════════════════════

BACKEND="git"
ACTION="status"
MSG=""
FILES=""

# Help
case "${1:-}" in
  -h|--help|help)
    cat <<'HELP'
sync — Unified sync engine for git and rclone

Usage:
  sync [git|rclone] [status|remote|ours] "msg" [files...]

Defaults:  backend=git  action=status  files=all

Actions:
  status   Smart status: fetch + compare + show divergence (default)
  remote   Add + commit + rebase (remote wins conflicts) + push
  ours     Add + commit + rebase (local wins conflicts) + push

Examples:
  sync                                # git smart status
  sync git remote "feat: new thing"   # add all + commit + sync + push
  sync git ours "fix: config"         # same but local wins conflicts
  sync git remote "msg" src/ lib/     # only add specific files
  sync rclone status                  # show rclone remotes

Shortcuts:
  gacp "msg"                          # = sync git remote "msg"
HELP
    exit 0
    ;;
esac

# Detect backend
case "${1:-}" in
  git|rclone) BACKEND="$1"; shift ;;
esac

# Detect action
case "${1:-}" in
  status|remote|ours) ACTION="$1"; shift ;;
esac

# Detect message
if [ $# -gt 0 ]; then
  MSG="$1"; shift
fi

# Remaining args = files
FILES="$*"

# Dispatch
case "$BACKEND" in
  git)    git_dispatch ;;
  rclone) rclone_dispatch ;;
  *)      die "Unknown backend: $BACKEND" ;;
esac
