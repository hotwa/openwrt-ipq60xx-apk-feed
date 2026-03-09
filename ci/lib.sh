#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${LOCK_FILE:-$ROOT_DIR/packages.lock}"
CACHE_DIR="${CACHE_DIR:-$ROOT_DIR/.cache}"
TMP_DIR="${TMP_DIR:-$ROOT_DIR/.tmp}"
SDK_DIR="${SDK_DIR:-$ROOT_DIR/.sdk/immortalwrt-sdk-ipq60xx}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/.artifacts}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_FORMATS="${BUILD_FORMATS:-apk}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

note() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || fail "missing command: $cmd"
  done
}

source_lock() {
  [ -f "$LOCK_FILE" ] || fail "lock file not found: $LOCK_FILE"
  # shellcheck disable=SC1090
  . "$LOCK_FILE"
}

package_key() {
  printf '%s' "$1" | tr '[:lower:]-.' '[:upper:]__'
}

package_field() {
  local pkg_id="$1"
  local field="$2"
  local var="PKG_$(package_key "$pkg_id")_${field}"
  printf '%s\n' "${!var:-}"
}

package_ids() {
  source_lock
  printf '%s\n' $PACKAGE_IDS
}

sdk_index_url() {
  source_lock
  printf '%s\n' "${SDK_BASE_URL%/}/"
}

sdk_filename() {
  local index_file="$CACHE_DIR/sdk-index.html"
  mkdir -p "$CACHE_DIR"
  curl -fsSL "$(sdk_index_url)" -o "$index_file"
  grep -o 'immortalwrt-sdk-qualcommax-ipq60xx[^"]*Linux-x86_64.tar.zst' "$index_file" | head -n 1
}

sdk_download_url() {
  local file
  file="$(sdk_filename)"
  [ -n "$file" ] || fail "unable to resolve SDK filename from $(sdk_index_url)"
  printf '%s%s\n' "$(sdk_index_url)" "$file"
}

ensure_sdk() {
  require_cmd curl tar zstd
  if [ -d "$SDK_DIR" ] && [ -f "$SDK_DIR/rules.mk" ]; then
    note "reuse SDK at $SDK_DIR"
    ensure_sdk_feeds
    return 0
  fi

  mkdir -p "$CACHE_DIR" "$(dirname "$SDK_DIR")"
  local sdk_file sdk_url
  sdk_url="$(sdk_download_url)"
  sdk_file="$CACHE_DIR/$(basename "$sdk_url")"

  if [ ! -f "$sdk_file" ]; then
    note "download SDK: $sdk_url"
    curl -fL "$sdk_url" -o "$sdk_file"
  else
    note "reuse cached SDK archive: $sdk_file"
  fi

  rm -rf "$SDK_DIR"
  mkdir -p "$(dirname "$SDK_DIR")"
  note "extract SDK"
  tar --zstd -xf "$sdk_file" -C "$(dirname "$SDK_DIR")"
  local extracted
  extracted="$(find "$(dirname "$SDK_DIR")" -maxdepth 1 -type d -name 'immortalwrt-sdk-*' | head -n 1)"
  [ -n "$extracted" ] || fail "extracted SDK directory not found"
  mv "$extracted" "$SDK_DIR"
  ensure_sdk_feeds
}

ensure_sdk_feeds() {
  require_cmd git make

  if [ -f "$SDK_DIR/feeds/luci/luci.mk" ] && [ -d "$SDK_DIR/feeds/packages" ]; then
    note "reuse initialized feeds"
    return 0
  fi

  note "initialize SDK feeds"
  (
    cd "$SDK_DIR"
    ./scripts/feeds update luci packages
    ./scripts/feeds install -a
  )
}

clone_package_source() {
  require_cmd git rsync
  local pkg_id="$1"
  local repo branch ref src_dir

  repo="$(package_field "$pkg_id" REPO)"
  branch="$(package_field "$pkg_id" BRANCH)"
  ref="$(package_field "$pkg_id" REF)"
  src_dir="$TMP_DIR/src/$pkg_id"

  [ -n "$repo" ] || fail "missing repo for package: $pkg_id"
  [ -n "$branch" ] || fail "missing branch for package: $pkg_id"
  [ -n "$ref" ] || fail "missing ref for package: $pkg_id"

  rm -rf "$src_dir"
  mkdir -p "$(dirname "$src_dir")"
  git clone --depth=1 --single-branch --branch "$branch" "https://github.com/$repo.git" "$src_dir" >/dev/null 2>&1
  git -C "$src_dir" fetch --depth=1 origin "$ref" >/dev/null 2>&1
  git -C "$src_dir" checkout --detach "$ref" >/dev/null 2>&1
  printf '%s\n' "$src_dir"
}

