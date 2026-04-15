#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
#  TeapodStream build script
#  Usage:
#    ./build.sh debug        — debug APK
#    ./build.sh release      — release APK (split per ABI)
#    ./build.sh aab          — release AAB (Google Play)
#    ./build.sh run          — запуск на подключённом устройстве
#    ./build.sh binaries     — скачать xray + geodata
#    ./build.sh clean        — очистить build артефакты
# ─────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JNILIBS_DIR="android/app/src/main/jniLibs"
LIBS_DIR="android/app/libs"
ALL_ABIS=("arm64-v8a" "x86_64")
DEFAULT_ABI="arm64-v8a"
TUN2SOCKS_REPO="Wendor/teapod-tun2socks"
LOCAL_TUN2SOCKS_DIR="../teapod-tun2socks/output"
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
  local check_all=${1:-false}
  local abis_to_check=("$DEFAULT_ABI")
  if [[ "$check_all" == "true" ]]; then
    abis_to_check=("${ALL_ABIS[@]}")
  fi

  for abi in "${abis_to_check[@]}"; do
    if [[ ! -f "$JNILIBS_DIR/$abi/libxray.so" ]]; then
      if [[ "$abi" == "$DEFAULT_ABI" ]]; then
        warn "Отсутствует критический файл: $JNILIBS_DIR/$abi/libxray.so"
        missing=1
      fi
    fi
    if [[ ! -f "$LIBS_DIR/teapod-tun2socks-$abi.aar" ]]; then
      warn "Отсутствует: $LIBS_DIR/teapod-tun2socks-$abi.aar"
      missing=1
    fi
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
      strip_binary "$JNILIBS_DIR/$abi/libxray.so"
      ok "xray → $JNILIBS_DIR/$abi/libxray.so"
    fi
  else
    warn "Пропуск xray для $abi"
  fi
  
  # Стриппинг других библиотек если они есть (например sing-box)
  if [[ -f "$JNILIBS_DIR/$abi/libsing-box.so" ]]; then
    strip_binary "$JNILIBS_DIR/$abi/libsing-box.so"
  fi

  rm -rf "$TMP_XRAY"
}

download_tun2socks_binaries() {
  mkdir -p "$LIBS_DIR"
  log "Проверяем наличие teapod-tun2socks..."

  local latest_info=""

  for abi in "${ALL_ABIS[@]}"; do
    local found=0
    # 1. Проверка локальной папки
    if [[ -d "$LOCAL_TUN2SOCKS_DIR" ]]; then
      local local_file=$(ls "$LOCAL_TUN2SOCKS_DIR"/teapod-tun2socks-"$abi"-*.aar 2>/dev/null | sort -V | tail -1)
      if [[ -n "$local_file" ]]; then
        cp "$local_file" "$LIBS_DIR/teapod-tun2socks-$abi.aar"
        ok "Локальный AAR ($abi) скопирован из $(basename "$local_file")"
        found=1
      fi
    fi

    # 2. Если не найдено локально, качаем с GitHub
    if [[ $found -eq 0 ]]; then
      # Получаем инфо о релизе один раз
      if [[ -z "$latest_info" ]]; then
        log "Запрос данных о последнем релизе $TUN2SOCKS_REPO..."
        latest_info=$(curl -s "https://api.github.com/repos/$TUN2SOCKS_REPO/releases/latest")
      fi

      local tag=$(echo "$latest_info" | grep '"tag_name":' | cut -d'"' -f4)
      local download_url=$(echo "$latest_info" | grep "browser_download_url" | grep "$abi" | cut -d'"' -f4 | head -1)

      if [[ -n "$download_url" ]]; then
        log "Скачиваем teapod-tun2socks ($abi) версия $tag..."
        curl -L --progress-bar "$download_url" -o "$LIBS_DIR/teapod-tun2socks-$abi.aar"
        # Для AAR стриппинг сложнее, но можно попробовать распаковать и почистить
        # (На данный момент считаем что библиотека собрана верно)
        ok "Скачан AAR ($abi) версия $tag"
        found=1
      else
        warn "Не удалось найти ссылку для скачивания $abi в релизе $tag"
      fi
    fi

    if [[ $found -eq 0 ]]; then
      warn "Не удалось найти библиотеку teapod-tun2socks для $abi"
    fi
  done
}

download_binaries() {
  log "Очистка управляемых бинарников..."
  # Удаляем только libxray.so (его мы точно скачаем), остальные оставляем для стриппинга
  find "$JNILIBS_DIR" -type f -name "libxray.so" -delete
  
  local ASSETS_BIN="assets/binaries"
  log "Очистка старых бинарников из ассетов..."
  find "$ASSETS_BIN" -type f ! -name "*.dat" -delete

  for abi in "${ALL_ABIS[@]}"; do
    download_abi_binaries "$abi"
  done

  download_tun2socks_binaries

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
  gh release view "$tag" --json url --jq '.url'
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
    log "Сборка RELEASE APK (arm64 + x86_64)..."
    accept_sdk_licenses
    check_binaries true || true
    ensure_pub

    # Каждый AAR содержит те же Kotlin-классы → Duplicate class в Gradle,
    # поэтому собираем по одной архитектуре за раз с --no-pub.
    dir="build/app/outputs/flutter-apk"
    rm -f "$dir"/app-*-release.apk

    for plat in android-arm64 android-x64; do
      abi="arm64-v8a"
      [[ "$plat" == "android-x64" ]] && abi="x86_64"

      log "Сборка архитектуры: $abi ($plat)..."
      flutter build apk --release --target-platform "$plat" --no-pub

      if [[ -f "$dir/app-release.apk" ]]; then
        mv "$dir/app-release.apk" "$dir/app-$abi-release.apk"
        ok "Сборка $abi завершена"
      else
        err "Ошибка: файл $dir/app-release.apk не был создан для $abi"
      fi
    done

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
    echo "    ./build.sh binaries     Скачать xray, geodata"
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
