#!/usr/bin/env bash
# Compares what the build pins with the latest upstream releases and prints an "Agent task" issue body in Markdown.
# Prints nothing when everything is current. Needs gh (GH_TOKEN), jq, curl, go, flutter; run from the repo root.
# Used by .github/workflows/updates.yml; can be run locally the same way.
set -euo pipefail

rows=()   # "| what | pinned | latest | where |"
items=()  # work items
add() { rows+=("| $1 | \`$2\` | \`$3\` | $4 |"); items+=("- [ ] $1: \`$2\` → \`$3\`"); }
latest_tag() { gh api "repos/$1/releases/latest" --jq .tag_name; }
# A version is newer when sort -V puts it last and it differs.
newer() { local a=${1#v} b=${2#v}; [ "$a" != "$b" ] && [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" = "$b" ]; }

# xray-core: go.mod pins a tag or a pseudo-version of a master commit; patches/xray-core must be re-applied.
xray=$(awk '$1=="github.com/xtls/xray-core"{print $2; exit}' core/go.mod)
xray_latest=$(latest_tag XTLS/Xray-core)
if [[ "$xray" =~ -0\.[0-9]{14}-([0-9a-f]{12})$ ]]; then
  # Pseudo-version of a master commit: an update when the release tag has commits the pinned one lacks.
  status=$(gh api "repos/XTLS/Xray-core/compare/${BASH_REMATCH[1]}...$xray_latest" --jq .status)
  [ "$status" = ahead ] && add "xray-core" "$xray" "$xray_latest" "\`core/go.mod\`, \`core/patches/xray-core/\`"
elif newer "$xray" "$xray_latest"; then
  add "xray-core" "$xray" "$xray_latest" "\`core/go.mod\`, \`core/patches/xray-core/\`"
fi

singbox=$(awk '$1=="github.com/sagernet/sing-box"{print $2; exit}' core/go.mod)
singbox_latest=$(latest_tag SagerNet/sing-box)
newer "$singbox" "$singbox_latest" && add "sing-box" "$singbox" "$singbox_latest" "\`core/go.mod\` (and the \`sagernet/*\` mods it requires)"

rust=$(sed -n 's/^XRAY_RUST_VERSION="\(.*\)"/\1/p' core/build.sh)
rust_latest=$(latest_tag aimalygin/xray-rust-mobile)
newer "$rust" "$rust_latest" && add "xray-rust-mobile" "$rust" "${rust_latest#v}" "\`core/build.sh\` (\`XRAY_RUST_VERSION\`, \`XRAY_RUST_SHA256\`)"

# Geodata bundled in the APK: Loyalsoldier publishes daily, the pin moves once a month.
geodata=$(sed -n 's/^GEODATA_VERSION="\(.*\)"/\1/p' build.sh)
geodata_latest=$(latest_tag Loyalsoldier/v2ray-rules-dat)
newer "$geodata" "$geodata_latest" && add "geodata (Loyalsoldier)" "$geodata" "$geodata_latest" \
  "\`build.sh\` (\`GEODATA_VERSION\`, \`GEOIP_SHA256\`, \`GEOSITE_SHA256\` from the release's \`*.sha256sum\`)"

go_pinned=$(awk '$1=="go"{print $2; exit}' core/go.mod)
go_latest=$(curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '[.[] | select(.stable)][0].version | ltrimstr("go")')
go_minor=$(cut -d. -f1-2 <<< "$go_latest")
newer "$go_pinned" "$go_minor" && add "Go" "$go_pinned" "$go_latest" "\`core/go.mod\` (\`go\` line)"

flutter=$(sed -n 's/^  FLUTTER_VERSION: //p' .github/workflows/ci.yml)
flutter_latest=$(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
  | jq -r '.current_release.stable as $h | .releases[] | select(.hash == $h) | .version' | head -1)
newer "$flutter" "$flutter_latest" && add "Flutter" "$flutter" "$flutter_latest" "\`FLUTTER_VERSION\` in \`ci.yml\`, \`release.yml\` and \`updates.yml\`"

maven_latest() { curl -fsSL "$1" | grep -o '<version>[^<]*</version>' | sed 's/<[^>]*>//g' | grep -E '^[0-9.]+$' | sort -V | tail -1; }
agp=$(sed -n 's/.*id("com.android.application") version "\(.*\)".*/\1/p' android/settings.gradle.kts)
agp_latest=$(maven_latest https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml)
newer "$agp" "$agp_latest" && add "Android Gradle Plugin" "$agp" "$agp_latest" "\`android/settings.gradle.kts\` (check Flutter supports it)"
kotlin=$(sed -n 's/.*id("org.jetbrains.kotlin.android") version "\(.*\)".*/\1/p' android/settings.gradle.kts)
kotlin_latest=$(maven_latest https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/maven-metadata.xml)
newer "$kotlin" "$kotlin_latest" && add "Kotlin" "$kotlin" "$kotlin_latest" "\`android/settings.gradle.kts\`"
gradle=$(sed -n 's/.*gradle-\([0-9.]*\)-all.zip/\1/p' android/gradle/wrapper/gradle-wrapper.properties)
gradle_latest=$(curl -fsSL https://services.gradle.org/versions/current | jq -r .version)
newer "$gradle" "$gradle_latest" && add "Gradle" "$gradle" "$gradle_latest" "\`android/gradle/wrapper/gradle-wrapper.properties\`"

# GitHub Actions: pinned by commit SHA with the release in a comment (`uses: owner/repo@<sha> # vX.Y.Z`), so a moved
# tag can't change what runs with the release secrets. A newer release is bumped by hand: new SHA and comment.
while read -r action pinned; do
  action_latest=$(latest_tag "$action")
  newer "$pinned" "$action_latest" && add "action $action" "$pinned" "$action_latest" \
    "\`.github/\` (every \`uses: $action@\`: the release's commit SHA, the tag in the comment)"
done < <(grep -rhoE 'uses: [a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+@[0-9a-f]{40} # v[0-9.]+' .github \
  | sed -E 's/uses: ([^@]+)@[0-9a-f]+ # (.*)/\1 \2/' | sort -u)

# Other direct Go modules (xray-core and sing-box are above; replaced modules are ours).
go_mods=$(cd core && go list -m -u -json all 2>/dev/null | jq -r 'select(.Main != true and .Indirect != true and .Update != null
  and .Replace == null and (.Path | test("xtls/xray-core$|sagernet/sing-box$") | not))
  | "| \(.Path) | `\(.Version)` | `\(.Update.Version)` | `core/go.mod` |"')
[ -n "$go_mods" ] && { while IFS= read -r r; do rows+=("$r"); done <<< "$go_mods"; items+=("- [ ] other Go modules in \`core/go.mod\` (table)"); }

# Direct Dart packages with a newer release, resolvable or not.
flutter pub get >/dev/null
dart=$(flutter pub outdated --json 2>/dev/null | jq -r '.packages[] | select(.kind == "direct" or .kind == "dev")
  | select(.current != null and .latest != null and .current.version != .latest.version)
  | "| \(.package) | `\(.current.version)` | `\(.latest.version)` | `pubspec.yaml` |"')
[ -n "$dart" ] && { while IFS= read -r r; do rows+=("$r"); done <<< "$dart"; items+=("- [ ] Dart packages in \`pubspec.yaml\` (table)"); }

[ ${#rows[@]} -eq 0 ] && exit 0

cat <<EOF
### Goal

The build uses the current upstream releases of the cores, toolchains and libraries below, with everything working
as before.

### Context

Found by the monthly update check (\`.github/workflows/updates.yml\`) on $(date -u +%F).

| What | Pinned | Latest | Where |
|---|---|---|---|
$(printf '%s\n' "${rows[@]}")

- xray-core is built with \`core/patches/xray-core/*.patch\` applied (\`core/build.sh prepare\`): every patch must
  apply and keep its tests passing — [teapod_core](https://github.com/Wendor/teapod-stream/blob/master/wiki/components/teapod_core.md).
- sing-box uses SagerNet's modified gvisor, quic-go and others: take the versions its release requires.
- Read the upstream release notes for breaking config changes; the config builders must keep producing valid configs.
- A major version of a package that stores data (\`flutter_secure_storage\`) must keep reading what users already
  have — [models](https://github.com/Wendor/teapod-stream/blob/master/wiki/components/models.md).

### Work items

$(printf '%s\n' "${items[@]}")

### Pull requests

One PR per core (xray-core, sing-box, xray-rust), one for Flutter with the Dart packages, one for Gradle/AGP/Kotlin,
one for Go and the other Go modules, one for the GitHub Actions pins. Each can merge on its own; open at most three at a time. Skip an item that
breaks something you can't fix and say why in this issue.

### Done when

- CI is green: \`dart\`, \`kotlin\`, \`core\` (with the xray-core patch tests).
- \`cd core && ./build.sh prepare && go test ./...\` passes locally for core changes, and the AAR builds.
- Wiki pages that name versions are updated.
- Not tested on a device: the maintainer runs \`tool/itest\` before the next release.

### Out of scope

New features of the updated components; changes to the app's behaviour.

### Risk

High — cores and the build toolchain.
EOF
