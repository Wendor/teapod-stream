#!/usr/bin/env bash
# Usage: wait-review.sh <pr> [minutes, default 40]
# Waits until the PR is ready for your next step and prints that step. Ready means: the required checks finished,
# CodeRabbit reviewed the head commit, and every unresolved CodeRabbit thread someone replied to has its answer
# (a reply, or a 🚀 / 👍 reaction on the last comment: CodeRabbit accepts a reply that way) — or has gone unanswered for WAIT_REVIEW_IDLE minutes (default 10): CodeRabbit sometimes answers two threads in
# one of them and never comes back to the other, so waiting longer only burns time.
# Exit codes: 0 ready, 1 a check failed, 2 CodeRabbit skipped the head commit (ACCEPTED first when it already accepted
# every fix: then go straight to the approval), 3 timed out.
set -uo pipefail
n=${1:?usage: wait-review.sh <pr> [minutes]}
deadline=$(( $(date +%s) + ${2:-40} * 60 ))
repo=Wendor/teapod-stream
bot='coderabbitai[bot]'
idle=$(( ${WAIT_REVIEW_IDLE:-10} * 60 ))
# Every CodeRabbit review and rate limit this script sees, one line each, shared by all PRs and sessions on this
# machine: the hourly limit is per repository, so the log tells how many reviews the last hour spent.
log=${CODERABBIT_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/teapod-stream/coderabbit.log}
mkdir -p "$(dirname "$log")"
note() {  # note <ISO time> <key> [detail]: appends "<time> <key> [detail]" once per key
  grep -qF -- " $2" "$log" 2>/dev/null || echo "$1 $2${3:+ $3}" >> "$log"
}

