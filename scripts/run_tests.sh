#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
toolchain_home="$(getent passwd "$(id -u)" | cut -d: -f6)"
PATH="${PATH}:${toolchain_home}/.ghcup/bin"
export PATH
cabal test all --builddir="${BUILD_DIR:-dist-review}" --test-show-details=direct
