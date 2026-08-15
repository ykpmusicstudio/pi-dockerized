# Helper Makefile to simplify running the secure agent container
# Usage: make run

.PHONY: build run clean shell

IMAGE := localhost/ykpmusicstudio/pi-dockerized

# Detect User ID and Group ID to prevent permission issues on Linux
UID := $(shell id -u)
GID := $(shell id -g)
# set podman or docker
DKR_COMPOSE := docker-compose
DKR_RUN := docker
USR_FLAG := 
#DKR_COMPOSE := podman compose
#DKR_RUN := podman
#USR_FLAG := "--userns=keep-id"

TESTDIR := $(shell pwd)/.tests
DKR_ENV := -e REPO_ROOT=/app -e PI_WEB_ALLOWED_HOSTS=127.0.0.1 -e PI_CODING_AGENT_DIR=/pi-config -e PI_WEB_CONFIG=/pi-config/.pi-web -e IP_ADDR=0.0.0.0 -e HTTP_PORT=8893
DKR_VOL := -v $(TESTDIR)/pi-config:/pi-config -v $(TESTDIR)/pi-extensions:/pi-extensions -v $(TESTDIR)/app:/app

# Create local data directory for persistence if using bind mount strategy
setup:
	#rm -rf $(TESTDIR)/*
	mkdir -p ./.tests/pi-config
	mkdir -p ./.tests/pi-extensions
	mkdir -p ./.tests/app
	touch ./.tests/pi-config/.reinit

# Build the podman image locally from source/npm
build:
	DOCKER_BUILDKIT=1 $(DKR_COMPOSE) build

# Build without cache the podman image locally from source/npm
update:
	DOCKER_BUILDKIT=1 $(DKR_COMPOSE) build --no-cache

# Run the agent in interactive mode
# Passes the current user's UID/GID to the container
run: setup
	UID=$(UID) GID=$(GID) $(DKR_COMPOSE) run --rm $(IMAGE)

# Run the agent with arguments (e.g., make args="--help" run-args)
run-args: setup
	UID=$(UID) GID=$(GID) $(DKR_COMPOSE) run --rm $(IMAGE) $(args)

# Access the container shell for debugging
shell: 
	UID=$(UID) GID=$(GID) $(DKR_RUN) run -it --rm $(USR_FLAG) $(DKR_VOL) $(DKR_ENV) --entrypoint /bin/bash $(IMAGE)
	# UID=$(UID) GID=$(GID) $(DKR) compose run --entrypoint /bin/bash --rm $(IMAGE)

# Test build
test: setup
	UID=$(UID) GID=$(GID) $(DKR_RUN) run -it --rm $(USR_FLAG) -p 8893:8893 $(DKR_VOL) $(DKR_ENV) $(IMAGE)

# Clean up stopped containers and networks
clean:
	$(DKR_COMPOSE) down
	$(DKR_RUN) buildx prune
	$(DKR_RUN) image prune

