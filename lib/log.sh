#!/usr/bin/env bash
# log.sh — Consistent logging helpers shared by every module.
# Sourced, never executed directly.

# Disable colors when not a TTY or when NO_COLOR is set (Jenkins-friendly).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _C_RESET=$'\033[0m'; _C_DIM=$'\033[2m'; _C_RED=$'\033[31m'
    _C_GREEN=$'\033[32m'; _C_YELLOW=$'\033[33m'; _C_BLUE=$'\033[34m'; _C_BOLD=$'\033[1m'
else
    _C_RESET=""; _C_DIM=""; _C_RED=""; _C_GREEN=""; _C_YELLOW=""; _C_BLUE=""; _C_BOLD=""
fi

log_info()  { printf '%s\n' "${_C_BLUE}ℹ${_C_RESET}  $*"; }
log_ok()    { printf '%s\n' "${_C_GREEN}✅${_C_RESET} $*"; }
log_warn()  { printf '%s\n' "${_C_YELLOW}⚠️${_C_RESET}  $*" >&2; }
log_err()   { printf '%s\n' "${_C_RED}❌${_C_RESET} $*" >&2; }
log_step()  { printf '%s\n' "${_C_BOLD}▶ $*${_C_RESET}"; }
log_dim()   { printf '%s\n' "${_C_DIM}$*${_C_RESET}"; }

log_section() {
    printf '%s\n' "${_C_BOLD}============================================================${_C_RESET}"
    printf '%s\n' "${_C_BOLD}$*${_C_RESET}"
    printf '%s\n' "${_C_BOLD}============================================================${_C_RESET}"
}

die() { log_err "$*"; exit 1; }
