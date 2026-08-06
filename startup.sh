#!/usr/bin/env bash
#
# pi-config setup / launch script
#
# Specs:
# - tests if /pi-config, /pi-extensions and /app folder exists, errors out if not
# - tests if /pi-config/.pi/agent exists, if not copy /root/.pi to /pi-config/.pi and warn about pi-config initialization
# - teste if /pi-extensions/.bun exists, if not  copy /root/.bun to /pi-extensions/.bun and warn about pi-extensions initialization
# - make sure that /pi-extensions/.bun/bin and /root/.local/bin are present or added to PATH
# - tests if /app/.bun and /app/.pi/agent folders exists, creates them if not
# - if all is ok, start pi-web agent with -p 8080 -H 0.0.0.0 --no-open
set -euo pipefail

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
# 2) Test if /pi-config/.pi/agent exists; if not copy /root/.pi to
#    /pi-config/.pi and warn about pi-config initialization
# ---------------------------------------------------------------------------
if [ ! -d /pi-config/.pi/agent ]; then
    if [ -d /root/.pi ]; then
        cp -a /root/.pi /pi-config/.pi
    else
        mkdir -p /pi-config/.pi/agent
    fi
    warn "pi-config initialization: copied '/root/.pi' to '/pi-config/.pi'"
fi

# ---------------------------------------------------------------------------
# 3) Test if /pi-extensions/.bun exists; if not copy /root/.bun to
#    /pi-extensions/.bun and warn about pi-extensions initialization
# ---------------------------------------------------------------------------
if [ ! -d /pi-extensions/.bun ]; then
    if [ -d /root/.bun ]; then
        cp -a /root/.bun /pi-extensions/.bun
    else
        mkdir -p /pi-extensions/.bun
    fi
    warn "pi-extensions initialization: copied '/root/.bun' to '/pi-extensions/.bun'"
fi

# ---------------------------------------------------------------------------
# 4) Make sure /pi-extensions/.bun/bin and /root/.local/bin are present
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
add_to_path /root/.local/bin

# ---------------------------------------------------------------------------
# 5) Test if /app/.bun and /app/.pi/agent exist; create them if not
# ---------------------------------------------------------------------------
mkdir -p /app/.bun
mkdir -p /app/.pi/agent
info "Ensured /app/.bun and /app/.pi/agent exist."

# ---------------------------------------------------------------------------
# 6) If all is ok, start pi-web agent with -p 8080 -H 0.0.0.0 --no-open
# ---------------------------------------------------------------------------
info "All checks passed. Starting pi-web agent..."
exec pi-web -H 0.0.0.0 -p 8080 --no-open
