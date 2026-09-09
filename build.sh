#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Honor a build-local JDK without changing global Flutter configuration.
if [[ -n "${JAVA_HOME:-}" ]]; then
  export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.home=$JAVA_HOME"
fi

build_command="${1:-release}"
selected_core="${TEAPOD_CORE:-go}"
case "$selected_core" in go|rust) ;; *) echo 'TEAPOD_CORE must be go or rust' >&2; exit 2 ;; esac
target_platforms="android-arm,android-arm64,android-x64"
abis=(armeabi-v7a arm64-v8a x86_64)
build_flags=("--dart-define=TEAPOD_CORE=$selected_core")
if [[ "$selected_core" == rust ]]; then
  target_platforms="android-arm64,android-x64"
  abis=(arm64-v8a x86_64)
  build_flags+=("--build-name=1.6.3-rust.4" "--build-number=10607")
fi
prepare_binaries() {
  if [[ "$selected_core" == rust ]]; then
    python3 scripts/fetch-rust-core.py
  else
    python3 scripts/fetch-go-core.py
  fi
}
case "$build_command" in
  binaries) prepare_binaries ;;
  release|debug|aab|run|run-release)
    prepare_binaries
    flutter pub get
    case "$build_command" in
      release) flutter build apk --release --target-platform "$target_platforms" --split-per-abi "${build_flags[@]}" ;;
      debug) flutter build apk --debug --target-platform "$target_platforms" --split-per-abi "${build_flags[@]}" ;;
      aab) flutter build appbundle --release --target-platform "$target_platforms" "${build_flags[@]}" ;;
      run) flutter run "${build_flags[@]}" ;;
      run-release) flutter run --release "${build_flags[@]}" ;;
    esac
    if [[ "$build_command" == release || "$build_command" == debug ]]; then
      artifact_dir="build/artifacts/$selected_core"
      mkdir -p "$artifact_dir"
      for abi in "${abis[@]}"; do
        cp "build/app/outputs/flutter-apk/app-$abi-$build_command.apk" "$artifact_dir/"
      done
      echo "APKs: $artifact_dir"
    fi
    ;;
  test)
    # A host proxy can intercept flutter_tester's loopback WebSocket.
    env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
      NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test "--dart-define=TEAPOD_CORE=$selected_core"
    ;;
  clean) flutter clean ;;
  *) echo 'Usage: ./build.sh {binaries|release|debug|aab|run|run-release|test|clean}' >&2; exit 2 ;;
esac
