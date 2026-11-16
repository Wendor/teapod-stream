#!/usr/bin/env bash
# ============================================================================
# build.sh — builds the teapod-tun2socks AAR via gomobile bind
# ============================================================================
# This script compiles the Go code into an Android .aar library
# for all major Android architectures.
#
# Requirements:
#   - Go 1.25.5+
#   - gomobile (go install golang.org/x/mobile/cmd/gomobile@latest)
#   - Android NDK (ANDROID_NDK_HOME or ANDROID_HOME variable)
#   - JDK 17+ (JAVA_HOME)
#
# Usage:
#   ./build.sh              # Build for all architectures
#   ./build.sh arm64        # arm64-v8a only
#   ./build.sh clean        # Clean output files
# ============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_MODULE_DIR="${SCRIPT_DIR}/go"
OUTPUT_DIR="${SCRIPT_DIR}/output"
AAR_NAME="teapod-tun2socks"

# Shared project version — the single source: teapodstream/pubspec.yaml
PUBSPEC="${SCRIPT_DIR}/../teapodstream/pubspec.yaml"
[ -f "${PUBSPEC}" ] || { echo "ERROR: ${PUBSPEC} not found (the version is taken from teapodstream)"; exit 1; }
VERSION=$(awk '/^version:/{split($2,v,"+"); print v[1]; exit}' "${PUBSPEC}")
[ -n "${VERSION}" ] || { echo "ERROR: couldn't read version from ${PUBSPEC}"; exit 1; }
MIN_ANDROID_API=29

# Architectures to build (gomobile targets)
ARCH_ARM64="arm64"   # -> arm64-v8a
ARCH_ARM="arm"       # -> armeabi-v7a
ARCH_X86_64="amd64"  # -> x86_64

