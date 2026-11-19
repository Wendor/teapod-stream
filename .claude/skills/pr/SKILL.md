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
gh pr ready <n>            # when checks pass and the description is complete; at most 3 in the repo out of draft (`gh pr list --search draft:false`)
gh pr edit <n> --body-file <updated description>   # after every push that changes what the PR does
```

The description states the PR as it is now; review history stays in the comments.

## The review loop

Don't write your own polling: [`scripts/wait-review.sh <n>`](scripts/wait-review.sh) waits (up to 40 minutes) and
says what to do next. Run it after `gh pr ready`, after every push and after every batch of thread replies.

| Result | Meaning | Next |
|---|---|---|
| `READY` (0) | Checks passed, CodeRabbit reviewed the head commit, every thread you replied to has its answer or got none for `WAIT_REVIEW_IDLE` minutes (default 10; listed separately — it may have answered in a sibling thread) | Read and act (below), then run the script again — or ask for approval when nothing is left |
| `FAILED` (1) | A required check failed | Read the log, fix, push, run again |
| `SKIPPED` (2) | CodeRabbit finished without reviewing the head (rate limit, "Reviews paused" after many pushes, or a push with nothing to review) | Rate limit or paused: post `@coderabbitai review`, run again — a request newer than CodeRabbit's last result counts as pending, so the script waits for that review. Nothing to review (e.g. only a merge from `master`): its previous review stands |
| `TIMEOUT` (3) | Something is still pending after 40 minutes | Tell the person you work for what is stuck |

How it knows, if you need to check by hand:

- **Reviewed commit:** `coveredCommitId` in CodeRabbit's summary comment on the PR. The green `CodeRabbit` check,
  its review list and empty reviews from its thread replies don't tell which commit it reviewed.
- **Thread answered:** the thread's last comment is CodeRabbit's. It posts a reply only when it's complete; the
  collapsed "Analysis chain" at its top is part of the final answer, not a draft.

On `READY`, read everything new:

```bash
gh api --paginate repos/Wendor/teapod-stream/pulls/<n>/comments --jq '.[] | select(.user.login=="coderabbitai[bot]") | {id, in_reply_to_id, path, line, body}'
gh api --paginate repos/Wendor/teapod-stream/pulls/<n>/reviews --jq '.[] | select(.user.login=="coderabbitai[bot]") | {commit_id, body}'
                                               # outside-diff and nitpick items live only in review bodies
```

For each comment: check it against the code and the wiki. Valid → fix in a new commit. Wrong or out of scope →
reply on the thread with the reason (`gh api repos/Wendor/teapod-stream/pulls/<n>/comments/<id>/replies -f body=...`).
Never apply a suggestion you haven't verified; never leave one unanswered. Collect all fixes of a round into one
push: every push costs a review from the hourly limit.
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

Ask for it when the script says `READY` — or `SKIPPED` because the last push had nothing to review (only a merge
from `master`; CodeRabbit's comment says so, never after a rate limit) — and nothing is left: every finding fixed or answered, fixed and accepted
threads resolved, disputed ones left open with a PR comment. A maintainer or the reviewer bot approves the latest
commit; any push after that dismisses the approval, so ask once, after the last push. Waiting for CodeRabbit to
come round on a thread it still disputes is not a reason to hold the approval request.
