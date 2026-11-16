#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
#  TeapodStream build script
#  Usage:
#    ./build.sh debug        — debug APK
#    ./build.sh release      — release APK (split per ABI)
#    ./build.sh aab          — release AAB (Google Play)
#    ./build.sh run          — run on the connected device
#    ./build.sh itest        — build and install the …itest package for integration tests
#    ./build.sh bump X.Y.Z   — app version
#    ./build.sh core         — build the teapod-core AAR from core/ (Go, gomobile, NDK)
#    ./build.sh binaries     — teapod-core AAR for core/ (cache → release asset → build) + geodata
#    ./build.sh clean        — clean build artifacts
# ─────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JNILIBS_DIR="android/app/src/main/jniLibs"
LIBS_DIR="android/app/libs"
ALL_ABIS=("arm64-v8a" "x86_64")
DEFAULT_ABI="arm64-v8a"
CORE_OUTPUTS="core/outputs"
GITHUB_REPO="Wendor/teapod-stream"
NDK_VERSION="28.2.13676358"

# ─── Version from pubspec.yaml (format: "1.0.0+5002") ───
VERSION=$(grep "^version:" pubspec.yaml | head -1 | cut -d' ' -f2 | cut -d'+' -f1)
VERSION_CODE=$(grep "^version:" pubspec.yaml | head -1 | cut -d' ' -f2 | cut -d'+' -f2)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
err()  { echo -e "${RED}✗ $*${NC}"; exit 1; }

