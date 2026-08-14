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
info "Required dirs checks..."
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
info "Checking pi-config initialization state"
if [ ! -d /pi-config/.pi/agent ]; then
    if [ -d $HOME/.pi ]; then
        cp -a $HOME/.pi /pi-config/.pi
        mv $HOME/.pi $HOME/.pi.ori
        ln -s /pi-config/.pi $HOME/.pi
        warn "pi-config initialization: copied '$HOME/.pi' and linked to '/pi-config/.pi'"
    else
        mkdir -p /pi-config/.pi/agent
        error "No '$HOME'/.pi folder found, creating empty config"
    fi
fi

# ---------------------------------------------------------------------------
# 3) Test if /pi-extensions/.bun exists; if not copy $HOME/.bun to
#    /pi-extensions/.bun and warn about pi-extensions initialization
# ---------------------------------------------------------------------------
if [ ! -d /pi-extensions/.bun ]; then
    if [ -d $HOME/.bun ]; then
        cp -a $HOME/.bun /pi-extensions/.bun
        mv $HOME/.bun $HOME/.bun.ori
        ln -s /pi-extensions/.bun $HOME/.bun
        warn "pi-extensions initialization: copied '$HOME/.bun' and linked to '/pi-extensions/.bun'"
    else
        mkdir -p /pi-extensions/.bun
        error "No '$HOME'/.bun folder found, creating empty config"
    fi
fi

# ---------------------------------------------------------------------------
# 4) Make sure /pi-extensions/.bun/bin and $HOME/.local/bin are present
#    or added to PATH
# ---------------------------------------------------------------------------
add_to_path() {
    local dir="$1"
    if [ -d "$dir" ]; then
        info "adding $dir to PATH"
        # Remove any existing entry to avoid duplicates, then prepend
        PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$dir" | paste -sd: -)
        PATH="$dir:$PATH"
        export PATH
    else
        warn "'$dir' is missing; cannot add to PATH."
    fi
}

add_to_path $HOME/.bun/bin
add_to_path $HOME/.local/bin

# ---------------------------------------------------------------------------
# 5) Test if /app/.bun and /app/.pi/agent exist; create them if not
# ---------------------------------------------------------------------------
mkdir -p /app/.bun
mkdir -p /app/.pi/agent
info "Ensured /app/.bun and /app/.pi/agent exist."
mkdir -p /app/.pi-web
info "Ensured /app/.pi-web exist."

# ---------------------------------------------------------------------------
# 5.1) Test if /app/.pi-web/config.json is present. copy it not
# ---------------------------------------------------------------------------
if [ ! -f /pi-config/.pi-web/config.json ]; then
    if [ -d $HOME/.bun ]; then
        cp $HOME/config.json /pi-config/.pi-web/config.json
        warn "pi-web initialization: copied '$HOME/.pi-web/config.json' to '/pi-config/.pi-web'"
    else
        error "creating empty config.json in /pi-config/.pi-web"
        touch /pi-config/.pi-web/config.json
    fi
fi

# ---------------------------------------------------------------------------
# 5.2) Env var checks: PI_WEB_ALLOWED_HOSTS, PI_CODING_AGENT_DIR, PI_WEB_CONFIG
#    - show value:   info
#    - set but empty: warning
#    - unset/missing: error
# ---------------------------------------------------------------------------
ENV_VARS=(PI_WEB_ALLOWED_HOSTS PI_CODING_AGENT_DIR PI_WEB_CONFIG REPO_ROOT)
ENV_FAILED=0
for var in "${ENV_VARS[@]}"; do
    if [[ ! -v "$var" ]]; then
        error "Environment variable '$var' is not set (missing)."
        ENV_FAILED=1
    elif [[ -z "${!var}" ]]; then
        warn "Environment variable '$var' is set but empty."
    else
        info "Environment variable '$var' = '${!var}'"
    fi
done

if [ "$ENV_FAILED" -ne 0 ]; then
    error "One or more required environment variables are missing. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# 6) If all is ok, start pi-web agent with -p $HTTP_PORT -H $IP_ADDR --no-open
# ---------------------------------------------------------------------------
info "All checks passed. Starting pi-web agent..."
info "Running as $(whoami)"
info "bun is $(which bun)"
info "PATH is $PATH"
info "cd'ing to $REPO_ROOT and launch pi-web"
cd $REPO_ROOT
bun --bun run pi-web -H $IP_ADDR -p $HTTP_PORT --no-open
