#!/usr/bin/env bash
# /bin/bash
#
# pi-config setup / launch script
#
# Specs:
# - tests if /pi-config, /pi-extensions and /app folder exists, errors out if not
# - tests if /pi-config/.pi/agent exists, if not copy $HOME/.pi to /pi-config/.pi and warn about pi-config initialization
# - teste if /pi-extensions/.bun exists, if not  copy $HOME/.bun to /pi-extensions/.bun and warn about pi-extensions initialization
# - make sure that /pi-extensions/.bun/bin and $HOME/.local/bin are present or added to PATH
# - tests if /app/.bun and /app/.pi/agent folders exists, creates them if not
# - if all is ok, start pi-web agent with -p 8080 -H 0.0.0.0 --no-open
set -euo pipefail

source $HOME/.bashrc

# ---------------------------------------------------------------------------
# Set up some colors for warnings / errors (only if stdout is a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    YELLOW='\033[1;33m'
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    NC='\033[0m'
else
    YELLOW=''
    RED=''
    GREEN=''
    NC=''
fi

warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$*"; }

# ---------------------------------------------------------------------------
# 1) Test that /pi-config, /pi-extensions and /app exist -> error out if not
# ---------------------------------------------------------------------------
REQUIRED_DIRS=(/pi-config /pi-extensions /app)
MISSING=0
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        error "Required directory '$dir' does not exist."
        MISSING=1
    fi
done
if [ "$MISSING" -ne 0 ]; then
    error "One or more required directories are missing. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2) Test if /pi-config/.pi/agent exists; if not copy $HOME/.pi to
#    /pi-config/.pi and warn about pi-config initialization
# ---------------------------------------------------------------------------
if [ ! -d /pi-config/.pi/agent ]; then
    if [ -d $HOME/.pi ]; then
        cp -a $HOME/.pi /pi-config/.pi
    else
        mkdir -p /pi-config/.pi/agent
    fi
    warn "pi-config initialization: copied '$HOME/.pi' to '/pi-config/.pi'"
fi

# ---------------------------------------------------------------------------
# 3) Test if /pi-extensions/.bun exists; if not copy $HOME/.bun to
#    /pi-extensions/.bun and warn about pi-extensions initialization
# ---------------------------------------------------------------------------
if [ ! -d /pi-extensions/.bun ]; then
    if [ -d $HOME/.bun ]; then
        cp -a $HOME/.bun /pi-extensions/.bun
    else
        mkdir -p /pi-extensions/.bun
    fi
    warn "pi-extensions initialization: copied '$HOME/.bun' to '/pi-extensions/.bun'"
fi

# ---------------------------------------------------------------------------
# 4) Make sure /pi-extensions/.bun/bin and $HOME/.local/bin are present
#    or added to PATH
# ---------------------------------------------------------------------------
add_to_path() {
    local dir="$1"
    if [ -d "$dir" ]; then
        # Remove any existing entry to avoid duplicates, then prepend
        PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$dir" | paste -sd: -)
        PATH="$dir:$PATH"
        export PATH
    else
        warn "'$dir' is missing; cannot add to PATH."
    fi
}

add_to_path /pi-extensions/.bun/bin
add_to_path $HOME/.bun/bin
add_to_path $HOME/.local/bin

# ---------------------------------------------------------------------------
# 5) Test if /app/.bun and /app/.pi/agent exist; create them if not
# ---------------------------------------------------------------------------
mkdir -p /app/.bun
mkdir -p /app/.pi/agent
info "Ensured /app/.bun and /app/.pi/agent exist."

# ---------------------------------------------------------------------------
# 6) If all is ok, start pi-web agent with -p $HTTP_PORT -H $IP_ADDR --no-open
# ---------------------------------------------------------------------------
info "All checks passed. Starting pi-web agent..."
info "Running as $(whoami)"
info "bun is $(which bun)"
info "PATH is $PATH"
bun --bun run pi-web -H $IP_ADDR -p $HTTP_PORT --no-open
