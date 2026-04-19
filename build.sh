#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
#  TeapodStream build script
#  Usage:
#    ./build.sh debug        — debug APK
#    ./build.sh release      — release APK (split per ABI)
#    ./build.sh aab          — release AAB (Google Play)
#    ./build.sh run          — запуск на подключённом устройстве
#    ./build.sh binaries     — скопировать teapod-core + скачать geodata
#    ./build.sh clean        — очистить build артефакты
# ─────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JNILIBS_DIR="android/app/src/main/jniLibs"
LIBS_DIR="android/app/libs"
ALL_ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
DEFAULT_ABI="arm64-v8a"
LOCAL_TEAPOD_CORE_DIR="../teapod-core/outputs"
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
  export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  export ANDROID_SDK_ROOT="/opt/homebrew/share/android-commandlinetools"

  # Android SDK лицензии хранятся в $ANDROID_HOME/licenses/. Если папка существует
  # и не пустая — лицензии уже приняты, пропускаем. Запускать flutter doctor
  # при каждом билде дорого (~5-10 сек).
  local licenses_dir="$ANDROID_HOME/licenses"
  if [[ -d "$licenses_dir" ]] && [[ -n "$(ls -A "$licenses_dir" 2>/dev/null)" ]]; then
    return 0
  fi

  log "Принимаем лицензии Android SDK (первый раз)..."
  local sdk_manager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [[ -x "$sdk_manager" ]]; then
    yes | "$sdk_manager" --licenses >/dev/null 2>&1 || true
  fi
  yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
}

ensure_pub() {
  # Запускаем pub get только если pubspec.yaml или pubspec.lock изменились
  # с момента последнего успешного pub get (смотрим на .dart_tool/package_config.json).
  local pkg_config=".dart_tool/package_config.json"
  if [[ ! -f "$pkg_config" ]] \
      || [[ "pubspec.yaml" -nt "$pkg_config" ]] \
      || [[ "pubspec.lock" -nt "$pkg_config" ]]; then
    log "pubspec изменился, запускаем flutter pub get..."
    flutter pub get
  fi
}

