FROM ubuntu:latest as base

ENV DEBIAN_FRONTEND=noninteractive

# Install required system tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    fd-find \
    ripgrep \
    unzip \
    tmux \
    ripgrep \
    curl \
    ca-certificates \
    build-essential \
    git \
    openssh-client \
    sudo \
 && rm -rf /var/lib/apt/lists/*

# volumes are :
# - config: global pi config folder
# - bun: static bun storage
# - app: current workspace

# Create a non-root user
RUN if id ubuntu &>/dev/null; then \
       echo "user ubuntu already exists"; \
    else \
       useradd -m -s /bin/bash ubuntu; \
    fi
#RUN useradd -m -s /bin/bash ubuntu
RUN echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

# create /app folder for future overlay
RUN mkdir /app
# add configuration mountpoint that will contain .pi system-wide folder
RUN mkdir -p /config/.pi
RUN mkdir -p /config/.bun

WORKDIR /app

# Prepare SSH configuration
RUN mkdir -p $HOME/.ssh \
 && touch $HOME/.ssh/known_hosts

# Preload GitHub host keys (non-interactive Git usage)
RUN ssh-keyscan -T 5 github.com 2>/dev/null >> $HOME/.ssh/known_hosts || true

ENV HOME=/root
# configure tmux
COPY --chown=ubuntu:ubuntu .tmux.conf $HOME/.tmux.conf
ADD --chown=ubuntu:ubuntu .tmux/ $HOME/.tmux

# Install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN echo 'source $HOME/.cargo/env' >> $HOME/.bashrc

# add .pi folder as a link to /config
RUN ln -s /config/.pi $HOME/.pi
# create bun install target
RUN mkdir -p $HOME/.bun
RUN ln -s /config/.bun $HOME/.bun/install

# Install bun
RUN curl -fsSL https://bun.com/install | bash

# configure fake npm as an alias to bun
RUN mkdir -p ~/.local/bin
COPY --chown=ubuntu:ubuntu fake_npm $HOME/.local/bin/npm
RUN chmod u+x $HOME/.local/bin/npm

# Install npm
#RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
#ENV NVM_DIR=$HOME/.nvm
#RUN bash -c "source $HOME/.nvm/nvm.sh && nvm install 24"

# Install Pi coding agent
RUN bash -c "export PATH=$PATH:$HOME:$HOME/.bun/bin && bun add -g --ignore-scripts @earendil-works/pi-coding-agent"
# Replace the pi exec with bun statup script
RUN mv $HOME/.bun/bin/pi $HOME/.bun/pi.ori
RUN echo "#!/bin/bash\nbunx --bun pi.ori \"\$@\"" > $HOME/.local/bin/pi
RUN chmod u+x $HOME/.local/bin/pi
