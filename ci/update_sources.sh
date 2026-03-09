#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

MODE="update"
if [ "${1:-}" = "--check" ]; then
  MODE="check"
fi

require_cmd curl awk sed git
source_lock

api_get_commit() {
  local repo="$1"
  local branch="$2"
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

  if [ -n "$token" ]; then
    curl -fsSL -H "Authorization: Bearer $token" "https://api.github.com/repos/$repo/commits/$branch" | sed -n 's/.*"sha": "\(.*\)".*/\1/p' | head -n 1
  else
    curl -fsSL "https://api.github.com/repos/$repo/commits/$branch" | sed -n 's/.*"sha": "\(.*\)".*/\1/p' | head -n 1
  fi
}

replace_lock_ref() {
  local var_name="$1"
  local new_ref="$2"
  sed -i.bak "s|^${var_name}=.*|${var_name}=${new_ref}|" "$LOCK_FILE"
  rm -f "$LOCK_FILE.bak"
}

changed=0
for pkg_id in $PACKAGE_IDS; do
  repo="$(package_field "$pkg_id" REPO)"
  branch="$(package_field "$pkg_id" BRANCH)"
  old_ref="$(package_field "$pkg_id" REF)"
  var_name="PKG_$(package_key "$pkg_id")_REF"
  new_ref="$(api_get_commit "$repo" "$branch")"

  [ -n "$new_ref" ] || fail "unable to resolve latest commit for $repo:$branch"
  printf '%s %s -> %s\n' "$pkg_id" "$old_ref" "$new_ref"

  if [ "$old_ref" != "$new_ref" ]; then
    changed=1
    if [ "$MODE" = "update" ]; then
      replace_lock_ref "$var_name" "$new_ref"
    fi
  fi
done

if [ "$MODE" = "check" ]; then
  [ "$changed" -eq 0 ] && note "lock file already up to date" || note "updates available"
else
  [ "$changed" -eq 0 ] && note "no lock updates written" || note "lock file updated"
fi
