#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Honor a build-local JDK without changing global Flutter configuration.
if [[ -n "${JAVA_HOME:-}" ]]; then
  export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.home=$JAVA_HOME"
fi

build_command="${1:-release}"
case "$build_command" in
  binaries) python3 scripts/fetch-rust-core.py ;;
  release|debug|aab|run|run-release)
    python3 scripts/fetch-rust-core.py
    flutter pub get
    case "$build_command" in
      release) flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi ;;
      debug) flutter build apk --debug --target-platform android-arm64,android-x64 --split-per-abi ;;
      aab) flutter build appbundle --release --target-platform android-arm64,android-x64 ;;
      run) flutter run ;;
      run-release) flutter run --release ;;
    esac
    ;;
  test)
    # A host proxy can intercept flutter_tester's loopback WebSocket.
    env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
      NO_PROXY=localhost,127.0.0.1,::1 no_proxy=localhost,127.0.0.1,::1 flutter test
    ;;
  clean) flutter clean ;;
  *) echo 'Usage: ./build.sh {binaries|release|debug|aab|run|run-release|test|clean}' >&2; exit 2 ;;
esac
