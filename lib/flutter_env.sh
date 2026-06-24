#!/usr/bin/env bash
# flutter_env.sh — Toolchain bootstrapping shared across platforms:
#   - ANDROID_HOME discovery + license/NDK pre-install (prevents CI hangs)
#   - FVM auto-detection so `flutter` resolves on bare Jenkins agents
#   - pubspec.yaml version extraction
#
# Sets the global FLUTTER_CMD ("flutter" or "fvm flutter").
# Requires: log.sh, config.sh sourced first.

FLUTTER_CMD="flutter"

# Ensure ANDROID_HOME points at a real SDK; auto-detect when unset/invalid.
env_setup_android_sdk() {
    if [ -n "${ANDROID_HOME:-}" ] && [ ! -d "$ANDROID_HOME" ]; then
        log_warn "ANDROID_HOME='$ANDROID_HOME' does not exist; re-detecting."
        unset ANDROID_HOME
    fi

    if [ -z "${ANDROID_HOME:-}" ]; then
        local candidates=(
            "$HOME/Library/Android/sdk"
            "$HOME/Android/Sdk"
            "/usr/local/share/android-sdk"
            "/opt/homebrew/share/android-sdk"
            "/opt/android-sdk"
        )
        local p
        for p in "${candidates[@]}"; do
            if [ -d "$p" ]; then export ANDROID_HOME="$p"; break; fi
        done
    fi

    [ -z "${ANDROID_HOME:-}" ] && { log_warn "Android SDK not located; relying on Flutter's own resolution."; return 0; }

    export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/tools/bin"
    log_ok "Android SDK: $ANDROID_HOME"
}

# Accept SDK licenses and pre-install the NDK declared in build.gradle so the
# Gradle build never blocks on an interactive prompt under Jenkins.
env_prepare_ndk() {
    # Nothing to do (and the find/grep pipelines below would trip pipefail)
    # when there is no SDK to manage.
    [ -z "${ANDROID_HOME:-}" ] && return 0

    local sdkmanager=""
    if [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
        sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
    elif [ -x "$ANDROID_HOME/tools/bin/sdkmanager" ]; then
        sdkmanager="$ANDROID_HOME/tools/bin/sdkmanager"
    else
        sdkmanager="$(find "$ANDROID_HOME/cmdline-tools" -name sdkmanager -type f 2>/dev/null | head -n1 || true)"
    fi
    [ -z "$sdkmanager" ] && return 0

    yes | "$sdkmanager" --licenses >/dev/null 2>&1 || true

    local gradle="$WORKSPACE/android/app/build.gradle"
    [ -f "$gradle" ] || gradle="$WORKSPACE/android/app/build.gradle.kts"
    [ -f "$gradle" ] || return 0

    local ndk
    # `|| true`: grep returns non-zero when ndkVersion is absent, which would
    # otherwise fail the command substitution under `set -o pipefail`.
    ndk="$(grep -m1 'ndkVersion' "$gradle" 2>/dev/null | awk -F'"' '{print $2}' || true)"
    [ -z "$ndk" ] && return 0

    local ndk_dir="$ANDROID_HOME/ndk/$ndk"
    if [ -d "$ndk_dir" ] && [ ! -f "$ndk_dir/source.properties" ]; then
        log_warn "Corrupted NDK at $ndk_dir; removing."
        rm -rf "$ndk_dir"
    fi
    if [ ! -d "$ndk_dir" ]; then
        log_info "Pre-installing NDK $ndk..."
        yes | "$sdkmanager" "ndk;$ndk" >/dev/null 2>&1 || true
    fi
}

# Decide whether to use FVM and make sure `fvm`/`flutter` are on PATH.
#   $1 = "true" | "false" | "" (auto: use FVM when a .fvm dir exists)
env_setup_flutter() {
    local use_fvm="$1"

    if [ -z "$use_fvm" ]; then
        if [ -d "$WORKSPACE/.fvm" ]; then use_fvm="true"; else use_fvm="false"; fi
    fi
    [ "$use_fvm" != "true" ] && { FLUTTER_CMD="flutter"; return 0; }

    if ! command -v fvm >/dev/null 2>&1; then
        local paths=("$HOME/fvm/bin" "$HOME/.fvm/bin" "/var/lib/jenkins/fvm/bin" "$HOME/.pub-cache/bin" "/usr/local/bin")
        local p
        for p in "${paths[@]}"; do
            if [ -x "$p/fvm" ]; then export PATH="$p:$PATH"; break; fi
        done
    fi

    if ! command -v fvm >/dev/null 2>&1; then
        log_warn "FVM requested but not found; falling back to system Flutter."
        FLUTTER_CMD="flutter"
        return 0
    fi

    FLUTTER_CMD="fvm flutter"

    # Pin the project's Flutter version (from .flutterci.yaml flutter.version)
    # so the agent needs no separate `fvm use` pre-step. Writes .fvmrc/.fvm in
    # the workspace (ephemeral on CI).
    if [ -n "${FLUTTER_VERSION:-}" ]; then
        log_info "Pinning Flutter $FLUTTER_VERSION via FVM..."
        ( cd "$WORKSPACE" && fvm install "$FLUTTER_VERSION" && fvm use "$FLUTTER_VERSION" --force ) \
            || die "fvm use $FLUTTER_VERSION failed."
    fi

    # Put the FVM-managed SDK on PATH so `dart` and friends resolve too.
    local root
    root="$(cd "$WORKSPACE" && fvm flutter --version --machine 2>/dev/null | grep -o '"flutterRoot":"[^"]*"' | cut -d'"' -f4 || true)"
    [ -n "$root" ] && [ -d "$root/bin" ] && export PATH="$root/bin:$PATH"
    log_ok "Using FVM Flutter${FLUTTER_VERSION:+ $FLUTTER_VERSION}"
}

# Parse `version: x.y.z+n` from pubspec.yaml into globals BUILD_NAME / BUILD_NUMBER.
env_read_pubspec_version() {
    local pubspec="$WORKSPACE/pubspec.yaml"
    [ -f "$pubspec" ] || die "pubspec.yaml not found in $WORKSPACE — is this a Flutter project?"
    local full
    full="$(grep -m1 '^version:' "$pubspec" | awk '{print $2}' || true)"
    [ -z "$full" ] && die "Could not read 'version:' from pubspec.yaml"
    BUILD_NAME="${full%%+*}"
    BUILD_NUMBER="${full#*+}"
    # No '+n' suffix -> default build number to 1. Use an if (not `cond &&`),
    # otherwise the function returns non-zero and trips `set -e` at the caller.
    if [ "$BUILD_NUMBER" = "$full" ]; then BUILD_NUMBER="1"; fi
    return 0
}
