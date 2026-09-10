#!/usr/bin/env bash
set -euo pipefail
export TEAPOD_CORE=rust
exec "$(dirname "$0")/build.sh" "$@"
