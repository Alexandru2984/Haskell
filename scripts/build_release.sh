#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
toolchain_home="$(getent passwd "$(id -u)" | cut -d: -f6)"
PATH="${PATH}:${toolchain_home}/.ghcup/bin"
export PATH
build_dir="${BUILD_DIR:-dist-review}"
if [[ "$build_dir" == dist-newstyle* ]]; then
  echo 'Refusing to build into the legacy production executable directory.' >&2
  exit 1
fi
cabal build exe:api-contract-monitor --builddir="$build_dir" -j4
cabal test all --builddir="$build_dir" --test-show-details=direct
git diff --quiet HEAD || { echo "Commit reviewed changes before packaging a release." >&2; exit 1; }
revision="$(git rev-parse --short=12 HEAD)"
release_dir="releases/${revision}"
if [[ -e "$release_dir" ]]; then
  echo 'Release directory already exists; use a new commit for a new release.' >&2
  exit 1
fi
binary="$(cabal list-bin exe:api-contract-monitor --builddir="$build_dir")"
mkdir -p "$release_dir/public"
install -m755 "$binary" "$release_dir/api-contract-monitor"
cp -R public/assets "$release_dir/public/"
cp public/robots.txt "$release_dir/public/"
git rev-parse HEAD > "$release_dir/REVISION"
(cd "$release_dir" && sha256sum api-contract-monitor public/robots.txt public/assets/* > SHA256SUMS)
echo "Verified release candidate: $release_dir"