threads() {  # unresolved threads, tab-separated: id, who started it, who spoke last, path, seconds since then,
             # whether CodeRabbit accepted the last comment with a reaction (1/0)
  # GraphQL names the bot "coderabbitai", REST "coderabbitai[bot]".
  gh api graphql --paginate -F n="$n" -f query='query($n:Int!,$endCursor:String){repository(owner:"Wendor",
    name:"teapod-stream"){pullRequest(number:$n){reviewThreads(first:100,after:$endCursor){nodes{id isResolved path
    first:comments(first:1){nodes{author{login}}} last:comments(last:1){nodes{author{login} createdAt
    rocket:reactions(first:100,content:ROCKET){nodes{user{login}}}
    thumbsUp:reactions(first:100,content:THUMBS_UP){nodes{user{login}}}}}}
    pageInfo{hasNextPage endCursor}}}}}' \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)
      | [.id, .first.nodes[0].author.login, .last.nodes[0].author.login, .path,
         (now - (.last.nodes[0].createdAt | fromdate) | floor),
         # Only 🚀 and 👍 are read (filtered by content, so other reactions cannot push them out of the page);
         # 👀 only means it is working on the thread. Reactions name the bot "coderabbitai[bot]".
         ([(.last.nodes[0].rocket.nodes + .last.nodes[0].thumbsUp.nodes)[]
           | select(.user.login == "coderabbitai[bot]" or .user.login == "coderabbitai")]
           | if length > 0 then 1 else 0 end)] | @tsv'
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
      # The usual case after a round of fixes: CodeRabbit already accepted every reply (🚀 / 👍) or resolved the
      # thread. Then its review of the fix commit adds nothing — don't wait out a rate limit for it.
      total=$(gh api graphql -F n="$n" -f query='query($n:Int!){repository(owner:"Wendor",name:"teapod-stream"){
        pullRequest(number:$n){reviewThreads(first:100){nodes{comments(first:1){nodes{author{login}}}}}}}}' \
        --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.comments.nodes[0].author.login == "coderabbitai")]
          | length' 2>/dev/null || echo "")
      if open=$(threads) && [ -n "$total" ] && [ "$total" -gt 0 ]; then
        pending=$(awk -F'\t' '$2 == "coderabbitai" && $6 != 1' <<< "$open" | sed '/^$/d' | wc -l | tr -d ' ')
        if [ "$pending" = 0 ]; then
          accepted=$(awk -F'\t' '$2 == "coderabbitai" && $6 == 1' <<< "$open" | cut -f1,4 | sed '/^$/d')
          echo "ACCEPTED: every CodeRabbit thread ($total) is resolved or its last reply has CodeRabbit's 🚀 / 👍."
          if [ -n "$accepted" ]; then
            echo "Resolve these accepted threads first:"
            sed 's/^/  /' <<< "$accepted"
          fi
          echo "Next: don't wait for its review of ${head:0:7} and don't post '@coderabbitai review' — check that"
          echo "nothing else is left (review bodies: outside-diff, nitpicks), then ask for the approval review and merge."
          exit 2
        fi
      fi
      # A rate limit names its wait ("Please wait **12 minutes and 5 seconds** ...") in the comment it last updated:
      # the time it accepts a request again is that update plus the wait.
      retry=$(gh api --paginate "repos/$repo/issues/$n/comments" --jq '.[]
        | select(.user.login == "coderabbitai[bot]" and (.body | test("rate limit"; "i")))
        | (.body | capture("wait \\*\\*(?<w>[^*]+)\\*\\*").w) as $w
        | (.updated_at | fromdate) + ([$w | scan("([0-9]+) *(hour|minute|second)")
          | (.[0] | tonumber) * {"hour": 3600, "minute": 60, "second": 1}[.[1]]] | add // 0)' 2>/dev/null \
        | sort -n | tail -1)
      spent=$(awk -v s="$(jq -rn 'now - 3600 | todate')" '$1 >= s && $3 == "reviewed"' "$log" | wc -l | tr -d ' ')
      if [ -n "$retry" ] && [ "$retry" -gt "$(date +%s)" ]; then
        note "$(jq -rn 'now | todate')" "pr=$n rate-limited $head" "retry=$(jq -rn "$retry | todate")"
        echo "Rate limited: CodeRabbit takes '@coderabbitai review' again at $(jq -rn "$retry | strflocaltime(\"%H:%M:%S\")")" \
          "(in $(( (retry - $(date +%s) + 59) / 60 )) min); reviews logged in the last hour: $spent ($log)."
        echo "Next: sleep $(( retry - $(date +%s) + 30 )), then post '@coderabbitai review' (with your Co-Authored-By"
        echo "line) and run this script again — it waits for that review to start."
      else
        [ -n "$retry" ] && echo "Its last rate limit ended at $(jq -rn "$retry | strflocaltime(\"%H:%M:%S\")")."
        echo "Next: read its latest comment on the PR. Rate limit or \"Reviews paused\" → post '@coderabbitai review'"
        echo "(with your Co-Authored-By line) and run this script again — it waits for that review to start."
      fi
      exit 2
    fi
    reviewed_at=$(jq -r '.[] | select(.name == "CodeRabbit") | .completedAt // empty' <<< "$checks" | head -1)
    note "${reviewed_at:-$(jq -rn 'now | todate')}" "pr=$n reviewed $head"
    # CodeRabbit posts a reply only when it is complete (the "Analysis chain" block is part of the final reply),
    # so a thread is answered when its last comment is CodeRabbit's.
    # A thread waits for CodeRabbit when CodeRabbit started it and someone else spoke last; threads people started
    # are theirs to answer.
    if open=$(threads); then
      replied='$2 == "coderabbitai" && $3 != "coderabbitai"'
      waiting=$(awk -F'\t' -v idle="$idle" "$replied"' && $6 == 0 && $5 < idle' <<< "$open" | sed '/^$/d')
      silent=$(awk -F'\t' -v idle="$idle" "$replied"' && $6 == 0 && $5 >= idle' <<< "$open" | cut -f1,4 | sed '/^$/d')
      accepted=$(awk -F'\t' "$replied"' && $6 == 1' <<< "$open" | cut -f1,4 | sed '/^$/d')
    else
      silent=""
      accepted=""
      waiting="(the thread query failed; retrying)"  # never READY on data we couldn't read
    fi
    # A push between the reads above and now makes them stale.
    if [ -z "$waiting" ] && [ "$(gh pr view "$n" --json headRefOid --jq .headRefOid)" = "$head" ]; then
      echo "READY: CodeRabbit reviewed ${head:0:7}; checks passed."
      if [ -n "$open" ]; then
        echo "Unresolved threads (id, started by, last comment by, path, seconds since, accepted by reaction):"
        sed 's/^/  /' <<< "$open"
      fi
      if [ -n "$accepted" ]; then
        echo "CodeRabbit accepted your reply with a reaction (resolve these threads):"
        sed 's/^/  /' <<< "$accepted"
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
