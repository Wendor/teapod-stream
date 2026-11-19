# CI/CD (GitHub Actions)

Workflows: `.github/workflows/`; the shared step that provides the teapod-core AAR: `.github/actions/teapod-core`
(restore from the Actions cache by the `core/` tree hash, or build with Go, gomobile and the NDK on a miss).

## `ci.yml` — checks

On push to `master` and on pull requests (not on every branch push: with an open PR that ran everything twice).

| Job | Steps |
|---|---|
| `dart` | `flutter gen-l10n` + `git diff --exit-code lib/l10n` (generated files match the ARB), `dart format --set-exit-if-changed lib test tool`, `flutter analyze`, `flutter test` |
| `kotlin` | JDK 21 → teapod-core AAR (the action above; built only on a cache miss, i.e. the first run for a `core/` tree) → `flutter build apk --debug --config-only` → `./gradlew :app:testDebugUnitTest` |
| `core` | `core/build.sh prepare` (patched xray-core), `go vet ./...`, `go test ./...` in `core/`, plus the tests the xray-core patches add |

`assets/binaries/` is created empty: it is declared in pubspec, tests don't need geodata.

## `pr.yml` — PR rules

`pull_request_target`: the workflow file comes from the base branch and the PR's code is never checked out, so a PR
can't change its own checks; it only reads the title, the description and the changed-file list through the API.
Skipped for drafts.

- title `area: what changed`, or `[ai] area: what changed` for a PR an agent opened; an `[ai]` title needs the
  *AI was used* box ticked, and a description signed `Co-Authored-By:` needs the `[ai]` title;
- the template's `## Why`, `## What changed`, `## Testing`, `## Risks` present and no placeholders left;
- `.github/`, `build.sh`, `core/build.sh`, `android/app/libs/` or the `version:` line of `pubspec.yaml` changed → problem;
- more than 500 changed lines (without `lib/l10n/`, `pubspec.lock`, `test/fixtures/`) → warning.

Problems fail the check for contributors and are warnings for owners/members/collaborators.

## Branch protection (`master`)

Required checks `dart`, `kotlin`, `core` and `rules`; one approving review from anyone with write access (the maintainer
or the `wendor-ai-reviewer` GitHub App) that covers the latest push — a push that changes the diff dismisses earlier
approvals, and the author of the last push can't approve it; every review conversation resolved; no force pushes or
deletion; the rules apply to admins too. `.github/CODEOWNERS` asks for the maintainer's review on every change, and GitHub requests it automatically, but
branch protection doesn't enforce it: an approval from the `wendor-ai-reviewer` app is enough to merge.

CodeRabbit (`.coderabbit.yaml`) reviews every non-draft PR; its guidelines are `AGENTS.md` and `CONTRIBUTING.md`.

## `updates.yml` — monthly update check

On the 1st of every month (and by hand). `.github/scripts/check-updates.sh` compares what the build pins with the
latest upstream releases: xray-core (a release newer than the pinned commit), sing-box and xray-rust-mobile, the
bundled geodata (`GEODATA_VERSION` in `build.sh`), Go,
Flutter, AGP, Kotlin, Gradle, the direct Go modules of `core/` and the direct Dart packages. If anything is behind,
it opens the issue `[ai] deps: monthly update check` (labels `ai`, `dependencies`), written as an *Agent task* with a
table of versions, or rewrites the body of the one already open. The maintainer hands it to an agent; closing the
issue lets the next run open a new one. The script runs locally the same way (needs `gh`, `go`, `flutter`, and
`core/build.sh prepare` first).

## `release.yml` — release

Manual (`workflow_dispatch`): Actions → Release → Run workflow, or
`gh workflow run release.yml --ref <branch> [-f prerelease=false]` (`prerelease` defaults to `true`).

Two jobs. `apk` runs once per ABI in parallel (matrix `arm64-v8a`, `x86_64`): signing key → JDK, NDK → teapod-core
AAR (the action: cache or build) → `./build.sh binaries` (the pinned geodata) → `TARGET_PLATFORMS=<platform> ./build.sh release`
→ signature check → artifact `build-<abi>` (the APK and its obfuscation symbols); the arm64 job also uploads the AAR as
artifact `teapod-core`. `publish` then downloads the three artifacts by name, runs `./build.sh push|pushpre` (APKs **and**
`teapod-core-<core/ hash>.aar`, which `./build.sh binaries` downloads elsewhere) and uploads the symbols of both ABIs
as artifact `symbols-<version>`. The APKs reach the release only through `publish`, so a failed ABI publishes nothing.

### Release notes

Written in `changelog/` **before** the release, one file per language: `en.md`, `ru.md`. The H1 is the language's own
name (`# English`, `# Русский`), then `## X.Y.Z` per version, newest first, `- ` bullets only: what a user notices,
issue numbers like `(#76)`. Versions before 1.7.0 are summaries per minor version (`## 1.6`, `## 1.0–1.2`).

`./build.sh notes [X.Y.Z]` prints the release body for a version (default: the `pubspec.yaml` one): for each file,
English first, `### <its H1>` and the bullets of its `## X.Y.Z` section. `./build.sh push|pushpre` creates the release
with this body and stops before publishing when a file has no section for the version.

The app shows the section of its language from the release body ([UpdateService](services.md#updateservice)) and
bundles `changelog/` as an asset for Settings → about → changelog. A language is added with its file and an entry in
`releaseNotesLanguages` (`update_service.dart`); `test/core/changelog_test.dart` checks that the files, their H1s
and the map match and that every file has the same versions.

`build.sh` takes `JAVA_HOME` / `ANDROID_HOME` from the environment (Homebrew paths by default). `core/build.sh` uses
`$ANDROID_HOME/ndk/$NDK_VERSION` (default 30.0.16248370; the workflows pass the same `NDK_VERSION`). The version is
one the `ubuntu-latest` runner image ships, so the workflows' NDK steps install nothing; moving it to a version the
image lacks costs ~30 s per job.

## Signing

Releases are signed with the **debug key** (`signingConfigs.debug` in `android/app/build.gradle.kts`): every published
APK has it, and another key would break updates over installed versions. On CI the key is restored from a secret into
`~/.android/debug.keystore` with `ANDROID_USER_HOME=~/.android` (otherwise AGP on the runner silently generates a new
key); its fingerprint is checked right after decoding, and "Verify signature" checks every APK (`apksigner`) against
`CERT_SHA256` before publishing.

## Secrets

| Secret | What | How |
|---|---|---|
| `DEBUG_KEYSTORE_BASE64` | `~/.android/debug.keystore` in base64 | `base64 -i ~/.android/debug.keystore \| gh secret set DEBUG_KEYSTORE_BASE64 -R Wendor/teapod-stream` |

It is checked at the start of the job, before the long build.
