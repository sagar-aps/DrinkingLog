#!/usr/bin/env bash
# orchestrator-pass.sh — one ephemeral Orchestrator pass, for cron.
#
# Adapted from ralph-harness .agents/ralph/target-templates/unattended-loop.sh.example.
# Each tick spawns a fresh driver, runs ONE pass, and exits. No state is kept in the
# process: the Orchestrator charter reconstructs everything from GitHub.
#
# Deviations from the shipped template, both deliberate:
#   * PROMPT_FILE is NOT under .agents/ralph/. Creating that directory here would make
#     bin/ralph resolve its templates from this repo (which has none) instead of the
#     harness, breaking every ralph invocation. Same reason the identity wrapper lives
#     in scripts/ and the efficiency profile lives in ~/.config/ralph/.
#   * The floor guard is armed by the wrapper, not left to the driver to remember.

set -euo pipefail

TARGET_REPO="${TARGET_REPO:-/home/sagar_ap/homelab/DrinkingLog}"
RALPH_HOME="${RALPH_HOME:-/home/sagar_ap/homelab/ralph-harness}"
PROMPT_FILE="${RALPH_LOOP_PROMPT:-$TARGET_REPO/scripts/orchestrator-pass.prompt.md}"

PATH="/home/sagar_ap/.npm-global/bin:/home/sagar_ap/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

STATE_DIR="$TARGET_REPO/.ralph"
LOG_DIR="$STATE_DIR/loop-logs"
PLAN_DIR="$STATE_DIR/plans"
LOG_FILE="$LOG_DIR/orchestrator-$(date +%Y%m%d).log"
LOCK_FILE="$STATE_DIR/orchestrator.lock"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

[[ -d "$TARGET_REPO" ]] || { echo "orchestrator-pass: TARGET_REPO not found: $TARGET_REPO" >&2; exit 1; }
[[ -d "$RALPH_HOME/.agents/ralph" ]] || { echo "orchestrator-pass: RALPH_HOME has no .agents/ralph: $RALPH_HOME" >&2; exit 1; }

mkdir -p "$LOG_DIR" "$PLAN_DIR"
exec >>"$LOG_FILE" 2>&1

log "=== pass start (pid $$)"

# A pass can outrun the 60-minute cadence. mkdir is the atomic test-and-set.
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  log "another pass holds $LOCK_FILE — exiting without running"
  exit 0
fi
cleanup() { rmdir "$LOCK_FILE" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

cd "$TARGET_REPO"

# `set -a` matters: config.local.sh uses `: "${VAR:=x}"`, which sets without exporting,
# so an unexported backend definition is invisible to the `ralph` child process.
set -a
# shellcheck source=/dev/null
source "$RALPH_HOME/.agents/ralph/agents.sh"
# shellcheck source=/dev/null
. "$RALPH_HOME/.agents/ralph/config.sh"
[[ -f "$RALPH_HOME/.agents/ralph/config.local.sh" ]] && . "$RALPH_HOME/.agents/ralph/config.local.sh"
set +a

# Identity: resolve once and export, so the driver's own `gh` calls and
# `ralph integrate --pr` file the PR as the same App.
# shellcheck source=/dev/null
. "$RALPH_HOME/.agents/ralph/resolve-identity.sh"
if [[ "${IDENTITY_STATUS:-}" == "resolved" && -n "${RESOLVED_WRAPPER:-}" ]]; then
  export RALPH_IDENTITY_WRAPPER="$RESOLVED_WRAPPER"
  log "identity: resolved via ${IDENTITY_SOURCE:-?} -> $RALPH_IDENTITY_WRAPPER"
else
  log "identity: ${IDENTITY_STATUS:-unknown} (${IDENTITY_SOURCE:-?}) — PRs will be filed by ambient gh"
fi

# Mechanical floor. Armed here rather than trusting the driver to source it: it is a
# backstop for exactly the case where the model drifts from its charter.
#
# RALPH_DEFAULT_BRANCH is pinned deliberately. floor-guard.sh otherwise autodetects it
# with `git symbolic-ref refs/remotes/origin/HEAD | sed …`, and under this script's
# `set -o pipefail` that pipeline returns git's 128 whenever origin/HEAD is absent —
# which kills the whole pass at exit 128, before a single log line about it. Pinning
# skips the detection block entirely. Filed upstream as ralph-harness#84.
export RALPH_DEFAULT_BRANCH="${RALPH_DEFAULT_BRANCH:-main}"
# shellcheck source=/dev/null
. "$RALPH_HOME/.agents/ralph/floor-guard.sh"
log "floor guard: gh -> $(command -v gh)"

export RALPH_WORKTREE_DIR="${RALPH_WORKTREE_DIR:-$STATE_DIR/worktrees}"
export RALPH_LOOP_PLAN_DIR="$PLAN_DIR"

# Efficiency: the profile lives outside the repo (see the note at the top).
export RALPH_EFFICIENCY_PROFILE="${RALPH_EFFICIENCY_PROFILE:-$HOME/.config/ralph/DrinkingLog/efficiency.json}"
export RALPH_EFFICIENCY=1

# The driver. Mechanical throughput, so: cheapest competent. Kept off the zai pool so
# the driver's 50% orchestrator reserve does not compete with the cheap builder rungs
# it dispatches. Revising this is the Orchestrator's own remit (ORCHESTRATOR.md §"driver").
export RALPH_CRON_DRIVER="${RALPH_CRON_DRIVER:-codex}"

DRIVER_OUT="$(mktemp "${TMPDIR:-/tmp}/ralph-driver.XXXXXX")"
if ! ralph_resolve_cron_driver >"$DRIVER_OUT"; then
  log "FATAL: could not resolve RALPH_CRON_DRIVER"
  rm -f "$DRIVER_OUT"; exit 1
fi
DRIVER_CMD="$(cat "$DRIVER_OUT")"; rm -f "$DRIVER_OUT"
log "driver: backend=${RALPH_CRON_DRIVER_BACKEND:-?} efficiency=on profile=$RALPH_EFFICIENCY_PROFILE"

[[ -f "$PROMPT_FILE" ]] || { log "FATAL: prompt file missing: $PROMPT_FILE"; exit 1; }
log "prompt: $PROMPT_FILE ($(wc -c <"$PROMPT_FILE" | tr -d ' ') bytes)"

# Prompt by path or on stdin — never interpolated as text, so an apostrophe in it is
# inert. Same dispatch as review-loop.sh:run_backend.
STATUS=0
if [[ "$DRIVER_CMD" == *"{prompt}"* ]]; then
  PROMPT_ESC="$(printf '%q' "$PROMPT_FILE")"
  eval "${DRIVER_CMD//\{prompt\}/$PROMPT_ESC}" || STATUS=$?
else
  eval "$DRIVER_CMD" <"$PROMPT_FILE" || STATUS=$?
fi

[[ "$STATUS" -eq 0 ]] && log "=== pass end: ok" || log "=== pass end: driver exited $STATUS"
exit "$STATUS"
