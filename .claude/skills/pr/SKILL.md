---
name: pr
description: Use when opening or updating a pull request in teapodstream — runs the CI checks locally, fills the PR template honestly and keeps the description current.
---

# Opening or updating a pull request

Rules: [CONTRIBUTING.md](../../../CONTRIBUTING.md). Template: [.github/pull_request_template.md](../../../.github/pull_request_template.md).

## Before opening

1. `git diff master...HEAD --stat`: one topic? Unrelated hunks → move them to another branch. Over ~500 lines
   (without `lib/l10n/`) → split, or the issue must already agree on the size.
2. Nothing from the hands-off list in AGENTS.md changed (version, `build.sh`, `.github/`, signing, `android/app/libs/`)
   unless that is the task.
3. Run every check and read the output — don't assume:
   ```bash
   dart format --output=none --set-exit-if-changed lib test tool
   flutter analyze && flutter test
   (cd android && ./gradlew :app:testDebugUnitTest)
   ```
4. Wiki pages for the touched area still true? Fix them in this branch.
5. Grep the diff for secrets: `git diff master...HEAD | grep -nE 'vless://|vmess://|trojan://|ss://|hy2://|[0-9a-f]{8}-[0-9a-f]{4}-'`.

## The description

- **Why:** the user-visible problem, one or two sentences; `Fixes #N` / `See #N`.
- **What changed:** summary, then `- area: change (file, function)` for what a reviewer should read first.
- **Testing:** list only what was actually run. You can't run a device: write native/VPN behaviour under
  **Not tested** and ask the person you work for to run it — never claim a device test you didn't see.
- **Risks:** connection, kill switch, reconnect, stored data migration; "None" only after checking.
- Tick a box only when it is true. Keep the *AI was used* box.
- End the description and every comment or review reply you post with `Co-Authored-By: <agent> <email>`;
  commits you make carry it as a trailer.
- No placeholders left (`<…>`): the `PR rules` workflow fails on them.

## Open and update

```bash
gh pr create --draft --base master --title "[ai] area: what changed" --body-file <filled template>
gh pr ready <n>            # when checks pass and the description is complete; at most 3 of yours out of draft
gh pr edit <n> --body-file <updated description>   # after every push that changes what the PR does
```

The description states the PR as it is now; review history stays in the comments.

## CodeRabbit

It reviews when the PR leaves draft and again after each push. It is rate-limited: when its comment says the review
was not completed or skipped, the `CodeRabbit` check is still green — post `@coderabbitai review` and wait.

```bash
gh pr checks <n> --watch                       # wait until the CodeRabbit check finishes
gh api repos/Wendor/teapod-stream/pulls/<n>/comments --jq '.[] | select(.user.login|test("coderabbit")) | {id, path, line, body}'
gh api repos/Wendor/teapod-stream/pulls/<n>/reviews --jq '.[] | select(.user.login|test("coderabbit")) | .body'
                                               # every review body: outside-diff and nitpick items live only here
```

For each comment: check it against the code and the wiki. Valid → fix in a new commit. Wrong or out of scope →
reply on the thread with the reason (`gh api repos/Wendor/teapod-stream/pulls/<n>/comments/<id>/replies -f body=...`).
Never apply a suggestion you haven't verified; never leave one unanswered. Repeat after its re-review.
Outside-diff and nitpick items from review bodies: fix them, or answer them in one PR comment.

Resolve a thread when it is fixed, or when CodeRabbit replied that it accepts your reason. If it still disagrees,
leave the thread open and say so in a PR comment: the maintainer decides. GitHub won't merge while a thread is open.

```bash
gh api graphql --paginate -F n=<n> -f query='query($n:Int!,$endCursor:String){repository(owner:"Wendor",
  name:"teapod-stream"){pullRequest(number:$n){reviewThreads(first:100,after:$endCursor){
  nodes{id isResolved path comments(last:1){nodes{author{login} body}}} pageInfo{hasNextPage endCursor}}}}}'
gh api graphql -F id=<thread id> -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
```

## Approval

A maintainer or the reviewer bot approves the latest commit. Any push after that dismisses the approval: finish all
fixes first, then ask for the review once.