ALL_ARCH="${ARCH_ARM64},${ARCH_ARM},${ARCH_X86_64}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
log()  { echo -e "${CYAN}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
err()  { echo -e "${RED}✗ $*${NC}"; exit 1; }

# --- Prerequisite check ---

check_prerequisites() {
    echo "=== Checking prerequisites ==="

    if ! command -v go &> /dev/null; then
        echo "ERROR: go not found. Install Go 1.25.5+"
        exit 1
    fi

    GO_VERSION=$(go version | awk '{print $3}')
    echo "Go version: ${GO_VERSION}"

    if ! command -v gomobile &> /dev/null; then
        echo "gomobile not found. Installing..."
        go install golang.org/x/mobile/cmd/gomobile@latest
        go install golang.org/x/mobile/cmd/gobind@latest
    fi

    GOMOBILE_VERSION=$(gomobile version 2>/dev/null || echo "unknown")
    echo "gomobile: ${GOMOBILE_VERSION}"

    # NDK check
    if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "${ANDROID_NDK_HOME}" ]; then
        echo "ANDROID_NDK_HOME: ${ANDROID_NDK_HOME}"
    elif [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}/ndk" ]; then
        ANDROID_NDK_HOME=$(ls -d "${ANDROID_HOME}/ndk"/* 2>/dev/null | head -1)
        if [ -n "${ANDROID_NDK_HOME}" ]; then
            export ANDROID_NDK_HOME
            echo "NDK found via ANDROID_HOME: ${ANDROID_NDK_HOME}"
        else
            echo "WARNING: NDK not found. Install the Android NDK or set ANDROID_NDK_HOME"
        fi
    else
        echo "WARNING: ANDROID_NDK_HOME is not set. gomobile may not find the NDK."
        echo "Recommended: export ANDROID_NDK_HOME=\$HOME/Android/Sdk/ndk/<version>"
    fi

    if ! command -v javac &> /dev/null; then
        echo "WARNING: javac not found. Make sure JAVA_HOME is set."
    fi

    echo ""
}

# --- Clean ---

clean() {
    echo "=== Cleaning ==="
    rm -rf "${OUTPUT_DIR}"
    rm -rf "${GO_MODULE_DIR}/go.sum"
    echo "Cleaned."
}

# --- Fetching dependencies ---

fetch_deps() {
    echo "=== Fetching Go dependencies ==="
    cd "${GO_MODULE_DIR}"

    go mod download
    go mod tidy

    echo "Dependencies fetched."
    echo ""
}

# --- Building the AAR ---

build_aar() {
    local arches="${1:-$ALL_ARCH}"

    echo "=== Building the AAR ==="
    echo "Architectures: ${arches}"
    echo "Minimum Android API: ${MIN_ANDROID_API}"
    echo "Output directory: ${OUTPUT_DIR}"
    echo ""

    mkdir -p "${OUTPUT_DIR}"

    cd "${GO_MODULE_DIR}"

    echo "Running gomobile bind..."
    echo "Go architectures: ${arches}"
    echo "Target: android/${arches//,/,android/}"
    echo "From directory: $(pwd)"

    # Run gomobile bind
    # -v for debugging, -ldflags="-s -w" to strip symbols, and -trimpath
    gomobile bind \
        -v \
        -ldflags="-s -w" \
        -trimpath \
        -target="android/${arches//,/,android/}" \
        -androidapi="${MIN_ANDROID_API}" \
        -o "${OUTPUT_DIR}/${AAR_NAME}.aar" \
        ./...

    if [ ! -f "${OUTPUT_DIR}/${AAR_NAME}.aar" ]; then
        echo "ERROR: the base Go AAR was not created at ${OUTPUT_DIR}/${AAR_NAME}.aar"
        echo "Output folder contents:"
        ls -la "${OUTPUT_DIR}"
        exit 1
    fi

    # 2. Build the Kotlin wrapper and merge it with the Go AAR for each architecture
    echo ""
    echo "=== Building the Kotlin wrapper and the release AARs ==="

    local KOTLIN_DIR="${SCRIPT_DIR}/kotlin"
    cd "${KOTLIN_DIR}"

    if [ ! -f "./gradlew" ]; then
        echo "WARNING: gradlew not found. Trying to create it..."
        # Look for a system gradle to create the wrapper
        local system_gradle=""
        if command -v gradle &> /dev/null; then
            system_gradle="gradle"
        else
            system_gradle=$(find ~/.gradle/wrapper/dists -name "gradle" -type f -path "*/bin/gradle" 2>/dev/null | head -1)
        fi
        
        if [ -n "${system_gradle}" ]; then
            "${system_gradle}" wrapper
        else
            echo "ERROR: Gradle not found! Install Gradle or create the wrapper manually."
            exit 1
        fi
    fi

    # Android architectures for the final packaging
    local ANDROID_ARCHES=()
    # Pad with spaces for an exact substring match
    local arches_with_spaces=" ${arches//,/ } "
    if [[ "${arches_with_spaces}" == *" ${ARCH_ARM64} "* ]]; then ANDROID_ARCHES+=("arm64-v8a"); fi
    if [[ "${arches_with_spaces}" == *" ${ARCH_ARM} "* ]]; then ANDROID_ARCHES+=("armeabi-v7a"); fi
    if [[ "${arches_with_spaces}" == *" ${ARCH_X86_64} "* ]]; then ANDROID_ARCHES+=("x86_64"); fi
    
    # Build mode: per-architecture AARs only
    echo "--- Cleaning before the build ---"
    ./gradlew clean --no-daemon

    # Build for each selected architecture
    for arch in "${ANDROID_ARCHES[@]}"; do
        echo ""
        echo "--- Building the AAR for architecture: ${arch} ---"
        # Pass the arch parameter to Gradle
        ./gradlew assembleFatAar -PtargetArch="${arch}" -PlibraryVersion="${VERSION}" --no-daemon
    done

    # 3. Copy the results to output
    echo ""
    echo "=== Copying the results to ${OUTPUT_DIR} ==="
    
    local version="${VERSION}"

    # Remove the temporary base Go AAR from output
    rm -f "${OUTPUT_DIR}/${AAR_NAME}.aar"
    
    local GRADLE_OUTPUT_DIR="${KOTLIN_DIR}/build/outputs/fat-aar"
    
    # Copy only the per-architecture libraries
    for arch in "${ANDROID_ARCHES[@]}"; do
        local arch_aar="${GRADLE_OUTPUT_DIR}/${AAR_NAME}-${arch}-${version}.aar"
        if [ -f "${arch_aar}" ]; then
            cp "${arch_aar}" "${OUTPUT_DIR}/"
            local size
            size=$(du -h "${OUTPUT_DIR}/${AAR_NAME}-${arch}-${version}.aar" | cut -f1)
            echo "AAR for ${arch}: ${OUTPUT_DIR}/${AAR_NAME}-${arch}-${version}.aar (${size})"
        fi
    done

    echo ""
    echo "=== Build finished ==="
}


# --- Publishing to GitHub ---

push_to_github() {
    echo "=== Publishing to GitHub ==="

    if ! command -v gh &> /dev/null; then
        echo "ERROR: gh CLI not found. Install it: brew install gh"
        exit 1
    fi

    local version="${VERSION}"
    local tag="v${version}"

    echo "Version: ${version}"
    echo "Tag: ${tag}"

    # Check that the built files exist
    local files=()
    # Find all AARs of the current version
    for f in "${OUTPUT_DIR}"/*"-${version}.aar"; do
        if [ -f "$f" ]; then
            files+=("$f")
        fi
    done

    # Add sources.jar if present
    local sources_jar="${OUTPUT_DIR}/${AAR_NAME}-sources.jar"
    if [ -f "${sources_jar}" ]; then
        files+=("${sources_jar}")
    fi

    if [ "${#files[@]}" -eq 0 ]; then
        echo "ERROR: no files to publish in ${OUTPUT_DIR}. Run the build first: ./build.sh"
        exit 1
    fi

    echo "Files to upload:"
    for f in "${files[@]}"; do
        echo "  - $(basename "$f")"
    done
    echo ""

    # Create the release and upload the files
    # --generate-notes builds the release description from the commits
    if gh release view "$tag" &>/dev/null; then
      warn "Release $tag already exists, updating..."
      gh release upload "$tag" "${files[@]}" --clobber
    else
      gh release create "$tag" \
        --title "TeapodStream $version" \
        --generate-notes \
        "${files[@]}"
    fi
    echo ""
    echo "=== Publishing finished ==="
}


# --- Info output ---

print_info() {
    local version="${VERSION}"

    echo ""
    echo "=========================================================="
    echo " teapod-tun2socks AAR v${version} — Info"
    echo "=========================================================="
    echo ""
    echo "Output files in: ${OUTPUT_DIR}/"
    echo "  - ${AAR_NAME}-arm64-v8a-${version}.aar"
    echo "  - ${AAR_NAME}-armeabi-v7a-${version}.aar"
    echo "  - ${AAR_NAME}-x86_64-${version}.aar"
    echo "=========================================================="
}

# --- Main ---

main() {
    local command="${1:-all}"

    case "${command}" in
        clean)
            clean
            ;;
        deps)
            fetch_deps
            ;;
        push)
            push_to_github
            ;;
        arm64)
            check_prerequisites
            fetch_deps
            # Build arm64-v8a only
            build_aar "${ARCH_ARM64}"
            ;;
        arm)
            check_prerequisites
            fetch_deps
            # Build armeabi-v7a only
            build_aar "${ARCH_ARM}"
            ;;
        x86_64)
            check_prerequisites
            fetch_deps
            # Build x86_64 only
            build_aar "${ARCH_X86_64}"
            ;;
        all)
            check_prerequisites
            fetch_deps
            build_aar "${ALL_ARCH}"
            print_info
            ;;
        *)
            echo "Usage: $0 {all|arm64|arm|x86_64|push|deps|clean}"
            echo ""
            echo "  all      — build all architectures (per-architecture AARs)"
            echo "  arm64    — arm64-v8a only"
            echo "  arm      — armeabi-v7a only"
            echo "  x86_64   — x86_64 only"
            echo "  push     — publish the built files to a GitHub Release (v<version>)"
            echo "  deps     — fetch Go dependencies"
            echo "  clean    — remove output files"
            exit 1
            ;;
    esac
}

main "$@"
