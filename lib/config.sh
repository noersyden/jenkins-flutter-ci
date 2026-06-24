#!/usr/bin/env bash
# config.sh — Load and resolve configuration with a strict precedence:
#
#   CLI flag (Jenkins param)  >  environment variable  >  .flutterci.yaml  >  built-in default
#
# Identity / credentials (app id, name, package, json key paths) live in
# .flutterci.yaml inside each Flutter project. Volatile run parameters
# (branch, flavor, distribution) come from Jenkins.
#
# Requires: log.sh sourced first.

CONFIG_FILE="${CONFIG_FILE:-}"
YQ_BIN=""

# Locate or bootstrap the `yq` (mikefarah v4) binary used to read YAML.
# Mirrors the self-bootstrapping pattern already used by ci_build.sh (rclone/firebase).
config_ensure_yq() {
    if command -v yq >/dev/null 2>&1; then
        YQ_BIN="yq"
        return 0
    fi

    local cache_dir="${FLUTTERCI_CACHE_DIR:-$HOME/.cache/flutterci}"
    local cached="$cache_dir/yq"
    if [ -x "$cached" ]; then
        YQ_BIN="$cached"
        return 0
    fi

    local os arch
    case "$(uname -s)" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        *) die "Unsupported OS for yq bootstrap: $(uname -s)" ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch="arm64" ;;
        x86_64|amd64)  arch="amd64" ;;
        *) die "Unsupported arch for yq bootstrap: $(uname -m)" ;;
    esac

    log_info "yq not found; downloading standalone binary (${os}_${arch})..."
    mkdir -p "$cache_dir"
    local url="https://github.com/mikefarah/yq/releases/latest/download/yq_${os}_${arch}"
    if ! curl -fsSL -o "$cached" "$url"; then
        die "Failed to download yq from $url"
    fi
    chmod +x "$cached"
    YQ_BIN="$cached"
    log_ok "yq ready at $cached"
}

# Read a scalar from the config file. Returns $2 (default) when the file is
# missing or the path resolves to null/empty.
yget() {
    local path="$1" default="${2:-}"
    [ -f "$CONFIG_FILE" ] || { printf '%s' "$default"; return; }
    local val
    val="$("$YQ_BIN" eval "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        printf '%s' "$default"
    else
        printf '%s' "$val"
    fi
}

# Resolve one setting honoring the precedence chain.
#   $1 = value already parsed from a CLI flag (may be empty)
#   $2 = environment variable value (may be empty)
#   $3 = yaml path expression
#   $4 = default
resolve() {
    local cli="$1" env="$2" path="$3" default="$4"
    if [ -n "$cli" ];  then printf '%s' "$cli";  return; fi
    if [ -n "$env" ];  then printf '%s' "$env";  return; fi
    yget "$path" "$default"
}

# Resolve the Firebase app id for a flavor, falling back to a default entry,
# then to a flat scalar `android.firebase.app_id`.
resolve_firebase_app_id() {
    local flavor="$1" cli="$2" env="$3"
    if [ -n "$cli" ]; then printf '%s' "$cli"; return; fi
    if [ -n "$env" ]; then printf '%s' "$env"; return; fi
    local id=""
    if [ -n "$flavor" ]; then
        id="$(yget ".android.firebase.app_ids.${flavor}" "")"
    fi
    [ -z "$id" ] && id="$(yget '.android.firebase.app_ids.default' '')"
    [ -z "$id" ] && id="$(yget '.android.firebase.app_id' '')"
    printf '%s' "$id"
}

# Resolve a path that may be relative to the project workspace into an
# absolute path, leaving already-absolute paths untouched.
abs_path() {
    local p="$1"
    [ -z "$p" ] && return
    case "$p" in
        /*) printf '%s' "$p" ;;
        *)  printf '%s' "$WORKSPACE/$p" ;;
    esac
}
