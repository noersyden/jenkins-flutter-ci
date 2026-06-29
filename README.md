# flutterci

Single source-of-truth CLI to **build and distribute every Flutter app** in the
fleet. Pure Bash, no Ruby/Docker required. Replaces the ~dozen drifting
`scripts/deploy_android.sh` / `ci_build.sh` copies with one versioned tool.

## Model

```
Jenkins job (params: branch, flavor, distribution)
   ├── checks out the Flutter project        →  ./project
   ├── checks out this CLI                    →  ./flutterci
   └── runs: flutterci deploy --workspace ./project ...
                 │
                 ├── reads ./project/.flutterci.yaml   (identity + credential paths)
                 ├── builds APK / AAB / IPA            (FVM auto-detected)
                 ├── distributes  firebase|playstore|appstore
                 └── notifies Discord
```

- **Runs in an existing workspace** — Jenkins owns SCM checkout; the CLI never clones.
- **Identity stays with the project** — `.flutterci.yaml` (app name, app ids, credential paths) is committed in each Flutter repo.
- **Run parameters come from Jenkins** — branch, flavor, distribution are flags.

### Configuration precedence

```
CLI flag (Jenkins param)  >  environment variable  >  .flutterci.yaml  >  built-in default
```

So a project pins its Firebase app id and credential path in `.flutterci.yaml`,
while Jenkins decides per-run which `--branch`, `--flavor`, and `--distribution`
to use. Any value can still be force-overridden by a flag or env var.

## Quick start

1. Copy [`examples/.flutterci.yaml`](examples/.flutterci.yaml) into the root of a
   Flutter project and fill in its identity + credential paths.
2. From the project directory:

```bash
# Android → Firebase App Distribution
flutterci deploy -d firebase -f production

# Android → Play Store (internal track, draft)
flutterci deploy -d playstore -f production

# iOS → App Store Connect / TestFlight
flutterci deploy -p ios -d appstore -f production

# Inspect what would run, resolving the full precedence chain:
flutterci config

# Build without uploading:
flutterci deploy -d firebase --dry-run
```

## Options

Run `flutterci --help` for the complete list. Highlights:

| Flag | Purpose |
|------|---------|
| `-p, --platform` | `android` (default) or `ios` |
| `-d, --distribution` | `firebase` \| `playstore` \| `appstore` |
| `-f, --flavor` | Build flavor (blank = none) |
| `-b, --branch` | Branch name for notification metadata |
| `--workspace` | Project root (default: cwd) |
| `--config` | Custom `.flutterci.yaml` path |
| `--dry-run` | Build only, skip upload + notify |
| `--no-notify` | Skip Discord |

Env overrides (handy for Jenkins credentials binding): `FIREBASE_APP_ID`,
`FIREBASE_CREDENTIALS`, `PLAY_CREDENTIALS`, `DISCORD_WEBHOOK_URL`,
`IOS_API_KEY_ID`, `IOS_API_ISSUER_ID`, `IOS_API_KEY_PATH`, and the
`FLUTTERCI_*` family — see `--help`.

### Discord notifications

Three events fire: **started** (build kicks off), **success** (deployed), and
**failure** (pipeline died — the last 10 log lines are attached inline). Set
`BUILD_URL` (Jenkins provides it) to include a console link.

Each event can go to its own webhook/thread; unset ones fall back to the shared
`DISCORD_WEBHOOK_URL` / `DISCORD_THREAD_ID`:

| Event | Webhook env | Thread env | YAML key |
|-------|-------------|------------|----------|
| started | `DISCORD_WEBHOOK_STARTED` | `DISCORD_THREAD_STARTED` | `.notify.discord.events.started` |
| success | `DISCORD_WEBHOOK_SUCCESS` | `DISCORD_THREAD_SUCCESS` | `.notify.discord.events.success` |
| failure | `DISCORD_WEBHOOK_FAILURE` | `DISCORD_THREAD_FAILURE` | `.notify.discord.events.failure` |

`.flutterci.yaml` example:

```yaml
notify:
  discord:
    webhook_url: https://discord.com/api/webhooks/AAA   # shared fallback
    events:
      started:
        webhook_url: https://discord.com/api/webhooks/BBB
      failure:
        webhook_url: https://discord.com/api/webhooks/CCC
```

`FAILURE_LOG_LINES` (default 10) controls how many trailing lines failures show.

## Distribution targets

| Target | Builds | Mechanism | Needs |
|--------|--------|-----------|-------|
| `firebase` | APK | `firebase appdistribution:distribute` (CLI auto-bootstrapped) | service-account JSON |
| `playstore` | AAB | Play Developer API, JWT signed with `curl`+`openssl` | service-account JSON, `jq` |
| `appstore` | IPA | `xcrun altool` (App Store Connect API key); Fastlane fallback | macOS + Xcode, `.p8` key |

## Jenkins (freestyle + Generic Webhook Trigger)

Keep every job's *Execute shell* to a fixed 3-line bootstrap that never changes;
all logic lives in [`ci/jenkins.sh`](ci/jenkins.sh) here, so updating CI for the
whole fleet is one commit. Per-job Execute shell:

```bash
set -e
TOOL="$HOME/.jenkins-tools/flutter-ci"
git -C "$TOOL" pull -q 2>/dev/null || git clone -q https://github.com/noersyden/jenkins-flutter-ci.git "$TOOL"
exec "$TOOL/ci/jenkins.sh"
```

`ci/jenkins.sh` reads env vars from Jenkins + the webhook payload (`BRANCH`,
`PLATFORM`, `DISTRIBUTION`, `FLAVOR`, `DRY_RUN`). The repo URL is fixed in the
job's SCM config; identity comes from the project's `.flutterci.yaml`. The JDK /
Flutter toolchain is configured at the Jenkins node or job level, not here.

## Layout

```
flutterci                 # entrypoint (orchestration + arg parsing)
ci/jenkins.sh             # reusable Jenkins freestyle runner
lib/
  log.sh                  # logging helpers
  config.sh               # yaml/env/flag resolution + yq bootstrap
  flutter_env.sh          # ANDROID_HOME/NDK/FVM + pubspec version
  build.sh                # flutter build + artifact path resolution
  dist_firebase.sh        # Firebase App Distribution
  dist_playstore.sh       # Google Play Developer API
  dist_appstore.sh        # App Store Connect / TestFlight
  notify.sh               # Discord webhook
examples/.flutterci.yaml  # per-project config template
jenkins/Jenkinsfile.example
```

## Dependencies

Always: `bash`, `curl`, `git`, Flutter (or FVM). Auto-bootstrapped on demand:
`yq`, `firebase` CLI. Play Store additionally needs `jq` + `openssl`; iOS needs
macOS + Xcode.

## Migrating an existing project

1. Add `.flutterci.yaml` (port `APP_NAME` + `FIREBASE_APP_ID` from the old `scripts/deploy_android.sh`).
2. Keep the existing service-account JSON path or point `credentials:` at it.
3. Replace the per-project script with a Jenkins job that calls `flutterci`.
4. Delete the old `scripts/deploy_android.sh` once parity is confirmed.
