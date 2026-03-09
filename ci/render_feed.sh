#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

require_cmd find cp tar base64 xxd
source_lock

TARGET_DIR="$DIST_DIR/all"
mkdir -p "$TARGET_DIR"
find "$TARGET_DIR" -type f -delete 2>/dev/null || true

find "$ARTIFACTS_DIR" -type f -name '*.apk' -exec cp -f {} "$TARGET_DIR/" \;
find "$TARGET_DIR" -type f | grep -q . || fail "no APK artifacts to index"

if command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$TARGET_DIR:/work" -w /work alpine:3.20 sh -c \
    "apk add --no-cache apk-tools >/dev/null && apk index -o APKINDEX.tar.gz ./*.apk >/dev/null"
else
  fail "docker is required to build APKINDEX.tar.gz locally"
fi

if [ -n "${USIGN_KEY:-}" ]; then
  printf '%s\n' "$USIGN_KEY" > "$TARGET_DIR/key-build.sig"
else
  if ! command -v usign >/dev/null 2>&1; then
    fail "USIGN_KEY not set and local usign command missing"
  fi
  usign -G -s "$TARGET_DIR/key-build.sig" -p "$TARGET_DIR/key-build.pub" -c "Local build key" >/dev/null 2>&1
fi

if [ ! -f "$TARGET_DIR/key-build.pub" ]; then
  key_hex="$(tail -n 1 "$TARGET_DIR/key-build.sig" | base64 -d | xxd -p | tr -d '\n')"
  [ "${#key_hex}" -eq 208 ] || fail "invalid usign key length"
  {
    printf 'untrusted comment: public key %s\n' "${key_hex:64:16}"
    printf '%s%s%s' "${key_hex:0:4}" "${key_hex:64:16}" "${key_hex:144:64}" | xxd -r -p | base64
    printf '\n'
  } > "$TARGET_DIR/key-build.pub"
fi

if command -v usign >/dev/null 2>&1; then
  usign -S -m "$TARGET_DIR/APKINDEX.tar.gz" -s "$TARGET_DIR/key-build.sig" -x "$TARGET_DIR/APKINDEX.tar.gz.sig"
fi

rm -f "$TARGET_DIR/key-build.sig"
note "feed rendered at $TARGET_DIR"
