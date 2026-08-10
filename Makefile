# Helper Makefile to simplify running the secure agent container
# Usage: make run

.PHONY: build run clean shell

IMAGE := pi-dockerized

# Detect User ID and Group ID to prevent permission issues on Linux
UID := $(shell id -u)
GID := $(shell id -g)
# set podman or docker
DKR := docker
#DKR := podman

TESTDIR := $(shell pwd)/.tests

# Create local data directory for persistence if using bind mount strategy
setup:
	rm -rf $(TESTDIR)/*
	mkdir -p ./.tests/pi-config
	mkdir -p ./.tests/pi-extensions
	mkdir -p ./.tests/app

# Build the podman image locally from source/npm
build:
	DOCKER_BUILDKIT=1 $(DKR) compose build

# Build without cache the podman image locally from source/npm
update:
	DOCKER_BUILDKIT=1 $(DKR) compose build --no-cache

# Run the agent in interactive mode
# Passes the current user's UID/GID to the container
run: setup
	UID=$(UID) GID=$(GID) $(DKR) compose run --rm $(IMAGE)

# Run the agent with arguments (e.g., make args="--help" run-args)
run-args: setup
	UID=$(UID) GID=$(GID) $(DKR) compose run --rm $(IMAGE) $(args)

# Access the container shell for debugging
shell: setup
	UID=$(UID) GID=$(GID) $(DKR) run -it --rm --userns=keep-id -v $(TESTDIR)/pi-config:/pi-config -v $(TESTDIR)/pi-extensions:/pi-extensions -v $(TESTDIR)/app:/app --entrypoint /bin/bash $(IMAGE)
	# UID=$(UID) GID=$(GID) $(DKR) compose run --entrypoint /bin/bash --rm $(IMAGE)

# Test build
test: setup
	UID=$(UID) GID=$(GID) $(DKR) run -it --rm --userns=keep-id -v $(TESTDIR)/pi-config:/pi-config -v $(TESTDIR)/pi-extensions:/pi-extensions -v $(TESTDIR)/app:/app $(IMAGE)

# Clean up stopped containers and networks
clean:
	$(DKR) compose down

