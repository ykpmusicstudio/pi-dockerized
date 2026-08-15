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

PICONFIG_VOL=/pi-config
PIEXT_VOL=/pi-extensions

# ---------------------------------------------------------------------------
# 0) Env var checks: PI_WEB_ALLOWED_HOSTS, PI_CODING_AGENT_DIR, PI_WEB_CONFIG
#    - show value:   info
#    - set but empty: warning
#    - unset/missing: error
# ---------------------------------------------------------------------------
ENV_VARS=(PI_WEB_ALLOWED_HOSTS PI_CODING_AGENT_DIR PI_WEB_CONFIG REPO_ROOT)
ENV_FAILED=0
for var in "${ENV_VARS[@]}"; do
    if [[ ! -v "$var" ]]; then
        error "** Environment variable '$var' is not set (missing)."
        ENV_FAILED=1
    elif [[ -z "${!var}" ]]; then
        warn ".. Environment variable '$var' is set but empty."
    else
        info "   Environment variable '$var' = '${!var}'"
    fi
done

if [ "$ENV_FAILED" -ne 0 ]; then
    error "** One or more required environment variables are missing. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1) Test that $PICONFIG_VOL, $PIEXT_VOL and $REPO_ROOT exist -> error out if not
# ---------------------------------------------------------------------------
info "Required dirs checks..."
REQUIRED_DIRS=($PICONFIG_VOL $PIEXT_VOL $REPO_ROOT ~/.pi/agent ~/.pi-web.init ~/.bun)
MISSING=0
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        error "** Required directory '$dir' does not exist."
        MISSING=1
    fi
done
info "Required files checks..."
REQUIRED_FILES=(~/.pi-web.init/config.json)
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        error "** Required file '$file' is missing."
        MISSING=1
    fi
done
if [ "$MISSING" -ne 0 ]; then
    error "** One or more required files on directories are missing. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# 1.1) Reinit Run asked in $PICONFIG_VOL ?
# ---------------------------------------------------------------------------
#DO_REINIT=${REINIT_VOL:-}
if [ -f $PICONFIG_VOL/.reinit ]; then
  warn "!!! .reinit file found in $PICONFIG_VOL !!! $PICONFIG_VOL and $PIEXT_VOL will be reinitialized!"
  rm -f $PICONFIG_VOL/.reinit
  rm -rf $PICONFIG_VOL/.pi
  rm -rf $PIEXT_VOL/.bun
fi

# ---------------------------------------------------------------------------
# 5) Test if $REPO_ROOT/.bun and $REPO_ROOT/.pi/agent exist; create them if not
#    or if a reinit run was asked.
# ---------------------------------------------------------------------------
#mkdir -p $REPO_ROOT/.bun
#mkdir -p $REPO_ROOT/.pi/agent
#info "Ensured $REPO_ROOT/.bun and $REPO_ROOT/.pi/agent exist."
#mkdir -p $REPO_ROOT/.pi-web
#info "Ensured $REPO_ROOT/.pi-web exist."

# ---------------------------------------------------------------------------
# 2) Test if $PICONFIG_VOL has sessins if not copy $HOME/.pi/agent to
#    $PICONFIG_VOL and warn about pi-config initialization
# ---------------------------------------------------------------------------
info "Checking $PICONFIG_VOL/.pi initialization state"
if [ ! -d $PICONFIG_VOL/session ]; then
    if [ -d $HOME/.pi/agent ]; then
        cp -a $HOME/.pi/agent $PICONFIG_VOL
        warn ".. pi-config initialization: copied '$HOME/.pi' and linked to '$PICONFIG_VOL/.pi'"
    else
        error "** No '$HOME'/.pi.init folder found, cannot initialize $PICONFIG_VOL volume. Aborting."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 5.1) Test if $REPO_ROOT/.pi-web/config.json is present. copy it not
# ---------------------------------------------------------------------------
info "Checking $PICONFIG_VOL/.pi-web initialization state"
if [ ! -f $PICONFIG_VOL/.pi-web/config.json ]; then
    mkdir -p $PICONFIG_VOL/.pi-web
    if [ -f $HOME/.pi-web.init/config.json ]; then
        cp $HOME/.pi-web.init/config.json $PICONFIG_VOL/.pi-web/config.json
        warn ".. pi-web initialization: copied '$HOME/.pi-web/config.json' to '$PICONFIG_VOL/.pi-web'"
    else
        error "** No '$HOME'/.pi-web.init folder found, cannot initialize $PICONFIG_VOL volume. Aborting."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 3) Test if $PIEXT_VOL/.bun exists; if not copy $HOME/.bun to
#    $PIEXT_VOL/.bun and warn about pi-extensions initialization
# ---------------------------------------------------------------------------
info "Checking $PIEXT_VOL/.bun initialization state"
if [ ! -d $PIEXT_VOL/.bun ]; then
    if [ -d $HOME/.bun ]; then
        cp -a $HOME/.bun $PIEXT_VOL
        warn ".. pi-extensions initialization: copied '$HOME/.bun' and linked to '$PIEXT_VOL'"
    else
        error "** No '$HOME'/.bun.init folder found, cannot initialize $PIEXT_VOL volume. Aborting."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Add symlinks whenever needed
# ---------------------------------------------------------------------------
info "Checking $HOME/.bun simlink"
if [ ! -d "$HOME/.bun" ]; then
    warn ".. adding $HOME/.bun simlink to $PIEXT_VOL/.bun"
    ln -s $PIEXT_VOL $HOME/.bun
fi
info "Checking $HOME/.pi simlink"
if [ ! -d "$HOME/.pi" ]; then
    warn ".. adding $HOME/.pi simlink to $PICONFIG_VOL/.pi"
    ln -s $PICONFIG_VOL $HOME/.pi/agent
fi

# ---------------------------------------------------------------------------
# 4) Make sure $PIEXT_VOL/.bun/bin and $HOME/.local/bin are present
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
        warn "'$dir' is missing; cannot add $dir to PATH."
    fi
}

add_to_path $HOME/.bun/bin
add_to_path $PIEXT_VOL/bin
add_to_path $HOME/.local/bin

# ---------------------------------------------------------------------------
# 6) If all is ok, start pi-web agent with -p $HTTP_PORT -H $IP_ADDR --no-open
# ---------------------------------------------------------------------------
info "All checks passed. Starting pi-web agent..."
info " --- "
info "Running as $(whoami)"
info "bun is $(which bun) / PATH is $PATH"
info "Port is set to ${HTTP_PORT:-8080} and address is bound to ${IP_ADDR:-127.0.0.1}"
info "cd'ing to $REPO_ROOT and launch pi-web"
cd $REPO_ROOT
#bun --bun run pi-web -H ${IP_ADDR:-127.0.0.0} -p ${HTTP_PORT:-8080} --no-open
pi-web -H ${IP_ADDR:-127.0.0.0} -p ${HTTP_PORT:-8080} --no-open
