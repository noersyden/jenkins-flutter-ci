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
    # NOTE: do not use yq's `//` alternative operator here — it treats a
    # boolean `false` as empty, silently dropping `use_fvm: false`. Read the
    # raw value and map a literal "null"/empty to the default instead.
    local val
    val="$("$YQ_BIN" eval "$path" "$CONFIG_FILE" 2>/dev/null)"
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

# Materialize a project `.env` from `.flutterci.yaml` -> flavors.<flavor>.dotenv.
# No-op unless that block exists (apps that read env at compile time, or commit
# their own .env, need nothing here). Generic over keys — never hardcodes them.
#   $1 = logical environment (production | staging)
# Secrets must NOT live in .flutterci.yaml; they are appended here from env vars
# bound by Jenkins credentials, and only when present.
config_write_dotenv() {
    local flavor="$1"
    [ -f "$CONFIG_FILE" ] || return 0
    # Skip silently when the project declares no per-flavor dotenv block.
    "$YQ_BIN" eval -e ".flavors.\"$flavor\".dotenv" "$CONFIG_FILE" >/dev/null 2>&1 || return 0

    local env_file="$WORKSPACE/.env"
    : > "$env_file"
    # KEY=VALUE for every entry in the map (mikefarah yq v4).
    "$YQ_BIN" eval \
        ".flavors.\"$flavor\".dotenv | to_entries | .[] | .key + \"=\" + .value" \
        "$CONFIG_FILE" >> "$env_file"

    # Runtime-injected, non-yaml values.
    printf 'LAST_UPDATE=%s\n' "$(date '+%d %B %Y')" >> "$env_file"
    # Secrets from Jenkins credentials binding (appended only if exported).
    local secret
    for secret in KIOSK_SOCKET_API_KEY BASIC_PASSWORD USERNAME PASSWORD MIXPANEL_API_KEY; do
        if [ -n "${!secret:-}" ]; then
            printf '%s=%s\n' "$secret" "${!secret}" >> "$env_file"
        fi
    done

    log_ok ".env generated for flavor '$flavor' ($(grep -c '=' "$env_file") keys)"
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
