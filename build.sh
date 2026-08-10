#!/bin/bash
set -e
DOCKER=podman

# copy tmux config in the context
#rm .tmux.conf
#rm -rf .tmux
#cp ~/.tmux.conf .
#cp -R ~/.tmux .

#$DOCKER build -v=$HOME/.config/picode:/config -t picode-ai:latest -f Dockerfile .
TESTS_DIRS=$(pwd)/.tests
#$DOCKER build -v=$TESTS_DIRS/pi-config:/pi-config -v=$TESTS_DIRS/pi-extensions:/pi-extensions -v=$TESTS_DIRS/app:/app -t pi-dockerized:latest -f Dockerfile .
$DOCKER build -t pi-dockerized:latest -f Dockerfile .

