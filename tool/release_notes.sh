#!/bin/bash
# Prints the GitHub release body for a version, built from changelog/<lang>.md:
# every file's "## X.Y.Z" section becomes "### <the file's H1>" + its bullets, English first.
# Fails when a file has no H1 or no section for the version.
#
#   tool/release_notes.sh 1.8.0
set -euo pipefail

version="${1:-}"
[[ -n "$version" ]] || { echo "Usage: tool/release_notes.sh X.Y.Z" >&2; exit 2; }

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/changelog"
[[ -f "$dir/en.md" ]] || { echo "changelog/en.md not found" >&2; exit 1; }

files=("$dir/en.md")
for f in "$dir"/*.md; do
  [[ "$f" == "$dir/en.md" ]] || files+=("$f")
done

body=""
for f in "${files[@]}"; do
  rel="changelog/$(basename "$f")"
  name=$(awk '/^# /{ sub(/^# +/, ""); sub(/[ \t]+$/, ""); print; exit }' "$f")
  [[ -n "$name" ]] || { echo "$rel has no '# <language>' heading" >&2; exit 1; }
  # Non-empty lines between "## <version>" and the next heading of level 1 or 2.
  section=$(awk -v v="$version" '
    /^##? / { h = $0; sub(/^##? +/, "", h); sub(/[ \t]+$/, "", h); on = ($0 ~ /^## / && h == v); next }
    on && NF { print }
  ' "$f")
  [[ -n "$section" ]] || { echo "$rel has no '## $version' section" >&2; exit 1; }
  [[ -z "$body" ]] || body+=$'\n\n'
  body+="### $name"$'\n'"$section"
done
# Nothing is printed unless every language has the section.
printf '%s\n' "$body"
