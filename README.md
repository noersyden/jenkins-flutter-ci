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

## Distribution targets

| Target | Builds | Mechanism | Needs |
|--------|--------|-----------|-------|
| `firebase` | APK | `firebase appdistribution:distribute` (CLI auto-bootstrapped) | service-account JSON |
| `playstore` | AAB | Play Developer API, JWT signed with `curl`+`openssl` | service-account JSON, `jq` |
| `appstore` | IPA | `xcrun altool` (App Store Connect API key); Fastlane fallback | macOS + Xcode, `.p8` key |

## Layout

```
flutterci                 # entrypoint (orchestration + arg parsing)
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
