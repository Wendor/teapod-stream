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

## `release.yml` — release

Manual (`workflow_dispatch`): Actions → Release → Run workflow, or
`gh workflow run release.yml --ref <branch> [-f prerelease=false]` (`prerelease` defaults to `true`).

Order: version from `pubspec.yaml` → signing key → JDK, NDK → teapod-core AAR (the action: cache or build) →
`./build.sh binaries` (geodata) → `./build.sh release` → signature check → `./build.sh push|pushpre` (APKs **and**
`teapod-core-<core/ hash>.aar`, which `./build.sh binaries` downloads elsewhere) → obfuscation symbols as artifact
`symbols-<version>`.

### Release notes

Written in `changelog/` **before** the release, one file per language: `en.md`, `ru.md`. The H1 is the language's own
name (`# English`, `# Русский`), then `## X.Y.Z` per version, newest first, `- ` bullets only: what a user notices,
issue numbers like `(#76)`.

`./build.sh notes [X.Y.Z]` prints the release body for a version (default: the `pubspec.yaml` one): for each file,
English first, `### <its H1>` and the bullets of its `## X.Y.Z` section. `./build.sh push|pushpre` creates the release
with this body and stops before publishing when a file has no section for the version.

`build.sh` takes `JAVA_HOME` / `ANDROID_HOME` from the environment (Homebrew paths by default). `core/build.sh` uses
`$ANDROID_HOME/ndk/$NDK_VERSION` (default 28.2.13676358; the workflows pass the same `NDK_VERSION`).

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
