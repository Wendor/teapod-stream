# CI/CD (GitHub Actions)

Workflows live only in this repository (`.github/workflows/`); teapod-core and teapod-tun2socks are built by this
repo's release workflow.

## `ci.yml` — checks

On push to `master` and on pull requests (not on every branch push: with an open PR that ran everything twice).

| Job | Steps |
|---|---|
| `dart` | `flutter gen-l10n` + `git diff --exit-code lib/l10n` (generated files match the ARB), `dart format --set-exit-if-changed` (tracked `.dart` without generated l10n), `flutter analyze`, `flutter test` |
| `kotlin` | downloads `teapod-core-<pubspec version>.aar` from the `Wendor/teapod-core` release; if it isn't released yet (a branch right after a bump) the job is skipped with a warning. Then JDK 21, NDK, `flutter build apk --debug --config-only`, `./gradlew :app:testDebugUnitTest` |

`assets/binaries/` is created empty: it is declared in pubspec, tests don't need geodata.

## `pr.yml` — PR rules

`pull_request_target`: the workflow file comes from the base branch and the PR's code is never checked out, so a PR
can't change its own checks; it only reads the title, the description and the changed-file list through the API.
Skipped for drafts.

- title `area: what changed`;
- the template's `## Why`, `## What changed`, `## Testing`, `## Risks` present and no placeholders left;
- `.github/`, `build.sh`, `android/app/libs/` or the `version:` line of `pubspec.yaml` changed → problem;
- more than 500 changed lines (without `lib/l10n/`, `pubspec.lock`, `test/fixtures/`) → warning.

Problems fail the check for contributors and are warnings for owners/members/collaborators.

## Branch protection (`master`)

Required checks `dart` and `kotlin`, one approving review from a code owner (`.github/CODEOWNERS`), no force pushes or
deletion; admins can bypass. Add `rules` to the required checks once `pr.yml` is on `master`.

CodeRabbit (`.coderabbit.yaml`) reviews every non-draft PR; its guidelines are `AGENTS.md` and `CONTRIBUTING.md`.

## `release.yml` — releasing the whole chain

Manual (`workflow_dispatch`): Actions → Release → Run workflow, or
`gh workflow run release.yml --ref <branch> [-f prerelease=false]`.

| Input | Default | Meaning |
|---|---|---|
| `prerelease` | `true` | `pushpre` instead of `push` (core and app) |
| `rebuild_core` | `false` | build the core even if its `v<version>` release exists (assets replaced) |
| `core_ref`, `tun2socks_ref` | empty | sibling branch; empty = same name as this branch if it exists, else the default branch |

Order: version from `pubspec.yaml` → if `Wendor/teapod-core` has no `v<version>` release: check out teapod-core and
teapod-tun2socks **next to** this repo (the relative paths work as locally), Go from `go.mod`, gomobile/gobind of the
`golang.org/x/mobile` version in `go.mod`, `teapod-core/build.sh build` + `push|pushpre` → `./build.sh binaries` →
`./build.sh release` → signature check → `./build.sh push|pushpre` → obfuscation symbols as artifact
`symbols-<version>`.

Both `build.sh` scripts take `JAVA_HOME` / `ANDROID_HOME` from the environment (Homebrew paths by default); the NDK is
always `$ANDROID_HOME/ndk/28.2.13676358`.

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
| `CORE_RELEASE_TOKEN` | fine-grained PAT for `Wendor/teapod-core`, Contents read/write | the workflow token can't publish releases in another repo; needed only when the core is built |

Both are checked at the start of the job, before the long build.
