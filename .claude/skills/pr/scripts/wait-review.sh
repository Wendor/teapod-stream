#!/usr/bin/env bash
# Usage: wait-review.sh <pr> [minutes, default 40]
# Waits until the PR is ready for your next step and prints that step. Ready means: the required checks finished,
# CodeRabbit reviewed the head commit, and every unresolved CodeRabbit thread someone replied to has its answer —
# or has gone unanswered for WAIT_REVIEW_IDLE minutes (default 10): CodeRabbit sometimes answers two threads in
# one of them and never comes back to the other, so waiting longer only burns time.
# Exit codes: 0 ready, 1 a check failed, 2 CodeRabbit skipped the head commit, 3 timed out.
set -uo pipefail
n=${1:?usage: wait-review.sh <pr> [minutes]}
deadline=$(( $(date +%s) + ${2:-40} * 60 ))
repo=Wendor/teapod-stream
bot='coderabbitai[bot]'
idle=$(( ${WAIT_REVIEW_IDLE:-10} * 60 ))

threads() {  # unresolved threads, tab-separated: id, who started it, who spoke last, path, seconds since then
  # GraphQL names the bot "coderabbitai", REST "coderabbitai[bot]".
  gh api graphql --paginate -F n="$n" -f query='query($n:Int!,$endCursor:String){repository(owner:"Wendor",
    name:"teapod-stream"){pullRequest(number:$n){reviewThreads(first:100,after:$endCursor){nodes{id isResolved path
    first:comments(first:1){nodes{author{login}}} last:comments(last:1){nodes{author{login} createdAt}}}
    pageInfo{hasNextPage endCursor}}}}}' \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)
      | [.id, .first.nodes[0].author.login, .last.nodes[0].author.login, .path,
         (now - (.last.nodes[0].createdAt | fromdate) | floor)] | @tsv'
}

while :; do
  head=$(gh pr view "$n" --json headRefOid --jq .headRefOid || true)
  checks=$(gh pr checks "$n" --json name,bucket,completedAt 2>/dev/null || echo '[]')
  failed=$(jq -r '[.[] | select(.bucket == "fail" or .bucket == "cancel") | .name] | join(", ")' <<< "$checks")
  if [ -n "$failed" ]; then
    echo "FAILED: $failed"
    echo "Next: read the logs (gh pr checks $n), fix and push, then run this script again."
    exit 1
  fi
  running=$(jq '[.[] | select(.bucket == "pending")] | length' <<< "$checks")
  coderabbit=$(jq -r '.[] | select(.name == "CodeRabbit") | .bucket' <<< "$checks")
  # The commit CodeRabbit last reviewed: its summary comment records it. A clean review posts no review body, and
  # its thread replies post empty reviews, so the reviews list can't tell.
  # A failed request leaves `covered` unknown: nothing is decided on it, the deadline check still runs.
  if bodies=$(gh api --paginate "repos/$repo/issues/$n/comments" --jq ".[] | select(.user.login == \"$bot\") | .body"); then
    covered=$(grep -oE '"coveredCommitId":"[0-9a-f]{40}"' <<< "$bodies" | tail -1 | cut -d'"' -f4)
  else
    covered=unknown
  fi
  # After '@coderabbitai review' the CodeRabbit check keeps its old result (paused, rate limited) until the
  # requested review starts: while the head isn't covered, a request newer than that result is still pending.
  # A failed lookup counts as pending too — never SKIPPED or READY on data we couldn't read.
  if [ -n "$head" ] && [ "$covered" != "$head" ]; then
    finished=$(jq -r '.[] | select(.name == "CodeRabbit") | .completedAt // ""' <<< "$checks")
    if requested=$(gh api --paginate "repos/$repo/issues/$n/comments" \
      --jq ".[] | select(.user.login != \"$bot\" and (.body | startswith(\"@coderabbitai review\"))) | .created_at"); then
      requested=$(tail -1 <<< "$requested")
      if [ -n "$requested" ] && [ -n "$finished" ] && [[ "$requested" > "$finished" ]]; then
        running=$(( running + 1 ))
      fi
    else
      running=$(( running + 1 ))
    fi
  fi

  if [ -n "$head" ] && [ "$covered" != unknown ] && [ "$running" = 0 ] && [ -n "$coderabbit" ]; then
    if [ "$covered" != "$head" ]; then
      echo "SKIPPED: CodeRabbit finished without reviewing ${head:0:7} (rate limit, paused reviews, or nothing to review)."
      echo "Next: read its latest comment on the PR. Rate limit or \"Reviews paused\" → post '@coderabbitai review'"
      echo "(with your Co-Authored-By line) and run this script again — it waits for that review to start; a rate"
      echo "limit can take until the hourly limit resets."
      exit 2
    fi
    # CodeRabbit posts a reply only when it is complete (the "Analysis chain" block is part of the final reply),
    # so a thread is answered when its last comment is CodeRabbit's.
    # A thread waits for CodeRabbit when CodeRabbit started it and someone else spoke last; threads people started
    # are theirs to answer.
    if open=$(threads); then
      waiting=$(awk -F'\t' -v idle="$idle" '$2 == "coderabbitai" && $3 != "coderabbitai" && $5 < idle' <<< "$open" \
        | sed '/^$/d')
      silent=$(awk -F'\t' -v idle="$idle" '$2 == "coderabbitai" && $3 != "coderabbitai" && $5 >= idle' <<< "$open" \
        | cut -f1,4 | sed '/^$/d')
    else
      silent=""
      waiting="(the thread query failed; retrying)"  # never READY on data we couldn't read
    fi
    # A push between the reads above and now makes them stale.
    if [ -z "$waiting" ] && [ "$(gh pr view "$n" --json headRefOid --jq .headRefOid)" = "$head" ]; then
      echo "READY: CodeRabbit reviewed ${head:0:7}; checks passed."
      if [ -n "$open" ]; then
        echo "Unresolved threads (id, started by, last comment by, path, seconds since):"
        sed 's/^/  /' <<< "$open"
      fi
      if [ -n "$silent" ]; then
        echo "No answer from CodeRabbit for $(( idle / 60 ))+ min (check whether it answered in a sibling thread):"
        sed 's/^/  /' <<< "$silent"
      fi
      gh api --paginate "repos/$repo/pulls/$n/reviews" \
        --jq ".[] | select(.user.login == \"$bot\" and .commit_id == \"$head\") | .body" \
        | grep -E 'Actionable comments posted|Outside diff range comments|Nitpick comments' | sed 's/<[^>]*>//g; s/^/  /'
      echo "Next: read every new comment, thread reply and review body (the pr skill). Then:"
      echo "  fixed something  → push, update the description if needed, run this script again;"
      echo "  replied only     → run this script again to wait for CodeRabbit's answers;"
      echo "  nothing left     → resolve fixed or accepted threads, leave disputed ones open with a PR comment,"
      echo "                     and ask for the approval review."
      exit 0
    fi
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT: head ${head:0:7}; checks running: $running; CodeRabbit check: ${coderabbit:-none};"
    echo "reviewed commit: ${covered:0:7}; threads waiting for CodeRabbit's answer:"
    sed 's/^/  /' <<< "${waiting:-}"
    echo "Next: tell the person you work for what is stuck; don't wait silently."
    exit 3
  fi
  sleep 30
done
