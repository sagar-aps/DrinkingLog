#!/usr/bin/env bash
# manager-round.sh — one ephemeral Manager maintenance round, for cron.
#
# The Manager is frontier-tier and runs INSIDE the target repo (unlike the
# orchestrator, which sits above it). Its charter is the repo-local skill at
# .claude/skills/manager/SKILL.md.
#
# NOTE: no floor guard here, deliberately. The Manager's job IS to approve, merge and
# deploy prod — the guard exists to stop the orchestrator doing those things.

set -euo pipefail

TARGET_REPO="${TARGET_REPO:-/home/sagar_ap/homelab/DrinkingLog}"
PROMPT_FILE="${MANAGER_ROUND_PROMPT:-$TARGET_REPO/scripts/manager-round.prompt.md}"

PATH="/home/sagar_ap/.npm-global/bin:/home/sagar_ap/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

STATE_DIR="$TARGET_REPO/.ralph"
LOG_DIR="$STATE_DIR/loop-logs"
LOG_FILE="$LOG_DIR/manager-$(date +%Y%m%d).log"
LOCK_FILE="$STATE_DIR/manager.lock"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

[[ -d "$TARGET_REPO" ]] || { echo "manager-round: TARGET_REPO not found" >&2; exit 1; }
mkdir -p "$LOG_DIR"
exec >>"$LOG_FILE" 2>&1

log "=== round start (pid $$)"

if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  log "another round holds $LOCK_FILE — exiting without running"
  exit 0
fi
cleanup() { rmdir "$LOCK_FILE" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

cd "$TARGET_REPO"

[[ -f "$PROMPT_FILE" ]] || { log "FATAL: prompt file missing: $PROMPT_FILE"; exit 1; }
log "prompt: $PROMPT_FILE ($(wc -c <"$PROMPT_FILE" | tr -d ' ') bytes)"

# Frontier tier by charter: the role is judgment-dense and a cheap model loses money
# here by approving a bad merge. Prompt on stdin, never interpolated.
STATUS=0
env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL \
    -u ANTHROPIC_DEFAULT_SONNET_MODEL -u ANTHROPIC_DEFAULT_HAIKU_MODEL -u ANTHROPIC_DEFAULT_OPUS_MODEL \
    claude -p --dangerously-skip-permissions <"$PROMPT_FILE" || STATUS=$?

[[ "$STATUS" -eq 0 ]] && log "=== round end: ok" || log "=== round end: exited $STATUS"
exit "$STATUS"
