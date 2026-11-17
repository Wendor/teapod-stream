# Contributing to TeapodStream

Thanks for helping. These rules keep pull requests reviewable — whether you write the code yourself or with an AI
agent. Agents also read [AGENTS.md](AGENTS.md).

## Before you start

- **Bugs:** open an issue with the bug template first, unless the fix is small and obvious.
- **Features, new protocols, new cores, UI redesigns:** open an issue and wait for a maintainer to agree on the
  approach. A large PR nobody asked for will be closed, however good it is.
- **Work for an AI agent:** the *Agent task* issue template — goal, scope, how to split it into PRs, when it is done.
- **Security problems:** don't open a public issue — use
  [private vulnerability reporting](https://github.com/Wendor/teapod-stream/security/advisories/new).

## Setup

Flutter (the version in `.github/workflows/ci.yml`), JDK 21, Android SDK with NDK `28.2.13676358`, a device or
emulator on Android 10+ (arm64-v8a or x86_64). Changing `core/` (the Go engines) also needs Go and gomobile —
`core/README.md`.

```bash
./build.sh binaries   # teapod-core AAR for core/ + geodata (not stored in git; downloaded when core/ matches a release)
./build.sh run        # debug build on the device
```

How the app is built inside: [`wiki/index.md`](wiki/index.md).

## Rules for a pull request

1. **One topic.** One fix or one feature per PR. Refactoring, formatting and drive-by fixes go into their own PRs.
2. **Keep it small.** Aim for under ~500 changed lines, excluding generated files and translations. Bigger needs
   the maintainer's agreement in the issue first; CI flags large PRs.
3. **Don't touch release machinery:** the `version:` in `pubspec.yaml`, `build.sh`, `core/build.sh`, `.github/`, signing config,
   `android/app/libs/`. CI fails a PR from a fork that changes them.
4. **No new dependencies** without agreement in the issue.
5. **Tests.** A fix or a logic change comes with a test that fails without it. Native code (VpnService, cores, TUN,
   kill switch, reconnect) can't be unit-tested: test it on a device and say how.
6. **Strings.** Everything the user sees goes through `lib/l10n/app_en.arb` **and** `app_ru.arb` (native:
   `values/strings.xml` and `values-ru/strings.xml`). Code, comments and logs are in English.
7. **Wiki.** If your change makes a page in `wiki/` wrong, fix the page in the same PR.
8. **Checks pass.** Run them locally before pushing:

   ```bash
   dart format --output=none --set-exit-if-changed lib test tool
   flutter analyze
   flutter test
   cd android && ./gradlew :app:testDebugUnitTest
   ```

9. **No secrets.** No server URIs, subscription links, keys, UUIDs or unmasked logs in code, tests, screenshots or
   the PR description.

## Using AI

AI tools are welcome. The rules don't change:

- **You own every line.** You have read the whole diff, you understand it and you can answer review questions
  without asking the AI again.
- **Say so:** tick the *AI was used* box in the PR template. A PR or issue an agent opened has `[ai] ` in front of
  its title. Commits an agent wrote carry a trailer naming it (`Co-Authored-By: <agent> <email>`), and comments an
  agent posts end with the same line.
- **The description is about the change, not the process.** Short, specific, verified — no generated essays,
  no claims you haven't checked ("tested on a device" means you did).
- Point your agent at [AGENTS.md](AGENTS.md); Claude Code reads it through `CLAUDE.md`.

## Commits and the PR

- Commit messages and the PR title: `area: what changed`, e.g. `vpn: keep the kill switch sink during reconnect`.
  Areas: `vpn`, `xray`, `singbox`, `rust`, `ui`, `l10n`, `config`, `routing`, `itest`, `ci`, `wiki`, `build`.
- Fill in every section of the [template](.github/pull_request_template.md). CI checks that the sections are there
  and not left as placeholders.
- Open the PR as a draft while you are still working; mark it ready when the checks pass and every box is honest.
- After review changes, push new commits (don't force-push over reviewed code) and keep the description current.

## Review

[CodeRabbit](https://coderabbit.ai) reviews every PR automatically once it is out of draft. Answer each of its
comments — fix it, or reply why it doesn't apply — and resolve the thread once it is settled: GitHub won't merge a
PR with an open conversation. Then the maintainer (or the maintainer's review bot) reviews; a push after the approval
needs a new one. Expect questions about *why*, about the device test, and requests to split large PRs. PRs that ignore these rules may be closed with a pointer to this file — you're welcome to reopen once
they're addressed.

## License

By contributing you agree that your work is licensed under the [MIT License](LICENSE).
