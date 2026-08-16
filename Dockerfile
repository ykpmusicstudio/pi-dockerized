FROM ubuntu:latest AS base
#FROM debian:stable-slim AS base

# debian created with root but executed with local user !!
# TODO Fix the user issue

ENV DEBIAN_FRONTEND=noninteractive

USER root
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

# create /app folder for future overlay
#RUN mkdir /app
# add configuration mountpoint that will contain .pi system-wide folder
#RUN mkdir -p /config/.pi
#RUN mkdir -p /config/.bun

# volumes are :
# - config: global pi config folder
# - bun: static bun storage
# - app: current workspace
#VOLUME ["/pi-config"]
#VOLUME ["/pi-extensions"]
#VOLUME ["/app"]
RUN mkdir -p /pi-config
RUN mkdir -p /pi-extensions
RUN mkdir -p /app

# give ubuntu user rw access to volumes
RUN chown ubuntu:ubuntu /pi-config && chown ubuntu:ubuntu /pi-extensions && chown ubuntu:ubuntu /app

FROM base AS build1

ENV HOME=/home/ubuntu
#ENV HOME=/root

USER ubuntu

# Prepare SSH configuration
RUN mkdir -p $HOME/.ssh \
 && touch $HOME/.ssh/known_hosts

# Preload GitHub host keys (non-interactive Git usage)
RUN ssh-keyscan -T 5 github.com 2>/dev/null >> $HOME/.ssh/known_hosts || true

# configure tmux
COPY --chown=ubuntu:ubuntu .tmux.conf $HOME/.tmux.conf
ADD .tmux/ $HOME/.tmux

# Install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
RUN echo 'source $HOME/.cargo/env' >> $HOME/.bashrc

# configure local .pi folder
RUN mkdir -p $HOME/.pi/agent
# create bun install target
RUN mkdir -p $HOME/.bun
#RUN ln -s /bun-config $HOME/.bun/install

# Install bun
RUN curl -fsSL https://bun.com/install | bash

# configure fake npm as an alias to bun
RUN mkdir -p ~/.local/bin
COPY --chmod=755 --chown=ubuntu:ubuntu fake_npm $HOME/.local/bin/npm
#COPY --chmod=755 fake_npm $HOME/.local/bin/npm
RUN chmod u+x $HOME/.local/bin/npm

FROM build1 AS final

USER ubuntu

# Install npm
#RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
#ENV NVM_DIR=$HOME/.nvm
#RUN bash -c "source $HOME/.nvm/nvm.sh && nvm install 24"

# Install Pi coding agent
COPY --chmod=555 --chown=ubuntu:ubuntu settings.json $HOME/.pi/agent/settings.json
RUN bash -c "export PATH=$PATH:$HOME:$HOME/.bun/bin && bun add -g --ignore-scripts @earendil-works/pi-coding-agent"
# Replace the pi exec with bun statup script

#RUN test -f $HOME/.bun/bin/pi && mv $HOME/.bun/bin/pi $HOME/.bun/bin/pi.ori
#RUN echo "#!/bin/bash\nbunx --bun pi.ori \"\$@\"" > $HOME/.local/bin/pi
#RUN chmod u+x $HOME/.local/bin/pi
# Install pi-web
#RUN bash -c "export PATH=$PATH:$HOME/.local/bin:$HOME/.bun/bin && npm install -g @agegr/pi-web"
RUN bash -c "export PATH=$PATH:$HOME/.local/bin:$HOME/.bun/bin && bun add -g @agegr/pi-web"

# Add $HOME/.local/bin to PATH
RUN echo 'export PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
RUN test -f $HOME/.bun/bin/pi && mv $HOME/.bun/bin/pi $HOME/.bun/bin/pi.npm
RUN echo "#!/bin/bash\nbunx --bun pi.npm \"\$@\"" > $HOME/.local/bin/pi
RUN test -f $HOME/.bun/bin/pi-web && mv $HOME/.bun/bin/pi-web $HOME/.bun/bin/pi-web.npm
RUN echo "#!/bin/bash\nbunx --bun pi-web.npm \"\$@\"" > $HOME/.local/bin/pi-web
RUN chmod u+x $HOME/.local/bin/pi
RUN chmod u+x $HOME/.local/bin/pi-web

# Test run pi
#RUN bash -c "export PATH=$PATH:$HOME/.local/bin:$HOME/.bun/bin && pi install git:github.com/edxeth/pi-tasks || :"
RUN bash -c "export PATH=$PATH:$HOME/.local/bin:$HOME/.bun/bin && pi update || :"

# Add config.json for pi-web
RUN mkdir $HOME/.pi-web.init
COPY --chmod=555 --chown=ubuntu:ubuntu config.json $HOME/.pi-web.init/config.json

# Add entrypoint script
COPY --chmod=555 --chown=ubuntu:ubuntu startup.sh $HOME/startup.sh
#COPY --chmod=755 startup.sh /

# Create simlinks for pi and pi-web in .bun/bin
#RUN cd $HOME/.bun/bin && ln -s ../install/global/node_modules/@earendil-works/pi-coding-agent/dist/cli.js pi
#RUN cd $HOME/.bun/bin && ln -s ../install/global/node_modules/@agegr/pi-web/bin/pi-web.js pi-web


# configure global .bunfig
COPY --chown=ubuntu:ubuntu .bunfig.toml $HOME/.bunfig.toml

# Now prepare for symlinking .pi and .bun to /pi-config and /pi-extensions volumes
#RUN mv $HOME/.pi $HOME/.pi.init
#RUN mv $HOME/.bun $HOME/.bun.init

WORKDIR /app
# Expose port 8080
#EXPOSE 8080

# entry point is pi-web -p 8080
ENTRYPOINT ["/bin/bash","-c","$HOME/startup.sh"]

