# pi-dockerized — Insights & Recommendations

## Overview

This document audits the `pi-dockerized` project — a containerized deployment of the
[pi-coding-agent](https://github.com/badlogic/pi-mono) with the
[pi-web](https://github.com/agegr/pi-web) web UI. The container is built for local development
(podman/docker-compose) and published to GitHub Container Registry.

---

## 1. Dockerfile — Structure & Multi-Stage

### 🟡 Multi-stage structure is a no-op (but Rust in final is intentional)

The `Dockerfile` declares three stages (`base`, `build1`, `final`) but `final` does `FROM build1`.
No artifacts are transferred between stages — the whole `build1` layer set is carried into the
final image.

> **Note (maintainer clarification):** the Rust toolchain in the final image is **intentional** —
> the agentic coder needs it to test/compile Rust builds inside the container. This changes the
> recommendation: Rust should stay in the runtime image; what should be optimized is *how* it is
> installed and cached.

#### Recommendation
- Keep Rust + `build-essential` in the final image.
- **Pin the Rust toolchain** instead of installing latest:
  ```dockerfile
  RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.85.0 --profile minimal
  ```
  or use a `rust-toolchain.toml` in the repo so the version is version-controlled.
- Consider moving rustup's installer caches / `rustup-download` caches out of the final image
  (`~/.rustup/downloads`, `~/.cargo/registry` are build-time only; `~/.cargo/bin` + `rustup`
  toolchain dirs are runtime-needed).
- If a slimmer image is ever wanted, the split would be: builder stage installs Rust, runtime
  stage copies the *toolchain* directories (`~/.rustup/toolchains/`, `~/.cargo/bin/`) rather than
  re-running the installer — but this is an optimization, not a removal of Rust.

> ✅ **Applied in PR #2** — Rust pinned to `1.97.1` with `--profile minimal`.

---

### 🟡 Floating base image

```dockerfile
FROM ubuntu:latest AS base
```

`ubuntu:latest` is a floating tag — the image changes without notice.

#### Recommendation
Pin to a specific release and digest:
```dockerfile
FROM ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03 AS base
```
Update the digest verified after testing on each base-image release.

> ✅ **Applied in PR #2** — pinned to `ubuntu:26.04@sha256:678c65...` (the LTS release that `ubuntu:latest` currently resolves to).

---

### 🔴 Bug: `ripgrep` listed twice in apt-get

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    fd-find \
    ripgrep \
    ...
    ripgrep \
```

Duplicated package name — harmless but indicates a tooling/authoring issue.

---

### 🔴 Supply-chain: curl | sh / curl | bash patterns

```dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN curl -fsSL https://bun.com/install | bash
```

No checksum pinning or signature verification. A compromise of the download server or a
MITM attack during build would inject untrusted code.

#### Recommendation
- Download the installer script, verify its hash against a known-good checksum, **then** execute it.
- Rust: pin the toolchain version in the installer command (see multi-stage note above).
- Bun: use a fixed release binary from `github.com/oven-sh/bun/releases` with checksum verification
  instead of the floating `bun.com/install` script.

> ✅ **Partially applied in PR #2** — Rust installer pinned to `--default-toolchain 1.97.1`,
> Bun installer pinned to `bun-v1.3.14` + binary sha256 verified. Download script integrity
> (checksuming the installer script itself) is not yet addressed.

---

### 🔴 Unpinned npm/bun packages

```dockerfile
RUN ... bun add -g --ignore-scripts @earendil-works/pi-coding-agent
RUN ... bun add -g @agegr/pi-web
```

Installs the latest version each time → non-reproducible builds.

#### Recommendation
Pin to specific versions:
```dockerfile
RUN ... bun add -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.2
RUN ... bun add -g @agegr/pi-web@0.8.9
```
Or use a lockfile (bun's `bun.lock` supports global installs).

> ✅ **Applied in PR #2** — pi-coding-agent pinned to `0.84.2`, pi-web pinned to `0.8.9`.

---

### 🟡 `pi update` runs during build

```dockerfile
RUN bash -c "... && pi update || :"
```

- **Network dependency at build time** — fails when offline; `|| :` silently swallows errors.
- **Embedded runtime state** — the update result is baked into the image; the image's agent version
  may drift from the runtime version.

#### Recommendation
Remove this line. Let `pi update` run naturally at container startup (it already happens
automatically when pi-web starts, unless `PI_OFFLINE=1`). Or move it to the entrypoint script.

---

### 🟡 Commented-out renaming of config directories

```dockerfile
#RUN mv $HOME/.pi $HOME/.pi.init
#RUN mv $HOME/.bun $HOME/.bun.init
```

These lines were intended to prepare the home directory so the startup script can symlink
`~/.pi`/`~/.bun` to the Docker volumes. Being commented out is the **root cause of a dual-path bug**
in the startup script (see §2).

#### Recommendation
Uncomment these lines, or restructure the approach so the Dockerfile itself places nothing
in `$HOME/.pi` / `$HOME/.bun` that would shadow a symlink.

---

## 2. Startup Script — Logic & Bugs

### 🔴 Bug: bun/pi config dual-path due to ~/.bun surviving in image

**The problem**:
1. Image has a real `$HOME/.bun/` directory (created by `RUN mkdir -p $HOME/.bun` + bun install).
2. `.bunfig.toml` sets `globalDir = "/pi-extensions/install"`.
3. At runtime, the startup script checks `if [ ! -d "$HOME/.bun" ]` — the dir **exists** (real dir
   in the image), so **no symlink is created**.
4. Therefore `~/.bun` stays a writable-layer directory inside the container, and the
   `/pi-extensions` volume is **never used** as bun's home.
5. The reinit logic copies `$HOME/.bun` **into** `/pi-extensions/.bun/` (nested), but bunfig
   expects `/pi-extensions/install` → **path mismatch**.
6. Result: build-time packages are found, runtime `bun add -g` writes to `/pi-extensions` (volume),
   and the two worlds drift. Restarting the container (wiping the writable layer) loses runtime
   installs but keeps the image's version.

**The intended design** (visible in comments): `~/.bun` should be renamed to `~/.bun.init` during
build, and at runtime symlinked to the `/pi-extensions` volume root.

#### Recommendation
Uncomment the `RUN mv` lines and fix the startup symlink creation to use the `.init` backup path.
Or, simpler: delete `$HOME/.bun` and `$HOME/.pi/agent` in the image and let the reinit logic always
recreate them from scratch.

---

### 🔴 Bug: Same symlink issue for `~/.pi/agent`

```bash
ln -s $PICONFIG_VOL $HOME/.pi/agent
```
If `~/.pi/agent` exists (it does — created in the Dockerfile), the symlink is skipped. The image's
static `settings.json` in `~/.pi/agent` takes precedence, and `PI_CODING_AGENT_DIR=/pi-config` points
to the volume. Which copy wins depends on pi's loading order — indeterminate.

---

### 🔴 Bug: `.tmux/plugins/` is empty

The `.tmux.conf` references TPM (Tmux Plugin Manager) and three plugins:
```
tmux-plugins/tpm
tmux-plugins/tmux-prefix-highlight
tmux-plugins/tmux-sensible
```

But `.tmux/plugins/tpm/` is an empty directory — TPM was never initialized. At tmux startup
the `run '~/.tmux/plugins/tpm/tpm'` command will fail silently, and no plugins are loaded.

#### Recommendation
- Add TPM as a git submodule:
  ```bash
  git submodule add https://github.com/tmux-plugins/tpm .tmux/plugins/tpm
  ```
- Or vendor the plugin scripts directly.
- Or remove TPM from the config if plugins aren't needed in the container.

---

### 🟡 `.bashrc` modifications may not take effect

```dockerfile
RUN echo 'source $HOME/.cargo/env' >> $HOME/.bashrc
RUN echo 'export PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
```

The entrypoint is `["/bin/bash","-c","$HOME/startup.sh"]` which runs bash **non-interactively**.
Ubuntu's default `/etc/bash.bashrc` often returns early in non-interactive mode (`case $- in
*i*) ;; *) return;; esac`). The startup script sources `$HOME/.bashrc` at the top, so the PATH
additions are available. This works but is fragile — a change in base image defaults could break it.

#### Recommendation
Set PATH directly in the Dockerfile via `ENV`:
```dockerfile
ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.bun/bin:${PATH}"
```
Then remove the `.bashrc` appends for PATH (keep `source $HOME/.cargo/env` if Rust is retained).

---

### 🟡 Default IP address

```bash
pi-web -H ${IP_ADDR:-127.0.0.0} -p ${HTTP_PORT:-8080} --no-open
```

`127.0.0.0` is a classful address (not `127.0.0.1`) — technically it works on Linux but is unusual.
The compose file sets `IP_ADDR=0.0.0.0`, so this only affects `docker run` without env vars.

#### Recommendation
```bash
pi-web -H ${IP_ADDR:-127.0.0.1} -p ${HTTP_PORT:-8080} --no-open
```

---

### 🟡 Port inconsistency

| Source | Port | Setting |
|---|---|---|
| docker-compose.yml | `8893:8893` | `HTTP_PORT=8893` |
| Makefile `DKR_ENV` | 8893 | hardcoded in `-e HTTP_PORT=8893` |
| startup.sh default | 8080 | `${HTTP_PORT:-8080}` |

These are consistent when compose/Makefile provide the env var, but the default in startup.sh
diverges from the expected port.

---

## 3. Docker Compose & Makefile

### 🟡 `.tests` directory in Docker build context

The workflow `docker build .` includes the entire repo context. The `.tests/` directory contains
bind-mount source for `pi-config`, `pi-extensions`, and `app` — potentially including:
- API keys / provider tokens stored in pi sessions
- SSH keys placed in `.tests/app/.ssh`
- pi sessions with sensitive chat history

**These end up in the image layers** if they exist at build time.

#### Recommendation
Add a `.dockerignore`:
```
.git
.gitignore
.tests/
.tmux/
doc/
README.md
LICENSE
makefile
build.sh
*.md
```

---

### 🟡 `make run` always triggers reinit

```makefile
setup:
	mkdir -p ./.tests/pi-config
	touch ./.tests/pi-config/.reinit
