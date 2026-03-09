#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

require_cmd curl grep
source_lock

status=0
for pkg_id in $PACKAGE_IDS; do
  deps="$(package_field "$pkg_id" RUNTIME_DEPS)"
  [ -n "$deps" ] || continue

  note "verify runtime deps for $pkg_id"
  for dep in $deps; do
    section="${dep%%:*}"
    package_name="${dep#*:}"
    if official_feed_contains "$section" "$package_name"; then
      printf '  OK  %s from %s\n' "$package_name" "$section"
    else
      printf '  MISS %s from %s\n' "$package_name" "$section" >&2
      status=1
    fi
  done
done

exit "$status"
