#!/usr/bin/env bash
# notify.sh — Post a build/release embed to a Discord webhook.
# No-ops gracefully when no webhook is configured or NO_NOTIFY=true.
#
# Requires: log.sh sourced. Reads globals:
#   DISCORD_WEBHOOK_URL, DISCORD_THREAD_ID, APP_NAME, FLAVOR, BRANCH,
#   BUILD_NAME, BUILD_NUMBER, DISTRIBUTION, TESTER_LINK, GIT_COMMIT_MSG,
#   LOG_FILE (optional — on failure its last lines are attached), BUILD_URL.
#
# Per-event webhooks (each falls back to DISCORD_WEBHOOK_URL when unset):
#   DISCORD_WEBHOOK_STARTED, DISCORD_WEBHOOK_SUCCESS, DISCORD_WEBHOOK_FAILURE
# Per-event threads (each falls back to DISCORD_THREAD_ID when unset):
#   DISCORD_THREAD_STARTED, DISCORD_THREAD_SUCCESS, DISCORD_THREAD_FAILURE

_json_escape() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null \
    || printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Number of trailing log lines attached to a failure notification.
FAILURE_LOG_LINES="${FAILURE_LOG_LINES:-10}"

# Pick the per-event value, falling back to a shared default.
#   $1 = status, $2 = default value, $3 = env var prefix (e.g. DISCORD_WEBHOOK)
_event_value() {
    local ev="$1" fallback="$2" prefix="$3" var
    var="${prefix}_$(printf '%s' "$ev" | tr '[:lower:]' '[:upper:]')"
    printf '%s' "${!var:-$fallback}"
}

# $1 = "started" | "success" | "failure", $2 = optional message override
notify_discord() {
    local status="$1" message="${2:-}"
    [ "${NO_NOTIFY:-false}" = "true" ] && return 0

    local webhook thread
    webhook="$(_event_value "$status" "${DISCORD_WEBHOOK_URL:-}" DISCORD_WEBHOOK)"
    thread="$(_event_value "$status" "${DISCORD_THREAD_ID:-}" DISCORD_THREAD)"
    [ -z "$webhook" ] && { log_dim "No Discord webhook for '$status'; skipping notification."; return 0; }

    local title color desc
    case "$status" in
        started)
            title="🏗️ ${APP_NAME:-App} build started"; color=3447003
            desc="${message:-Building & distributing via **$DISTRIBUTION**…}" ;;
        success)
            title="🚀 ${APP_NAME:-App} deployed"; color=5763719
            desc="${message:-Built and distributed via **$DISTRIBUTION**.}" ;;
        *)
            title="❌ ${APP_NAME:-App} build failed"; color=15158332
            desc="${message:-The pipeline failed. Check the Jenkins log.}" ;;
    esac

    local link_field=""
    if [ -n "$TESTER_LINK" ]; then
        link_field=",{\"name\":\"🔗 Link\",\"value\":\"$(_json_escape "$TESTER_LINK")\",\"inline\":false}"
    fi
    local commit_field=""
    if [ -n "$GIT_COMMIT_MSG" ]; then
        commit_field=",{\"name\":\"📝 Commit\",\"value\":\"$(_json_escape "$GIT_COMMIT_MSG")\",\"inline\":false}"
    fi

    # On failure, attach the last N lines of the build log so the cause is
    # visible straight in Discord. Strip ANSI colors; Discord field cap is 1024.
    local log_field=""
    if [ "$status" = "failure" ] && [ -n "${LOG_FILE:-}" ] && [ -f "$LOG_FILE" ]; then
        local tail_log
        tail_log="$(tail -n "$FAILURE_LOG_LINES" "$LOG_FILE" \
            | sed $'s/\033\\[[0-9;]*m//g' | tail -c 980)"
        if [ -n "$tail_log" ]; then
            log_field=",{\"name\":\"🪵 Last $FAILURE_LOG_LINES lines\",\"value\":\"\`\`\`\n$(_json_escape "$tail_log")\n\`\`\`\",\"inline\":false}"
        fi
    fi
    local build_field=""
    if [ -n "${BUILD_URL:-}" ]; then
        build_field=",{\"name\":\"🔧 Jenkins\",\"value\":\"$(_json_escape "${BUILD_URL}console")\",\"inline\":false}"
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
      ${commit_field}${link_field}${log_field}${build_field}
    ],
    "footer": {"text": "Flutter CI • $DISTRIBUTION"},
    "timestamp": "$ts"
  }]
}
EOF
)"

    url="$webhook"
    [ -n "$thread" ] && url="${url}?thread_id=${thread}"

    if curl -s -X POST "$url" -H 'Content-Type: application/json' -d "$payload" >/dev/null; then
        log_ok "Discord notified ($status)"
    else
        log_warn "Discord notification failed (non-fatal)."
    fi
}