```

The `.reinit` marker is created **on every run**, causing the startup script to wipe `/pi-config`
and re-copy from the image. This is fine for testing but surprising — session data is lost.

#### Recommendation
Remove `.reinit` touch from `setup`, or gate it behind a separate target (`make reset`).

---

### 🟡 Compose volumes depend on host-side setup

The compose file uses `driver_opts: type: none, o: bind, device: ${PWD}/.tests/...`. The
directories must exist before `docker compose up`. The Makefile handles this, but a direct
`docker compose up` without `make setup` first will fail.

#### Recommendation
Document this dependency or have compose create the directories automatically (e.g., add an
`init` container, or use named volumes without bind).

---

## 4. GitHub Workflow

### 🟡 Only builds on `main` push

Docker images are only built when merging to `main`. PR branches are not validated by the build.

#### Recommendation
Add a trigger for PRs (`pull_request:`) with `push: false` to validate changes before merge:
```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

---

### 🟡 No BuildKit cache

Each workflow run starts from scratch — downloading all apt packages and npm/bun dependencies.

#### Recommendation
Use `docker/build-push-action` with GitHub Actions cache:
```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
- name: Build and push
  uses: docker/build-push-action@v6
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

This would cut CI build time from ~10 min to ~2 min.

---

### 🟡 No `.dockerignore`

Build context sent to the Docker daemon includes `.git` (history) and `.tests` (potentially large).
See §3 for `.dockerignore` recommendations.

---

## 5. Security

### 🟡 `sudo` in final image

```dockerfile
RUN apt-get install -y --no-install-recommends ... sudo
```

- `sudo` allows privilege escalation — an LLM-invoked `sudo` command could break out of the
  container or modify host-mounted volumes.
- `build-essential` and the Rust toolchain are **intentional** (needed to compile Rust/C code the
  agent is asked to build) — keep them.

#### Recommendation
- Keep `build-essential` + Rust (intentional).
- Evaluate whether `sudo` is truly needed: pi runs as `ubuntu`, and `apt` inside the container
  would otherwise fail. If the agent is expected to install system packages at runtime, `sudo`
  with a no-password rule for `ubuntu` (`sudo -n`) is a pragmatic compromise; otherwise drop it.
- Consider restricting `sudo` to specific commands (apt, pkg-config installs) rather than full
  `ALL` access.

---

### 🟡 SSH key mounts

The startup script copies `$REPO_ROOT/.ssh/*` to `~/.ssh/`. This means SSH private keys from the
host workspace are accessible inside the container.

- For the docker-compose dev workflow, these keys are bind-mounted from `./.tests/app/.ssh`.
- The pi agent could inadvertently expose them via tool calls.

This is a common pattern for agent containers and is acceptable with awareness.

---

## 6. UX & Maintainability

### 🟡 Minimal README

```markdown
# pi-dockerized
Contenerized version of my pi-agent
```

No setup instructions, no env var table, no architecture explanation.

---

### 🟡 No health check

The container runs a web server (pi-web) with no `HEALTHCHECK`.

#### Recommendation
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD curl -f http://localhost:${HTTP_PORT:-8893}/ || exit 1
```

---

### 🟡 No `.env` file template

The compose file references `${PWD}` and `${UID}`/`${GID}` but provides no `.env.example`.

### 🟡 Missing C libraries for GUI Rust builds (new insight)

The image ships `build-essential` (so Rust crates with C/C++ build scripts can compile), but it
**lacks `pkg-config` and the `-dev` system libraries** that common GUI toolkits need. Evidence:
`ewsim-ui` (eframe/egui, see sibling repo `ewsim2`) fails to compile in this environment with
`yeslogic-fontconfig-sys` → *"The pkg-config command could not be found"*.

If the agent is expected to build Rust projects with egui/eframe, wgpu, or similar, add:
```bash
sudo apt install pkg-config libfontconfig-dev libfreetype-dev libx11-dev libwayland-dev libegl-dev
```

#### Recommendation
Decide deliberately: either (a) keep the image lean and document that GUI builds require a runtime
`apt install` by the agent, or (b) pre-install `pkg-config` + fontconfig/freetype/X11/EGL `-dev`
packages (adds ~50–100 MB) so egui-based projects build out of the box.

---

## 7. Priority Summary

| Priority | Issue | Section | Status |
|---|---|---|---|
| 🔴 Higher | Supply chain: curl | sh without pinning | §1 | ✅ applied (partial) |
| 🔴 Higher | ~/.bun dual-path bug (symlink never created) | §2 | open |
| 🔴 Higher | ~/.pi/agent dual-path bug (symlink never created) | §2 | open |
| 🔴 Higher | .tmux/plugins empty — TPM broken | §2 | open |
| 🟡 Medium | Multi-stage no-op (Rust intentional — pin toolchain instead) | §1 | ✅ toolchain pinned |
| 🟡 Medium | Missing pkg-config/-dev libs for GUI Rust builds | §5 | open |
| 🟡 Medium | Floating base image | §1 | ✅ applied |
| 🟡 Medium | Unpinned npm/bun packages | §1 | ✅ applied |
| 🟡 Medium | .dockerignore missing — secrets in build context | §3 | open |
| 🟡 Medium | pi update in build (silent failure) | §1 | open |
| 🟡 Medium | No BuildKit cache — slow CI | §4 | open |
| 🟡 Medium | `make run` always wipes sessions | §3 | open |
| 🟡 Medium | Commented-out mv commands (dead code in intent) | §1,§2 | open |
| 🟢 Low | sudo (intentional-ish, restrict if kept) | §5 | open |
| 🟢 Low | ripgrep listed twice | §1 | open |
| 🟢 Low | Default IP 127.0.0.0 (should be .0.1) | §2 | open |
| 🟢 Low | Port inconsistency in defaults | §2 | open |
| 🟢 Low | Minimal README, no .env.example | §6 | open |
| 🟢 Low | No HEALTHCHECK | §6 | open |