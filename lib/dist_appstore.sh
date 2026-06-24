#!/usr/bin/env bash
# dist_appstore.sh — Upload an IPA to App Store Connect (TestFlight / App Store
# review) via `xcrun altool` using an App Store Connect API key (.p8). Falls
# back to a Fastlane lane when the project ships a Fastfile and altool is not
# usable. macOS + Xcode only.
#
# Requires: log.sh, config.sh sourced. Reads globals:
#   IOS_API_KEY_ID, IOS_API_ISSUER_ID, IOS_API_KEY_PATH (abs path),
#   ARTIFACT_PATH, FLAVOR, FASTLANE_LANE.
# Sets TESTER_LINK on success.

_appstore_via_altool() {
    command -v xcrun >/dev/null 2>&1 || return 1
    [ -n "$IOS_API_KEY_ID" ] && [ -n "$IOS_API_ISSUER_ID" ] && [ -f "$IOS_API_KEY_PATH" ] || return 1

    # altool resolves the key from a private_keys dir by KEYID.
    local key_dir="$HOME/.appstoreconnect/private_keys"
    mkdir -p "$key_dir"
    cp "$IOS_API_KEY_PATH" "$key_dir/AuthKey_${IOS_API_KEY_ID}.p8"

    log_info "Uploading IPA via altool..."
    xcrun altool --upload-app -f "$ARTIFACT_PATH" -t ios \
        --apiKey "$IOS_API_KEY_ID" --apiIssuer "$IOS_API_ISSUER_ID" \
        || die "altool upload failed."
    return 0
}

_appstore_via_fastlane() {
    [ -f "$WORKSPACE/ios/Fastfile" ] || [ -f "$WORKSPACE/ios/fastlane/Fastfile" ] || return 1
    command -v fastlane >/dev/null 2>&1 || command -v bundle >/dev/null 2>&1 || return 1

    log_info "Delegating to Fastlane lane '$FASTLANE_LANE'..."
    local opts=""
    [ -n "$FLAVOR" ] && opts="flavor:$FLAVOR"
    ( cd "$WORKSPACE/ios" && {
        if [ -f Gemfile ]; then bundle exec fastlane "$FASTLANE_LANE" $opts;
        else fastlane "$FASTLANE_LANE" $opts; fi
    } ) || die "Fastlane lane failed."
    return 0
}

dist_appstore() {
    [ "$(uname -s)" = "Darwin" ] || die "iOS distribution requires macOS."
    log_section "📤 App Store Connect / TestFlight"

    if _appstore_via_altool; then :;
    elif _appstore_via_fastlane; then :;
    else
        die "No usable iOS upload path: provide an App Store Connect API key (key id, issuer id, .p8) or an ios/Fastfile."
    fi

    TESTER_LINK="https://appstoreconnect.apple.com/apps"
    log_ok "Submitted to App Store Connect. Processing in TestFlight may take a few minutes."
}