accept_sdk_licenses() {
  # homebrew by default; on CI taken from the runner's environment
  export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
  export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"

  # Android SDK licenses live in $ANDROID_HOME/licenses/. If the folder exists
  # and isn't empty, the licenses are already accepted — skip. Running flutter doctor
  # on every build is expensive (~5-10 s).
  local licenses_dir="$ANDROID_HOME/licenses"
  if [[ -d "$licenses_dir" ]] && [[ -n "$(ls -A "$licenses_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  log "Accepting Android SDK licenses (first time)..."
  local sdk_manager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [[ -x "$sdk_manager" ]]; then
    yes | "$sdk_manager" --licenses >/dev/null 2>&1 || true
  fi
  yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
}

ensure_pub() {
  # Run pub get only if pubspec.yaml or pubspec.lock changed
  # since the last successful pub get (compared against .dart_tool/package_config.json).
  local pkg_config=".dart_tool/package_config.json"
  if [[ ! -f "$pkg_config" ]] \
      || [[ "pubspec.yaml" -nt "$pkg_config" ]] \
      || [[ "pubspec.lock" -nt "$pkg_config" ]]; then
    log "pubspec changed, running flutter pub get..."
    flutter pub get
  fi
}

check_binaries() {
  local missing=0

  if [[ ! -f "$LIBS_DIR/teapod-core.aar" ]]; then
    warn "Missing: $LIBS_DIR/teapod-core.aar"
    missing=1
  fi

  local ASSETS_BIN="assets/binaries"
  for f in "geoip.dat" "geosite.dat"; do
    if [[ ! -f "$ASSETS_BIN/$f" ]]; then
      warn "Missing: $ASSETS_BIN/$f"
      missing=1
    fi
  done

  if [[ $missing -eq 1 ]]; then
    warn "Critical binaries are missing!"
    return 1
  fi
  return 0
}

find_strip_tool() {
  local ndk_path="/opt/homebrew/share/android-commandlinetools/ndk/$NDK_VERSION"
  local tool="$ndk_path/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip"
  if [[ -x "$tool" ]]; then
    echo "$tool"
  else
    find "$ANDROID_HOME/ndk" -name "llvm-strip" -type f | head -1
  fi
}

strip_binary() {
  local target=$1
  if [[ ! -f "$target" ]]; then return; fi
  
  local strip_tool=$(find_strip_tool)
  if [[ -n "$strip_tool" ]]; then
    "$strip_tool" --strip-unneeded "$target"
  fi
}

# The AAR is identified by the git tree hash of core/: the same sources give the same AAR,
# whatever the app version. Empty when core/ has uncommitted changes.
core_key() {
  [[ -z "$(git status --porcelain -- core)" ]] || return 0
  git rev-parse --short=12 HEAD:core
}

build_core() {
  log "Building teapod-core from core/..."
  core/build.sh build
  mkdir -p "$LIBS_DIR"
  cp "$CORE_OUTPUTS/teapod-core.aar" "$LIBS_DIR/teapod-core.aar"
  local key
  key=$(core_key)
  [[ -z "$key" ]] || cp "$CORE_OUTPUTS/teapod-core.aar" "$CORE_OUTPUTS/teapod-core-$key.aar"
  ok "teapod-core ${key:-(uncommitted core/)} → $LIBS_DIR/teapod-core.aar"
}

copy_teapod_core_binaries() {
  mkdir -p "$LIBS_DIR" "$CORE_OUTPUTS"
  local key
  key=$(core_key)
  if [[ -z "$key" ]]; then
    warn "core/ has uncommitted changes — building the AAR locally"
    build_core
    return 0
  fi

  local cached="$CORE_OUTPUTS/teapod-core-$key.aar"
  if [[ ! -f "$cached" ]]; then
    # Every app release carries the AAR it was built with, named by the core/ tree hash
    local url
    url=$(curl -fsSL "https://api.github.com/repos/$GITHUB_REPO/releases?per_page=100" 2>/dev/null \
      | grep -o "https://[^\"]*/teapod-core-$key\.aar" | head -1 || true)
    if [[ -n "$url" ]]; then
      log "Downloading teapod-core $key from the releases..."
      curl -fL --progress-bar "$url" -o "$cached.download" && mv "$cached.download" "$cached"
    fi
  fi

  if [[ -f "$cached" ]]; then
    cp "$cached" "$LIBS_DIR/teapod-core.aar"
    ok "teapod-core $key"
  else
    warn "No released AAR for core/ $key — building it (needs Go, gomobile and the NDK, see core/README.md)"
    build_core
  fi
}

# App version. versionCode = MAJOR*10000 + MINOR*100 + PATCH.
bump_version() {
  local v="${1:-}"
  [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || err "Usage: ./build.sh bump X.Y.Z"
  local code=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))
  sed -i '' -E "s/^version: .*/version: ${v}+${code}/" pubspec.yaml
  ok "Version $VERSION → $v (+$code)"
}

download_binaries() {
  local ASSETS_BIN="assets/binaries"

  copy_teapod_core_binaries

  mkdir -p "$ASSETS_BIN"
  log "Downloading geoip.dat..."
  curl -L --progress-bar "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -o "$ASSETS_BIN/geoip.dat" && ok "geoip.dat"

  log "Downloading geosite.dat..."
  curl -L --progress-bar "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -o "$ASSETS_BIN/geosite.dat" && ok "geosite.dat"

  echo ""
  log "Binaries in $JNILIBS_DIR"
  log "Geodata in $ASSETS_BIN"
}

rename_apks() {
  local dir="build/app/outputs/flutter-apk"

  echo ""
  if ls "$dir"/app-arm64-v8a-release.apk 1>/dev/null 2>&1; then
    for abi in arm64-v8a x86_64; do
      local src="$dir/app-$abi-release.apk"
      if [[ -f "$src" ]]; then
        local dst="$dir/teapod-stream-$abi-release-$VERSION.apk"
        mv "$src" "$dst"
        ok "$dst"
      fi
    done
  elif ls "$dir"/app-arm64-v8a-debug.apk 1>/dev/null 2>&1; then
    for abi in arm64-v8a x86_64; do
      local src="$dir/app-$abi-debug.apk"
      if [[ -f "$src" ]]; then
        local dst="$dir/teapod-stream-$abi-debug-$VERSION.apk"
        mv "$src" "$dst"
        ok "$dst"
      fi
    done
  elif [[ -f "$dir/app-release.apk" ]]; then
    local dst="$dir/teapod-stream-universal-release-$VERSION.apk"
    mv "$dir/app-release.apk" "$dst"
    ok "$dst"
  elif [[ -f "$dir/app-debug.apk" ]]; then
    local dst="$dir/teapod-stream-universal-debug-$VERSION.apk"
    mv "$dir/app-debug.apk" "$dst"
    ok "$dst"
  fi
}

push_release() {
  local is_pre=${1:-false}
  local dir="build/app/outputs/flutter-apk"
  local tag="v$VERSION"

  # Find APK files
  local apks=("$dir"/teapod-stream-*-release-"$VERSION".apk)
  if [[ ! -f "${apks[0]}" ]]; then
    err "No APKs found! Run first: ./build.sh release"
  fi
  # The AAR the APKs were built with, so ./build.sh binaries can download it by the core/ hash
  local key
  key=$(core_key)
  [[ -n "$key" && -f "$CORE_OUTPUTS/teapod-core-$key.aar" ]] || err "No teapod-core AAR for core/ ${key:-(uncommitted)} — run ./build.sh binaries"
  apks+=("$CORE_OUTPUTS/teapod-core-$key.aar")

  # Check if gh is installed
  if ! command -v gh &>/dev/null; then
    err "gh CLI not found! Install it: brew install gh && gh auth login"
  fi

  # Check if authenticated
  if ! gh auth status &>/dev/null; then
    err "Not logged in to gh! Run: gh auth login"
  fi

  log "Publishing release $tag ($VERSION)..."

  # Check if tag already exists
  if gh release view "$tag" &>/dev/null; then
    warn "Release $tag already exists, updating..."
    gh release upload "$tag" "${apks[@]}" --clobber
  else
    # The tag points to the current commit, not the default branch (master)
    local head
    head=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
    [[ -n "$(git -C "$SCRIPT_DIR" branch -r --contains "$head")" ]] || err "Commit $head is not pushed — git push first"
    local flags=("--title" "TeapodStream $VERSION" "--generate-notes" "--target" "$head")
    [[ "$is_pre" == "true" ]] && flags+=("--prerelease")
    gh release create "$tag" "${flags[@]}" "${apks[@]}"
  fi

  ok "Release $tag published!"
}

case "${1:-help}" in

  debug)
    log "Building DEBUG APK..."
    accept_sdk_licenses
    check_binaries || true
    ensure_pub
    flutter build apk --debug --split-per-abi --no-pub --target-platform android-arm64,android-x64
    rename_apks
    ;;

  itest)
    # The com.teapodstream.teapodstream.itest package with the agent (tool/itest/).
    # The main app is not reinstalled.
    log "Building ITEST APK..."
    accept_sdk_licenses
    check_binaries || true
    ensure_pub
    TEAPOD_ITEST=1 flutter build apk --debug --no-pub --target-platform android-arm64 --dart-define=ITEST=true
    apk="build/app/outputs/flutter-apk/app-debug.apk"
    pkg="com.teapodstream.teapodstream.itest"
    aapt=$(ls -d "${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"/build-tools/*/aapt2 2>/dev/null | tail -1)
    # Don't install an unchecked APK: a non-itest build would replace the main app.
    [ -n "$aapt" ] || err "aapt2 not found (ANDROID_HOME) — cannot verify the package, install cancelled"
    "$aapt" dump packagename "$apk" | grep -qx "$pkg" || err "APK was not built as $pkg — install cancelled"
    adb install -r "$apk"
    adb shell appops set "$pkg" ACTIVATE_VPN allow
    adb shell pm grant "$pkg" android.permission.POST_NOTIFICATIONS || true
    adb shell dumpsys deviceidle whitelist +"$pkg" >/dev/null
    ok "Installed $pkg"
    ;;

  release)
    log "Building RELEASE APK (arm64 + x86_64)..."
    accept_sdk_licenses
    check_binaries || true
    ensure_pub

    dir="build/app/outputs/flutter-apk"
    rm -f "$dir"/app-*-release.apk

    flutter build apk --release --split-per-abi --no-pub --target-platform android-arm64,android-x64 \
      --obfuscate --split-debug-info=build/app/outputs/symbols

    rename_apks
    ;;

  aab)
    log "Building RELEASE AAB..."
    accept_sdk_licenses
    check_binaries || warn "Continuing without binaries"
    ensure_pub
    flutter build appbundle --release --no-pub --target-platform android-arm64,android-x64
    ok "AAB: build/app/outputs/bundle/release/app-release.aab"
    ;;

  run)
    log "Running DEBUG..."
    check_binaries || true
    ensure_pub
    flutter run --debug --no-pub
    ;;

  run-release)
    log "Running RELEASE..."
    check_binaries || warn "Binaries are missing"
    ensure_pub
    flutter run --release --no-pub
    ;;

  binaries)
    download_binaries
    ;;

  core)
    build_core
    ;;

  bump)
    bump_version "${2:-}"
    ;;

  push)
    push_release false
    ;;

  pushpre)
    push_release true
    ;;

  clean)
    log "Cleaning..."
    flutter clean
    ok "Done"
    ;;

  help|--help|-h|*)
    echo ""
    echo "  TeapodStream build script"
    echo ""
    echo "  Commands:"
    echo "    ./build.sh bump X.Y.Z   App version"
    echo "    ./build.sh binaries     teapod-core AAR for core/ (cache, release asset or build) + geodata"
    echo "    ./build.sh core         Build the teapod-core AAR from core/"
    echo "    ./build.sh debug        Build a debug APK"
    echo "    ./build.sh release      Build a release APK (split per ABI)"
    echo "    ./build.sh aab          Build an AAB"
    echo "    ./build.sh run          Run debug on the device"
    echo "    ./build.sh itest        Build and install the …itest package (integration tests)"
    echo "    ./build.sh run-release  Run release on the device"
    echo "    ./build.sh pushpre      Publish a Pre-release on GitHub"
    echo "    ./build.sh push         Publish a Release on GitHub"
    echo "    ./build.sh clean        Clean artifacts"
    echo ""
    ;;
esac
