#!/usr/bin/env bash
# notify.sh — Post a build/release embed to a Discord webhook.
# No-ops gracefully when no webhook is configured or NO_NOTIFY=true.
#
# Requires: log.sh sourced. Reads globals:
#   DISCORD_WEBHOOK_URL, DISCORD_THREAD_ID, APP_NAME, FLAVOR, BRANCH,
#   BUILD_NAME, BUILD_NUMBER, DISTRIBUTION, TESTER_LINK, GIT_COMMIT_MSG.

_json_escape() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null \
    || printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# $1 = "success" | "failure", $2 = optional message override
notify_discord() {
    local status="$1" message="${2:-}"
    [ "${NO_NOTIFY:-false}" = "true" ] && return 0
    [ -z "$DISCORD_WEBHOOK_URL" ] && { log_dim "No Discord webhook configured; skipping notification."; return 0; }

    local title color desc
    if [ "$status" = "success" ]; then
        title="🚀 ${APP_NAME:-App} deployed"; color=5763719
        desc="${message:-Built and distributed via **$DISTRIBUTION**.}"
    else
        title="❌ ${APP_NAME:-App} build failed"; color=15158332
        desc="${message:-The pipeline failed. Check the Jenkins log.}"
    fi

    local link_field=""
    if [ -n "$TESTER_LINK" ]; then
        link_field=",{\"name\":\"🔗 Link\",\"value\":\"$(_json_escape "$TESTER_LINK")\",\"inline\":false}"
    fi
    local commit_field=""
    if [ -n "$GIT_COMMIT_MSG" ]; then
        commit_field=",{\"name\":\"📝 Commit\",\"value\":\"$(_json_escape "$GIT_COMMIT_MSG")\",\"inline\":false}"
    fi

    local ts payload url
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    payload="$(cat <<EOF
{
  "username": "Flutter CI",
  "embeds": [{
    "title": "$(_json_escape "$title")",
    "description": "$(_json_escape "$desc")",
    "color": $color,
    "fields": [
      {"name":"📦 Version","value":"${BUILD_NAME:-?}+${BUILD_NUMBER:-?}","inline":true},
      {"name":"🌿 Branch","value":"${BRANCH:-?}","inline":true},
      {"name":"🎯 Flavor","value":"${FLAVOR:-default}","inline":true}
      ${commit_field}${link_field}
    ],
    "footer": {"text": "Flutter CI • $DISTRIBUTION"},
    "timestamp": "$ts"
  }]
}
EOF
)"

    url="$DISCORD_WEBHOOK_URL"
    [ -n "$DISCORD_THREAD_ID" ] && url="${url}?thread_id=${DISCORD_THREAD_ID}"

    if curl -s -X POST "$url" -H 'Content-Type: application/json' -d "$payload" >/dev/null; then
        log_ok "Discord notified ($status)"
    else
        log_warn "Discord notification failed (non-fatal)."
    fi
}
