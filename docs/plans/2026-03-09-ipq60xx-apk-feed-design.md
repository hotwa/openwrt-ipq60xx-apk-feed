# 2026-03-09 IPQ60XX APK Feed Design

## Goal
- Build a dedicated package feed repository for the `qualcommax/ipq60xx` target used by the current firmware pipeline.
- Keep GitHub Actions as the first execution environment because it is convenient and already proven by upstream single-package repositories.
- Fail over to Gitea/Woodpecker only if package compilation time or dependency closure makes GitHub Actions unreliable.

## Constraints
- Target scope is only the current main firmware target:
  - `qualcommax/ipq60xx`
  - runtime package architecture: `aarch64_cortex-a53`
- We need to avoid repeating full source firmware builds just to refresh two LuCI packages.
- We need a path that can later host a signed custom APK feed.

## Key Findings
- ImmortalWrt snapshot feeds for `aarch64_cortex-a53` already publish:
  - `tailscale.apk`
  - `podman.apk`
  - `luci-app-tailscale-community.apk`
- This means the first version of this repository does not need to rebuild `tailscale` or `podman` from source.
- The only package clearly missing from the official feed path we checked is `luci-app-podman`, so the first high-value custom build target is that package.
- Even so, we will keep both LuCI packages in this repository so the build system is symmetric and can override official versions if needed.

## Chosen Approach
- Create one dedicated repository, not separate repositories per package.
- Use the ImmortalWrt SDK for `qualcommax/ipq60xx` to compile only:
  - `luci-app-podman`
  - `luci-app-tailscale-community`
- Pin upstream source commits in a lock file.
- Add a scheduled updater that refreshes pinned commits when upstream package repositories change.
- Publish build artifacts as a small `all/` APK feed payload so the repository can later serve as a custom feed overlay.

## Why This First
- LuCI packages are `all` architecture packages and should compile much faster than rebuilding `tailscale` or `podman`.
- This gives a low-risk timing probe on GitHub Actions before spending effort moving anything to Gitea/Woodpecker.
- If this works reliably, the same repository shape can later be extended to heavier packages or mirrored into Gitea.

## Exit Criteria
- Repository contains a reproducible lock file and build scripts.
- GitHub Actions can build both LuCI packages for the IPQ60XX SDK baseline.
- Local validation proves the SDK URL, upstream source layout, and dependency preflight checks are correct.
- The repository is ready for scheduled upstream refreshes.
