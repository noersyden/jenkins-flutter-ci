#!/usr/bin/env bash
# dist_playstore.sh — Upload an AAB to the Google Play Developer API using a
# service-account JSON, signing the OAuth2 JWT with curl + openssl (no Python,
# no Fastlane). Assigns to a track as a draft by default.
#
# Requires: log.sh, config.sh sourced; jq + openssl + curl available.
# Reads globals: PLAY_PACKAGE, PLAY_CREDENTIALS (abs path), PLAY_TRACK,
#   PLAY_STATUS, BUILD_NAME, BUILD_NUMBER, FLAVOR, ARTIFACT_PATH.
# Sets TESTER_LINK on success.

_play_access_token() {
    local sa_email sa_key now exp header claim unsigned sig jwt pk
    sa_email="$(jq -r '.client_email' "$PLAY_CREDENTIALS")"
    sa_key="$(jq -r '.private_key' "$PLAY_CREDENTIALS")"
    [ -z "$sa_email" ] && die "Could not read client_email from $PLAY_CREDENTIALS"

    pk="$(mktemp)"; printf '%s\n' "$sa_key" > "$pk"
    now="$(date +%s)"; exp="$((now + 3600))"
    header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
    claim="$(printf '%s' "{\"iss\":\"$sa_email\",\"scope\":\"https://www.googleapis.com/auth/androidpublisher\",\"aud\":\"https://oauth2.googleapis.com/token\",\"iat\":$now,\"exp\":$exp}" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
    unsigned="${header}.${claim}"
    sig="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$pk" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')"
    rm -f "$pk"
    jwt="${unsigned}.${sig}"

    curl -s -X POST "https://oauth2.googleapis.com/token" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$jwt" \
        | jq -r '.access_token'
}

dist_playstore() {
    [ -n "$PLAY_PACKAGE" ] || die "Play Store package name required (--package / .flutterci.yaml android.playstore.package)."
    [ -f "$PLAY_CREDENTIALS" ] || die "Play Store credentials not found: $PLAY_CREDENTIALS"
    command -v jq >/dev/null 2>&1 || die "jq is required for Play Store upload."
    command -v openssl >/dev/null 2>&1 || die "openssl is required for Play Store upload."

    log_section "📤 Google Play ($PLAY_TRACK / $PLAY_STATUS)"
    log_dim "   package: $PLAY_PACKAGE"

    local token api edit version_code track
    token="$(_play_access_token)"
    [ -z "$token" ] || [ "$token" = "null" ] && die "Failed to obtain Play Store access token."

    api="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/$PLAY_PACKAGE"

    log_info "Creating edit..."
    edit="$(curl -s -X POST "$api/edits" -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" -d '{}' | jq -r '.id')"
    [ -z "$edit" ] || [ "$edit" = "null" ] && die "Failed to create Play edit."

    log_info "Uploading AAB ($(du -h "$ARTIFACT_PATH" | awk '{print $1}'))..."
    version_code="$(curl -s -X POST \
        "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$PLAY_PACKAGE/edits/$edit/bundles?uploadType=media" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/octet-stream" \
        --data-binary @"$ARTIFACT_PATH" | jq -r '.versionCode')"
    if [ -z "$version_code" ] || [ "$version_code" = "null" ]; then
        curl -s -X DELETE "$api/edits/$edit" -H "Authorization: Bearer $token" >/dev/null
        die "AAB upload failed."
    fi
    log_ok "Uploaded versionCode $version_code"

    log_info "Assigning to '$PLAY_TRACK' (status=$PLAY_STATUS)..."
    track="$(curl -s -X PUT "$api/edits/$edit/tracks/$PLAY_TRACK" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d "{\"track\":\"$PLAY_TRACK\",\"releases\":[{\"versionCodes\":[\"$version_code\"],\"status\":\"$PLAY_STATUS\",\"releaseNotes\":[{\"language\":\"en-US\",\"text\":\"$RELEASE_NOTES\"}]}]}" \
        | jq -r '.track')"
    if [ -z "$track" ] || [ "$track" = "null" ]; then
        curl -s -X DELETE "$api/edits/$edit" -H "Authorization: Bearer $token" >/dev/null
        die "Failed to assign track."
    fi

    log_info "Committing edit..."
    curl -s -X POST "$api/edits/$edit:commit" -H "Authorization: Bearer $token" >/dev/null

    TESTER_LINK="https://play.google.com/store/apps/details?id=$PLAY_PACKAGE"
    log_ok "Play Store upload committed. $TESTER_LINK"
}
