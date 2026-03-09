#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

pkg_id="${1:-}"
[ -n "$pkg_id" ] || fail "usage: $0 <package-id>"

require_cmd bash curl git rsync make find grep sed awk
source_lock

pkg_name="$(package_field "$pkg_id" PACKAGE_NAME)"
[ -n "$pkg_name" ] || fail "unknown package id: $pkg_id"

note "build package $pkg_id ($pkg_name)"
ensure_sdk
mkdir -p "$TMP_DIR" "$ARTIFACTS_DIR"

clean_sdk_package_state "$pkg_name"
stage_package_into_sdk "$pkg_id"
render_package_config "$pkg_name"

(
  cd "$SDK_DIR"
  note "make defconfig"
  make defconfig >/dev/null
  note "compile $pkg_name"
  make "package/$pkg_name/compile" -j"$JOBS" V=s
)

collect_apk_artifacts "$pkg_name"
note "artifacts at $ARTIFACTS_DIR/$pkg_name"