check_binaries() {
  local missing=0

  if [[ ! -f "$LIBS_DIR/teapod-core.aar" ]]; then
    warn "Отсутствует: $LIBS_DIR/teapod-core.aar"
    missing=1
  fi

  local ASSETS_BIN="assets/binaries"
  for f in "geoip.dat" "geosite.dat"; do
    if [[ ! -f "$ASSETS_BIN/$f" ]]; then
      warn "Отсутствует: $ASSETS_BIN/$f"
      missing=1
    fi
  done

  if [[ $missing -eq 1 ]]; then
    warn "Критически важные бинарники отсутствуют!"
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

copy_teapod_core_binaries() {
  mkdir -p "$LIBS_DIR"

  # 1. Ищем fat AAR локально (../teapod-core/outputs/teapod-core-{VERSION}.aar)
  #    Имя fat AAR не содержит ABI: teapod-core-1.0.0.aar, не teapod-core-arm64-v8a-1.0.0.aar
  if [[ -d "$LOCAL_TEAPOD_CORE_DIR" ]]; then
    local local_fat
    local_fat=$(ls "$LOCAL_TEAPOD_CORE_DIR"/teapod-core-[0-9]*.aar 2>/dev/null | sort -V | tail -1)
    if [[ -n "$local_fat" ]]; then
      cp "$local_fat" "$LIBS_DIR/teapod-core.aar"
      ok "Локальный fat AAR скопирован: $(basename "$local_fat")"
      return 0
    fi
  fi

  # 2. Fallback — скачиваем fat AAR из последнего релиза Wendor/teapod-core
  log "Локальный teapod-core не найден, скачиваем с GitHub..."
  local release_info
  release_info=$(curl -sf "https://api.github.com/repos/Wendor/teapod-core/releases/latest") || {
    err "Не удалось получить инфо о релизе Wendor/teapod-core"
  }

  local tag download_url
  tag=$(echo "$release_info" | grep '"tag_name":' | cut -d'"' -f4)
  # Fat AAR: имя вида teapod-core-{VERSION}.aar (без ABI-суффикса)
  download_url=$(echo "$release_info" | grep "browser_download_url" \
    | grep '"teapod-core-[^"]*\.aar"' \
    | grep -v 'arm64\|armeabi\|x86' \
    | cut -d'"' -f4 | head -1)

  if [[ -z "$download_url" ]]; then
    err "Не найден fat AAR в релизе $tag репозитория Wendor/teapod-core"
  fi

  log "Скачиваем teapod-core $tag..."
  curl -L --progress-bar "$download_url" -o "$LIBS_DIR/teapod-core.aar"
  ok "Скачан teapod-core $tag"
}

download_binaries() {
  local ASSETS_BIN="assets/binaries"

  copy_teapod_core_binaries

  mkdir -p "$ASSETS_BIN"
  log "Скачиваем geoip.dat..."
  curl -L --progress-bar "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" -o "$ASSETS_BIN/geoip.dat" && ok "geoip.dat"

  log "Скачиваем geosite.dat..."
  curl -L --progress-bar "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" -o "$ASSETS_BIN/geosite.dat" && ok "geosite.dat"

  echo ""
  log "Бинарники в $JNILIBS_DIR"
  log "Геоданные в $ASSETS_BIN"
}

rename_apks() {
  local dir="build/app/outputs/flutter-apk"

  echo ""
  if ls "$dir"/app-arm64-v8a-release.apk 1>/dev/null 2>&1; then
    for abi in arm64-v8a armeabi-v7a x86_64; do
      local src="$dir/app-$abi-release.apk"
      if [[ -f "$src" ]]; then
        local dst="$dir/teapod-stream-$abi-release-$VERSION.apk"
        mv "$src" "$dst"
        ok "$dst"
      fi
    done
  elif [[ -f "$dir/app-release.apk" ]]; then
    local dst="$dir/teapod-stream-universal-release-$VERSION.apk"
    mv "$dir/app-release.apk" "$dst"
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
    err "APK не найдены! Сначала выполните: ./build.sh release"
  fi

  # Check if gh is installed
  if ! command -v gh &>/dev/null; then
    err "gh CLI не найден! Установите: brew install gh && gh auth login"
  fi

  # Check if authenticated
  if ! gh auth status &>/dev/null; then
    err "Не авторизован в gh! Выполните: gh auth login"
  fi

  log "Публикация релиза $tag ($VERSION)..."

  # Check if tag already exists
  if gh release view "$tag" &>/dev/null; then
    warn "Релиз $tag уже существует, обновляю..."
    gh release upload "$tag" "${apks[@]}" --clobber
  else
    local flags=("--title" "TeapodStream $VERSION" "--generate-notes")
    [[ "$is_pre" == "true" ]] && flags+=("--prerelease")
    gh release create "$tag" "${flags[@]}" "${apks[@]}"
  fi

  ok "Релиз $tag опубликован!"
}

case "${1:-help}" in

  debug)
    log "Сборка DEBUG APK..."
    accept_sdk_licenses
    check_binaries || true
    ensure_pub
    flutter build apk --debug --no-pub
    APK="build/app/outputs/flutter-apk/app-debug.apk"
    ok "Debug APK: $APK ($(du -sh "$APK" | cut -f1))"
    ;;

  release)
    log "Сборка RELEASE APK (arm64 + arm32 + x86_64)..."
    accept_sdk_licenses
    check_binaries || true
    ensure_pub

    dir="build/app/outputs/flutter-apk"
    rm -f "$dir"/app-*-release.apk

    flutter build apk --release --split-per-abi --no-pub \
      --obfuscate --split-debug-info=build/app/outputs/symbols

    rename_apks
    ;;

  aab)
    log "Сборка RELEASE AAB..."
    accept_sdk_licenses
    check_binaries || warn "Продолжаем без бинарников"
    ensure_pub
    flutter build appbundle --release --no-pub
    ok "AAB: build/app/outputs/bundle/release/app-release.aab"
    ;;

  run)
    log "Запуск DEBUG..."
    check_binaries || true
    ensure_pub
    flutter run --debug --no-pub
    ;;

  run-release)
    log "Запуск RELEASE..."
    check_binaries || warn "Бинарники отсутствуют"
    ensure_pub
    flutter run --release --no-pub
    ;;

  binaries)
    download_binaries
    ;;

  push)
    push_release false
    ;;

  pushpre)
    push_release true
    ;;

  clean)
    log "Очистка..."
    flutter clean
    ok "Готово"
    ;;

  help|--help|-h|*)
    echo ""
    echo "  TeapodStream build script"
    echo ""
    echo "  Команды:"
    echo "    ./build.sh binaries     Скопировать teapod-core AAR + скачать geodata"
    echo "    ./build.sh debug        Собрать debug APK"
    echo "    ./build.sh release      Собрать release APK (split per ABI)"
    echo "    ./build.sh aab          Собрать AAB"
    echo "    ./build.sh run          Запустить debug на устройстве"
    echo "    ./build.sh run-release  Запустить release на устройстве"
    echo "    ./build.sh pushpre      Опубликовать Pre-release на GitHub"
    echo "    ./build.sh push         Опубликовать Release на GitHub"
    echo "    ./build.sh clean        Очистить артефакты"
    echo ""
    ;;
esac
