#!/usr/bin/env bash
# build.sh — Flutter artifact builds (apk / appbundle / ipa) and output-path
# resolution. Honors optional flavor. Sets ARTIFACT_PATH on success.
#
# Requires: log.sh, flutter_env.sh sourced first; FLUTTER_CMD, WORKSPACE,
# BUILD_NAME, BUILD_NUMBER set.

ARTIFACT_PATH=""

# Compute the conventional output path Flutter writes for a given build type.
#   $1 = apk | appbundle | ipa   $2 = flavor (may be empty)
_artifact_path_for() {
    local type="$1" flavor="$2"
    case "$type" in
        apk)
            if [ -n "$flavor" ]; then
                echo "build/app/outputs/flutter-apk/app-${flavor}-release.apk"
            else
                echo "build/app/outputs/flutter-apk/app-release.apk"
            fi ;;
        appbundle)
            if [ -n "$flavor" ]; then
                echo "build/app/outputs/bundle/${flavor}Release/app-${flavor}-release.aab"
            else
                echo "build/app/outputs/bundle/release/app-release.aab"
            fi ;;
        ipa)
            echo "build/ios/ipa" ;;  # directory; caller picks the .ipa inside
    esac
}

# Run `flutter build`. Args: <type> <flavor> [extra flutter args...]
build_flutter() {
    local type="$1" flavor="$2"; shift 2
    local extra=("$@")

    log_step "flutter build $type ${flavor:+(flavor=$flavor) }${BUILD_NAME}+${BUILD_NUMBER}"

    local args=(build "$type" --release
        --build-name="$BUILD_NAME" --build-number="$BUILD_NUMBER")
    [ -n "$flavor" ] && args+=(--flavor "$flavor" --dart-define=ENVIRONMENT="$flavor")
    args+=("${extra[@]}")

    ( cd "$WORKSPACE" && $FLUTTER_CMD "${args[@]}" ) || die "Flutter build failed."

    if [ "$type" = "ipa" ]; then
        local dir="$WORKSPACE/build/ios/ipa"
        ARTIFACT_PATH="$(find "$dir" -maxdepth 1 -name '*.ipa' 2>/dev/null | head -n1)"
        [ -z "$ARTIFACT_PATH" ] && die "IPA not found under $dir"
    else
        ARTIFACT_PATH="$WORKSPACE/$(_artifact_path_for "$type" "$flavor")"
        [ -f "$ARTIFACT_PATH" ] || die "Build succeeded but artifact missing: $ARTIFACT_PATH"
    fi
    log_ok "Artifact: $ARTIFACT_PATH"
}

# Restore pub dependencies before building.
build_pub_get() {
    log_step "Resolving dependencies (pub get)"
    ( cd "$WORKSPACE" && $FLUTTER_CMD pub get ) || die "flutter pub get failed."
}