inject_dynamic_version_if_needed() {
  local makefile="$1"
  local ref="$2"

  if grep -q '^PKG_VERSION:=' "$makefile"; then
    return 0
  fi

  local date_ver rel
  date_ver="$(TZ=UTC date +%Y.%m.%d)"
  rel="1.git-${ref:0:12}"

  awk -v ver="$date_ver" -v rel="$rel" '
    {
      print $0
      if ($0 ~ /^include \$\(TOPDIR\)\/rules.mk$/) {
        print "PKG_VERSION:=" ver
        print "PKG_RELEASE:=" rel
      }
    }
  ' "$makefile" > "$makefile.tmp"
  mv "$makefile.tmp" "$makefile"
}

stage_package_into_sdk() {
  local pkg_id="$1"
  local src_dir subdir pkg_name dest_dir ref

  src_dir="$(clone_package_source "$pkg_id")"
  subdir="$(package_field "$pkg_id" SUBDIR)"
  pkg_name="$(package_field "$pkg_id" PACKAGE_NAME)"
  ref="$(package_field "$pkg_id" REF)"
  dest_dir="$SDK_DIR/package/$pkg_name"

  [ -n "$pkg_name" ] || fail "missing package name for package: $pkg_id"
  [ -n "$subdir" ] || fail "missing source subdir for package: $pkg_id"
  [ -d "$src_dir/$subdir" ] || fail "source subdir not found: $src_dir/$subdir"

  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  rsync -a --delete "$src_dir/$subdir/" "$dest_dir/"
  [ -f "$dest_dir/Makefile" ] || fail "package Makefile missing at $dest_dir/Makefile"
  inject_dynamic_version_if_needed "$dest_dir/Makefile" "$ref"
}

clean_sdk_package_state() {
  local pkg_name="$1"
  rm -f "$SDK_DIR/.config"
  rm -rf "$SDK_DIR/bin/packages"
  rm -rf "$SDK_DIR/bin/targets"
  rm -rf "$SDK_DIR/build_dir/target-"*
  rm -rf "$SDK_DIR/staging_dir/target-"*
  rm -rf "$SDK_DIR/tmp"
  rm -rf "$SDK_DIR/package/$pkg_name"
}

render_package_config() {
  local pkg_name="$1"
  local translation_pkg="${pkg_name#luci-app-}"

  cat > "$SDK_DIR/.config" <<EOF
CONFIG_TARGET_qualcommax=y
CONFIG_TARGET_qualcommax_ipq60xx=y
CONFIG_USE_APK=y
CONFIG_PACKAGE_${pkg_name}=m
CONFIG_PACKAGE_luci-i18n-${translation_pkg}-zh-cn=m
CONFIG_LUCI_LANG_zh_Hans=y
EOF
}

collect_apk_artifacts() {
  local pkg_name="$1"
  local output_dir="$ARTIFACTS_DIR/$pkg_name"
  local translation_pkg="${pkg_name#luci-app-}"

  rm -rf "$output_dir"
  mkdir -p "$output_dir"
  find "$SDK_DIR/bin/packages" -type f \( \
    -name "${pkg_name}*.apk" -o \
    -name "luci-i18n-${translation_pkg}-*.apk" \
  \) -exec cp -f {} "$output_dir/" \;

  find "$output_dir" -type f | grep -q . || fail "no APK artifacts collected for $pkg_name"
}

official_feed_page() {
  local section="$1"
  source_lock
  case "$section" in
    packages) printf '%s\n' "$OFFICIAL_PACKAGES_URL" ;;
    luci) printf '%s\n' "$OFFICIAL_LUCI_URL" ;;
    *) fail "unsupported feed section: $section" ;;
  esac
}

official_feed_contains() {
  local section="$1"
  local package_name="$2"
  local cache_file="$CACHE_DIR/${section}.html"

  mkdir -p "$CACHE_DIR"
  if [ ! -f "$cache_file" ]; then
    curl -fsSL "$(official_feed_page "$section")" -o "$cache_file"
  fi

  grep -Eq ">${package_name}-[^<]*\.apk<" "$cache_file"
}
