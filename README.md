# IPQ60XX APK Feed

Custom package feed repository for the current `qualcommax/ipq60xx` firmware target.

This repository is intentionally narrow:
- target: `qualcommax/ipq60xx`
- package architecture: `aarch64_cortex-a53`
- custom packages:
  - `luci-app-podman`
  - `luci-app-tailscale-community`

The first version only builds the LuCI packages. Runtime dependencies such as
`podman` and `tailscale` are expected to come from the official ImmortalWrt
snapshot feeds for the matching target baseline.

## Why only these packages

The current firmware pipeline times out when too many source-built packages are
included in a full firmware compile. These two LuCI packages are much lighter
than rebuilding `podman` or `tailscale` themselves, so they are a lower-risk
first step for moving package refreshes out of the main firmware build.

## Repository layout

- `packages.lock`
  - pinned upstream package source commits
- `ci/lib.sh`
  - shared helper functions
- `ci/update_sources.sh`
  - scheduled upstream commit refresher
- `ci/verify_runtime_deps.sh`
  - confirms required runtime dependencies exist in official ImmortalWrt feeds
- `ci/build_package.sh`
  - downloads the IPQ60XX SDK and compiles one package
- `ci/render_feed.sh`
  - assembles `dist/all` and creates `APKINDEX.tar.gz`
- `.github/workflows/build-feed.yml`
  - scheduled updater and package build workflow

## Local validation

```bash
bash -n ci/lib.sh ci/update_sources.sh ci/verify_runtime_deps.sh ci/build_package.sh ci/render_feed.sh
./ci/update_sources.sh --check
./ci/verify_runtime_deps.sh
./ci/build_package.sh luci-app-tailscale-community
./ci/build_package.sh luci-app-podman
```

## Feed usage

After GitHub Actions publishes the `dist/all` contents, the resulting feed can
be added as an overlay APK repository alongside the official ImmortalWrt feeds.
The repository public key is published next to `APKINDEX.tar.gz`.
