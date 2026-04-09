#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
#  TeapodStream build script
#  Usage:
#    ./build.sh debug        — debug APK
#    ./build.sh release      — release APK (split per ABI)
#    ./build.sh aab          — release AAB (Google Play)
#    ./build.sh run          — запуск на подключённом устройстве
#    ./build.sh binaries     — скачать xray + tun2socks + geodata
#    ./build.sh clean        — очистить build артефакты
# ─────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JNILIBS_DIR="android/app/src/main/jniLibs"
ALL_ABIS=("arm64-v8a" "x86_64")
DEFAULT_ABI="arm64-v8a"

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
  log "Проверяем лицензии Android SDK..."
  export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
  export ANDROID_SDK_ROOT="/opt/homebrew/share/android-commandlinetools"

  local sdk_manager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  if [[ -x "$sdk_manager" ]]; then
    yes | "$sdk_manager" --licenses >/dev/null 2>&1 || true
  fi
  yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
}

check_binaries() {
  local missing=0
  local check_all=${1:-false}
  local abis_to_check=("$DEFAULT_ABI")
  if [[ "$check_all" == "true" ]]; then
    abis_to_check=("${ALL_ABIS[@]}")
  fi

  for abi in "${abis_to_check[@]}"; do
    for f in "libxray.so" "libtun2socks.so"; do
      if [[ ! -f "$JNILIBS_DIR/$abi/$f" ]]; then
        if [[ "$abi" == "$DEFAULT_ABI" ]]; then
          warn "Отсутствует критический файл: $JNILIBS_DIR/$abi/$f"
          missing=1
        fi
      fi
    done
  done

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

download_abi_binaries() {
  local abi=$1
  log "Скачиваем бинарники для ABI: $abi"
  mkdir -p "$JNILIBS_DIR/$abi"

  local xray_abi=$abi
  [[ "$abi" == "x86_64" ]] && xray_abi="amd64"

  log "Скачиваем xray-core ($abi)..."
  local TMP_XRAY=$(mktemp -d)
  if curl -L --progress-bar "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-android-$xray_abi.zip" -o "$TMP_XRAY/xray.zip" 2>/dev/null; then
    unzip -o "$TMP_XRAY/xray.zip" xray -d "$TMP_XRAY/" 2>/dev/null || true
    local found=$(find "$TMP_XRAY" -name "xray" -type f | head -1)
    if [[ -n "$found" ]]; then
      cp "$found" "$JNILIBS_DIR/$abi/libxray.so"
      chmod +x "$JNILIBS_DIR/$abi/libxray.so"
      ok "xray → $JNILIBS_DIR/$abi/libxray.so"
    fi
  else
    warn "Пропуск xray для $abi"
  fi
  rm -rf "$TMP_XRAY"

  log "Скачиваем tun2socks ($abi)..."
  local tun_file="tun2socks-linux-arm64"
  [[ "$abi" == "x86_64" ]] && tun_file="tun2socks-linux-amd64"

  local TMP_TUN=$(mktemp -d)
  if curl -L --progress-bar "https://github.com/xjasonlyu/tun2socks/releases/latest/download/$tun_file.zip" -o "$TMP_TUN/tun.zip" 2>/dev/null; then
    unzip -o "$TMP_TUN/tun.zip" -d "$TMP_TUN/" 2>/dev/null || true
    local found=$(find "$TMP_TUN" -name "tun2socks*" -type f | head -1)
    if [[ -n "$found" ]]; then
      cp "$found" "$JNILIBS_DIR/$abi/libtun2socks.so"
      chmod +x "$JNILIBS_DIR/$abi/libtun2socks.so"
      ok "tun2socks → $JNILIBS_DIR/$abi/libtun2socks.so"
    fi
  else
    warn "Пропуск tun2socks для $abi"
  fi
  rm -rf "$TMP_TUN"
}

download_binaries() {
  local ASSETS_BIN="assets/binaries"
  if [[ -d "$ASSETS_BIN" ]]; then
    log "Очистка старых бинарников из ассетов..."
    find "$ASSETS_BIN" -type f ! -name "*.dat" -delete
  fi

  for abi in "${ALL_ABIS[@]}"; do
    download_abi_binaries "$abi"
  done

  mkdir -p "$ASSETS_BIN"
  log "Скачиваем geoip.dat..."
  curl -L --progress-bar "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" -o "$ASSETS_BIN/geoip.dat" && ok "geoip.dat"

  log "Скачиваем geosite.dat..."
  curl -L --progress-bar "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" -o "$ASSETS_BIN/geosite.dat" && ok "geosite.dat"

  echo ""
  log "Бинарники в $JNILIBS_DIR"
  log "Геоданные в $ASSETS_BIN"
}

rename_apks() {
  local dir="build/app/outputs/flutter-apk"

  # Remove broken armeabi-v7a (no xray binary for 32-bit ARM)
  rm -f "$dir"/app-armeabi-v7a-release.apk*

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
  elif [[ -f "$dir/app-release.apk" ]]; then
    local dst="$dir/teapod-stream-universal-release-$VERSION.apk"
    mv "$dir/app-release.apk" "$dst"
    ok "$dst"
  fi
}

case "${1:-help}" in

  debug)
    log "Сборка DEBUG APK..."
    accept_sdk_licenses
    check_binaries || true
    flutter build apk --debug
    APK="build/app/outputs/flutter-apk/app-debug.apk"
    ok "Debug APK: $APK ($(du -sh "$APK" | cut -f1))"
    ;;

  release)
    log "Сборка RELEASE APK (arm64 + x86_64)..."
    accept_sdk_licenses
    check_binaries true || true
    flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64
    rename_apks
    ;;

  aab)
    log "Сборка RELEASE AAB..."
    accept_sdk_licenses
    check_binaries || warn "Продолжаем без бинарников"
    flutter build appbundle --release
    ok "AAB: build/app/outputs/bundle/release/app-release.aab"
    ;;

  run)
    log "Запуск DEBUG..."
    check_binaries || true
    flutter run --debug
    ;;

  run-release)
    log "Запуск RELEASE..."
    check_binaries || warn "Бинарники отсутствуют"
    flutter run --release
    ;;

  binaries)
    download_binaries
    ;;

  push)
    dir="build/app/outputs/flutter-apk"
    tag="v$VERSION"

    # Find APK files
    apks=("$dir"/teapod-stream-*-release-"$VERSION".apk)
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

    log "Создаю релиз $tag ($VERSION)..."

    # Check if tag already exists
    if gh release view "$tag" &>/dev/null; then
      warn "Релиз $tag уже существует, обновляю..."
      gh release upload "$tag" "${apks[@]}" --clobber
    else
      gh release create "$tag" \
        --title "TeapodStream $VERSION" \
        --generate-notes \
        "${apks[@]}"
    fi

    ok "Релиз $tag опубликован:"
    gh release view "$tag" --json url --jq '.url'
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
    echo "    ./build.sh binaries     Скачать xray, tun2socks, geodata"
    echo "    ./build.sh debug        Собрать debug APK"
    echo "    ./build.sh release      Собрать release APK (split per ABI)"
    echo "    ./build.sh aab          Собрать AAB"
    echo "    ./build.sh run          Запустить debug на устройстве"
    echo "    ./build.sh run-release  Запустить release на устройстве"
    echo "    ./build.sh push          Опубликовать релиз на GitHub"
    echo "    ./build.sh clean        Очистить артефакты"
    echo ""
    ;;
esac
