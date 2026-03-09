# IPQ60XX APK Feed Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a dedicated repository that compiles `luci-app-podman` and `luci-app-tailscale-community` against the ImmortalWrt `qualcommax/ipq60xx` SDK and prepares a custom APK feed overlay.

**Architecture:** The repository pins upstream package source commits in a shell lock file, uses scripts to resolve SDK and verify dependency availability in official ImmortalWrt feeds, and drives package builds through GitHub Actions. Only the lightweight LuCI packages are compiled in phase one, while heavy runtime dependencies remain satisfied by official ImmortalWrt feeds.

**Tech Stack:** GitHub Actions, shell, ImmortalWrt SDK, APK index tooling, GitHub CLI

---

### Task 1: Create repository baseline

**Files:**
- Create: `.gitignore`
- Create: `docs/plans/2026-03-09-ipq60xx-apk-feed-design.md`
- Create: `docs/plans/2026-03-09-ipq60xx-apk-feed.md`

**Step 1: Add ignore rules**

```gitignore
/.worktrees/
/.cache/
/.tmp/
/.sdk/
/.artifacts/
```

**Step 2: Save design and implementation docs**

Run: `test -f docs/plans/2026-03-09-ipq60xx-apk-feed-design.md && test -f docs/plans/2026-03-09-ipq60xx-apk-feed.md`
Expected: command exits 0

**Step 3: Commit the baseline**

```bash
git add .gitignore docs/plans/2026-03-09-ipq60xx-apk-feed-design.md docs/plans/2026-03-09-ipq60xx-apk-feed.md
git commit -m "docs(plans): add apk feed design"
```

### Task 2: Create isolated workspace

**Files:**
- Modify: git worktree metadata only

**Step 1: Create implementation worktree**

```bash
git worktree add .worktrees/codex/bootstrap -b codex/bootstrap
```

**Step 2: Verify clean baseline**

Run: `git -C .worktrees/codex/bootstrap status --short --branch`
Expected: clean branch state

### Task 3: Implement feed metadata and helper scripts

**Files:**
- Create: `README.md`
- Create: `packages.lock`
- Create: `ci/lib.sh`
- Create: `ci/update_sources.sh`
- Create: `ci/verify_runtime_deps.sh`
- Create: `ci/build_package.sh`

**Step 1: Write lock file for upstream sources**

Include exact repo, branch, pinned commit, and source subdir for:
- `luci-app-podman`
- `luci-app-tailscale-community`

**Step 2: Write helper library**

Implement shared shell helpers to:
- source the lock file
- resolve package metadata by package id
- compute SDK URLs for `qualcommax/ipq60xx`

**Step 3: Write updater script**

Run: `./ci/update_sources.sh --check`
Expected: exits 0 and prints pinned versions without modifying files

**Step 4: Write dependency preflight**

Run: `./ci/verify_runtime_deps.sh`
Expected: confirms required official ImmortalWrt packages exist for `aarch64_cortex-a53`

### Task 4: Implement GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build-feed.yml`

**Step 1: Define triggers**

Include:
- `workflow_dispatch`
- `push` to `main`
- `schedule` for upstream refresh checks

**Step 2: Define build matrix**

Build:
- `luci-app-podman`
- `luci-app-tailscale-community`

**Step 3: Add scheduled update logic**

Scheduled run:
- refresh lock file
- auto-commit changes if upstream moved
- continue into build

**Step 4: Add build and artifact publication**

Build artifacts should include:
- compiled `.apk`
- optional `.ipk`
- feed metadata directory under `dist/all`

### Task 5: Validate locally and remotely

**Files:**
- Modify: as needed from validation feedback

**Step 1: Run local static validation**

```bash
bash -n ci/lib.sh ci/update_sources.sh ci/verify_runtime_deps.sh ci/build_package.sh
```

Expected: no syntax errors

**Step 2: Run dependency and source checks**

```bash
./ci/update_sources.sh --check
./ci/verify_runtime_deps.sh
```

Expected: both succeed

**Step 3: Run at least one local package build path test**

```bash
./ci/build_package.sh luci-app-tailscale-community
./ci/build_package.sh luci-app-podman
```

Expected: build output created or, if the environment is too constrained, a concrete failure point captured with logs

**Step 4: Commit and push**

```bash
git add .
git commit -m "feat(ci): bootstrap ipq60xx apk feed"
git push -u origin codex/bootstrap:main
```

**Step 5: Trigger GitHub Actions**

```bash
gh workflow run build-feed.yml --repo hotwa/openwrt-ipq60xx-apk-feed --ref main
gh run list --repo hotwa/openwrt-ipq60xx-apk-feed --workflow build-feed.yml --limit 5
```

Plan complete and saved to `docs/plans/2026-03-09-ipq60xx-apk-feed.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Current task will proceed in this session because the user explicitly requested immediate execution.
