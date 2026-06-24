#!/usr/bin/env bash
# ci/jenkins.sh — reusable runner for Jenkins freestyle "Execute shell" jobs.
#
# Keep the per-job Execute shell to a fixed 3-line bootstrap (identical across
# every app) and let this file — versioned in the single-source-of-truth repo —
# hold all the logic. Updating CI behaviour for the whole fleet = one commit.
#
# Per-job Execute shell:
#   set -e
#   TOOL="$HOME/.jenkins-tools/flutter-ci"
#   git -C "$TOOL" pull -q 2>/dev/null || git clone -q https://github.com/noersyden/jenkins-flutter-ci.git "$TOOL"
#   exec "$TOOL/ci/jenkins.sh"
#
# Reads env vars provided by Jenkins + the Generic Webhook Trigger plugin:
#   WORKSPACE     (Jenkins) — checked-out project dir
#   BRANCH, PLATFORM, DISTRIBUTION, FLAVOR, DRY_RUN  (webhook payload)
#
# JDK/Flutter toolchain is the agent's responsibility (configure it at the
# Jenkins node or job level); this runner does not touch JAVA_HOME.
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Assemble flutterci arguments from the environment --------------------
ARGS=(deploy --workspace "${WORKSPACE:-$PWD}")
[ -n "${PLATFORM:-}" ]      && ARGS+=(--platform "$PLATFORM")
[ -n "${DISTRIBUTION:-}" ]  && ARGS+=(--distribution "$DISTRIBUTION")
[ -n "${BRANCH:-}" ]        && ARGS+=(--branch "$BRANCH")
[ -n "${FLAVOR:-}" ]        && ARGS+=(--flavor "$FLAVOR")
[ "${DRY_RUN:-}" = "true" ] && ARGS+=(--dry-run)

exec "$REPO_DIR/flutterci" "${ARGS[@]}"
