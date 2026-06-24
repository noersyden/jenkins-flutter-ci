#!/usr/bin/env bash
# dist_firebase.sh — Upload an APK/AAB to Firebase App Distribution.
# Bootstraps the firebase CLI standalone binary when absent (no Node required).
#
# Requires: log.sh, config.sh sourced. Reads globals:
#   FIREBASE_APP_ID, FIREBASE_CREDENTIALS (abs path), FIREBASE_GROUPS,
#   RELEASE_NOTES, ARTIFACT_PATH.
# Sets TESTER_LINK on success.

FIREBASE_BIN=""
TESTER_LINK=""

_firebase_ensure_cli() {
    if command -v firebase >/dev/null 2>&1; then FIREBASE_BIN="firebase"; return; fi
    if command -v npx >/dev/null 2>&1; then FIREBASE_BIN="npx --yes firebase-tools"; return; fi

    local cache_dir="${FLUTTERCI_CACHE_DIR:-$HOME/.cache/flutterci}"
    local cached="$cache_dir/firebase"
    if [ -x "$cached" ]; then FIREBASE_BIN="$cached"; return; fi

    local os
    case "$(uname -s)" in
        Darwin) os="macos" ;;
        Linux)  os="linux" ;;
        *) die "Unsupported OS for firebase CLI bootstrap." ;;
    esac
    log_info "firebase CLI not found; downloading standalone binary..."
    mkdir -p "$cache_dir"
    curl -fsSL -o "$cached" "https://firebase.tools/bin/${os}/latest" || die "firebase CLI download failed."
    chmod +x "$cached"
    FIREBASE_BIN="$cached"
    log_ok "firebase CLI ready"
}

dist_firebase() {
    [ -n "$FIREBASE_APP_ID" ] || die "Firebase app id is required (--firebase-app-id / FIREBASE_APP_ID / .flutterci.yaml)."
    [ -f "$FIREBASE_CREDENTIALS" ] || die "Firebase credentials not found: $FIREBASE_CREDENTIALS"

    log_section "📤 Firebase App Distribution"
    log_dim "   app:    $FIREBASE_APP_ID"
    log_dim "   groups: ${FIREBASE_GROUPS:-<none>}"

    _firebase_ensure_cli

    local out
    out="$(GOOGLE_APPLICATION_CREDENTIALS="$FIREBASE_CREDENTIALS" \
        $FIREBASE_BIN appdistribution:distribute "$ARTIFACT_PATH" \
            --app "$FIREBASE_APP_ID" \
            ${FIREBASE_GROUPS:+--groups "$FIREBASE_GROUPS"} \
            --release-notes "$RELEASE_NOTES" 2>&1 | tee /dev/stderr)" || die "Firebase upload failed."

    TESTER_LINK="$(printf '%s' "$out" | grep -ioE 'https://appdistribution.firebase.google.com/testerapps/[^[:space:]]+' | head -n1)"
    [ -z "$TESTER_LINK" ] && TESTER_LINK="https://appdistribution.firebase.google.com/testerapps/${FIREBASE_APP_ID#*:android:}"
    log_ok "Distributed. $TESTER_LINK"
}
