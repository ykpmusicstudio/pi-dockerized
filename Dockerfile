FROM ubuntu:26.04@sha256:678c6550cc43645e08669028bc177f50be4e7c5b8cca677067b1914d4afc7a03 AS base

ENV DEBIAN_FRONTEND=noninteractive

USER root
# Install required system tools
# NOTE: sudo is intentionally NOT installed. The agent (ubuntu user) must
# never be able to escalate to root — see doc/insights-and-reco.md.
RUN apt-get update && apt-get install -y --no-install-recommends \
    fd-find \
    ripgrep \
    unzip \
    tmux \
    curl \
    ca-certificates \
    build-essential \
    git \
    openssh-client \
    python3 \
    python3-pip \
 && rm -rf /var/lib/apt/lists/*

# Lock the root account: no password, no login, no su/sudo path.
# The agent runs as 'ubuntu' and must never gain root privileges.
RUN usermod -L root \
 && passwd -l root \
 && usermod -s /usr/sbin/nologin root

# Volume mount points: global pi config, bun extensions, workspace
RUN mkdir -p /pi-config /pi-extensions /app

# give ubuntu user rw access to volumes
RUN chown ubuntu:ubuntu /pi-config && chown ubuntu:ubuntu /pi-extensions && chown ubuntu:ubuntu /app

FROM base AS build1

ENV HOME=/home/ubuntu

USER ubuntu

# Prepare SSH configuration
RUN mkdir -p $HOME/.ssh \
 && touch $HOME/.ssh/known_hosts

# Preload GitHub host keys (non-interactive Git usage)
RUN ssh-keyscan -T 5 github.com 2>/dev/null >> $HOME/.ssh/known_hosts || true

# configure tmux
COPY --chown=ubuntu:ubuntu .tmux.conf $HOME/.tmux.conf

# Install rust (pinned to 1.97.1 with minimal profile)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.97.1 --profile minimal
# Make cargo available in interactive / SSH shells
RUN echo 'source $HOME/.cargo/env' >> $HOME/.bashrc

# configure local .pi folder (image defaults, renamed to .init in final stage)
RUN mkdir -p $HOME/.pi/agent
# create bun install target (image defaults, renamed to .init in final stage)
RUN mkdir -p $HOME/.bun

# Install bun (pinned to v1.3.14)
RUN curl -fsSL https://bun.sh/install | bash -s -- bun-v1.3.14
# Verify bun binary integrity (x86_64 AVX2 build hash)
RUN sha256sum $HOME/.bun/bin/bun | grep -q 9fd36f87e4b90b07632b987a2e4ec81ca15a62c81bf983190cea6d715be2ad74 || \
  { echo "WARNING: bun checksum mismatch (may be baseline/arch variant, verify expected hash)"; }

# Install uv (Python package manager)
# uv is a Rust binary. The installer places it in $CARGO_HOME/bin
# (~/.cargo/bin) when cargo is present, else ~/.local/bin — both are on PATH.
RUN curl -fsSL https://astral.sh/uv/install.sh | sh -s -- --no-modify-path
# Verify uv is installed and on PATH
RUN bash -c "export PATH=$HOME/.cargo/bin:$HOME/.local/bin:$PATH && uv --version"

# configure fake npm as an alias to bun
RUN mkdir -p ~/.local/bin
COPY --chmod=755 --chown=ubuntu:ubuntu fake_npm $HOME/.local/bin/npm

FROM build1 AS final

USER ubuntu

# Install Pi coding agent (pinned)
COPY --chmod=555 --chown=ubuntu:ubuntu settings.json $HOME/.pi/agent/settings.json
RUN bash -c "export PATH=$PATH:$HOME:$HOME/.bun/bin && bun add -g --ignore-scripts @earendil-works/pi-coding-agent@0.84.2"
# Install pi-web (pinned)
RUN bash -c "export PATH=$PATH:$HOME/.local/bin:$HOME/.bun/bin && bun add -g @agegr/pi-web@0.8.9"

# Rename the bun-global pi executables and expose them through wrapper scripts
# that force the bun runtime (bun x --bun).
# Note: 'bunx' is a symlink to 'bun' with an absolute path that breaks after
# the .init → volume copy. Keeping 'bun x' as a defense — both work when
# the ~/.bun symlink is restored (see startup.sh §5).
RUN test -f $HOME/.bun/bin/pi && mv $HOME/.bun/bin/pi $HOME/.bun/bin/pi.npm
RUN printf '#!/bin/bash\nbun x --bun pi.npm "$@"\n' > $HOME/.local/bin/pi
RUN test -f $HOME/.bun/bin/pi-web && mv $HOME/.bun/bin/pi-web $HOME/.bun/bin/pi-web.npm
RUN printf '#!/bin/bash\nbun x --bun pi-web.npm "$@"\n' > $HOME/.local/bin/pi-web
RUN chmod u+x $HOME/.local/bin/pi
RUN chmod u+x $HOME/.local/bin/pi-web

# Pre-fetch pi package updates into the image defaults
RUN bash -c "export PATH=$PATH:$HOME/.local/bin:$HOME/.bun/bin && pi update || :"

# Add config.json for pi-web
RUN mkdir $HOME/.pi-web.init
COPY --chmod=555 --chown=ubuntu:ubuntu config.json $HOME/.pi-web.init/config.json

# Add entrypoint script
COPY --chmod=555 --chown=ubuntu:ubuntu startup.sh $HOME/startup.sh

# configure global .bunfig
COPY --chown=ubuntu:ubuntu .bunfig.toml $HOME/.bunfig.toml

# ---------------------------------------------------------------------------
# Runtime environment: pi config and bun extensions live on the volumes.
# PATH is defined once here (docker ENV) and mirrored in .bashrc for SSH
# login sessions. startup.sh relies on it; no symlinks are used.
# ---------------------------------------------------------------------------
ENV PI_CODING_AGENT_DIR=/pi-config
ENV BUN_INSTALL=/pi-extensions
ENV PATH="/home/ubuntu/.local/bin:/home/ubuntu/.cargo/bin:/pi-extensions/bin:${PATH}"

# Keep .bashrc coherent with the runtime ENV for interactive / SSH sessions
RUN echo 'export PATH=$HOME/.local/bin:$HOME/.cargo/bin:/pi-extensions/bin:$PATH' >> $HOME/.bashrc

# Rename live dirs to .init: startup.sh copies these into the volumes
# when they are empty or corrupt.
RUN mv $HOME/.pi $HOME/.pi.init \
 && mv $HOME/.bun $HOME/.bun.init

WORKDIR /app

# entry point is pi-web
ENTRYPOINT ["/bin/bash","-c","$HOME/startup.sh"]
