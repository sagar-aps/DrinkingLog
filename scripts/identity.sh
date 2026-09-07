#!/usr/bin/env bash
# identity.sh — run a command as one of this repo's GitHub App identities.
#
#   scripts/identity.sh <manager|orchestrator> <command> [args...]
#
# Ralph's contract (.agents/ralph/resolve-identity.sh): the wrapper takes the ROLE
# as its first argument and execs the rest. `ralph integrate --pr` calls it as
#   "$RESOLVED_WRAPPER" orchestrator git push ...
#   "$RESOLVED_WRAPPER" orchestrator gh pr create ...
# so both GitHub writes are authored by the App rather than the owner's account.
#
# This lives in scripts/ rather than the conventional .agents/ralph/ on purpose:
# bin/ralph resolves its templates from "$PWD/.agents/ralph" whenever that
# directory exists, so creating one here to hold a single file would make every
# `ralph` invocation from inside this repo fail to find review-loop.sh. The
# deviation is recorded in the manager charter's Project facts -> Identities.
#
# Private keys are NOT in this repo. They live outside it, mode 600.

set -euo pipefail

KEY_DIR="${RALPH_GH_APP_KEY_DIR:-/home/sagar_ap/homelab/ralph-harness/.agents/ralph/gh-apps}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ralph/gh-app"

die() { printf 'identity.sh: %s\n' "$*" >&2; exit 1; }

[[ $# -ge 2 ]] || die "usage: identity.sh <manager|orchestrator> <command> [args...]"

ROLE="$1"; shift

# Per-role App coordinates. Bot user ids are needed for the noreply commit email
# that attributes a commit to the App; they come from /users/<slug>[bot].
case "$ROLE" in
  manager)
    APP_ID=4865203; INSTALL_ID=159875616
    KEY_FILE="$KEY_DIR/manager.pem"
    BOT_NAME="sagar-aps-manager[bot]"; BOT_ID=326237815
    ;;
  orchestrator)
    APP_ID=4865217; INSTALL_ID=159875883
    KEY_FILE="$KEY_DIR/orchestrator.pem"
    BOT_NAME="sagar-aps-orchestrator[bot]"; BOT_ID=326238164
    ;;
  *) die "unknown role '$ROLE' (expected: manager, orchestrator)" ;;
esac

[[ -r "$KEY_FILE" ]] || die "private key not readable: $KEY_FILE"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

mint_installation_token() {
  local now header payload sig jwt resp token
  now="$(date +%s)"
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  # iat backdated 60s to tolerate clock skew; GitHub caps App JWT life at 10 min.
  payload="$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$APP_ID" | b64url)"
  sig="$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEY_FILE" -binary | b64url)"
  jwt="$header.$payload.$sig"

  resp="$(curl -sS -X POST \
    -H "Authorization: Bearer $jwt" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "https://api.github.com/app/installations/$INSTALL_ID/access_tokens")" \
    || die "token request failed for role '$ROLE'"

  token="$(printf '%s' "$resp" | jq -r '.token // empty')"
  # Never echo $resp on failure: on success it contains the token.
  [[ -n "$token" ]] || die "no token in response for role '$ROLE' (message: $(printf '%s' "$resp" | jq -r '.message // "unknown"'))"

  mkdir -p "$CACHE_DIR"; chmod 700 "$CACHE_DIR" 2>/dev/null || true
  local tmp; tmp="$(mktemp "$CACHE_DIR/.$ROLE.XXXXXX")"
  chmod 600 "$tmp"
  printf '%s' "$resp" | jq -c '{token, expires_at}' >"$tmp"
  mv "$tmp" "$CACHE_DIR/$ROLE.json"
  printf '%s' "$token"
}

cached_token() {
  local f="$CACHE_DIR/$ROLE.json" exp now
  [[ -r "$f" ]] || return 1
  exp="$(jq -r '.expires_at // empty' <"$f" 2>/dev/null)" || return 1
  [[ -n "$exp" ]] || return 1
  # Installation tokens live 1h. Treat anything inside 5 minutes of expiry as
  # spent, so a long `ralph review` can't have its token die mid-push.
  exp="$(date -d "$exp" +%s 2>/dev/null)" || return 1
  now="$(date +%s)"
  (( exp - now > 300 )) || return 1
  jq -r '.token' <"$f"
}

TOKEN="$(cached_token || true)"
[[ -n "$TOKEN" ]] || TOKEN="$(mint_installation_token)"

# --- gh ---------------------------------------------------------------------
export GH_TOKEN="$TOKEN" GITHUB_TOKEN="$TOKEN"
# gh otherwise prefers the keyring/hosts.yml entry for the owner account.
unset GH_CONFIG_DIR GH_ENTERPRISE_TOKEN 2>/dev/null || true

# --- git --------------------------------------------------------------------
# Rewrite this machine's SSH remotes to HTTPS and supply the App token through a
# credential helper rather than embedding it in a URL, so the token never lands
# in .git/config, a remote string, or an error message. All of it is process-local
# env (GIT_CONFIG_COUNT), so the owner's own SSH workflow is untouched.
export GIT_CONFIG_COUNT=5
export GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf'          GIT_CONFIG_VALUE_0='git@github.com:'
export GIT_CONFIG_KEY_1='url.https://github.com/.insteadOf'          GIT_CONFIG_VALUE_1='git@github.com-personal:'
export GIT_CONFIG_KEY_2='url.https://github.com/.insteadOf'          GIT_CONFIG_VALUE_2='ssh://git@github.com/'
export GIT_CONFIG_KEY_3='credential.helper'                          GIT_CONFIG_VALUE_3=''
export GIT_CONFIG_KEY_4='credential.helper'                          GIT_CONFIG_VALUE_4='!f() { echo username=x-access-token; echo "password=${GH_TOKEN}"; }; f'
export GIT_TERMINAL_PROMPT=0

# Attribute commits to the App, not to whoever's ~/.gitconfig is ambient.
export GIT_AUTHOR_NAME="$BOT_NAME"    GIT_AUTHOR_EMAIL="${BOT_ID}+${BOT_NAME}@users.noreply.github.com"
export GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="${BOT_ID}+${BOT_NAME}@users.noreply.github.com"

export RALPH_ACTIVE_IDENTITY="$ROLE"

exec "$@"
