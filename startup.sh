#!/usr/bin/env bash
#
# pi-config setup / launch script
#
# Specs:
# - validates required env vars and directories
# - initializes /pi-config from $HOME/.pi.init when empty or .reinit marker present
# - initializes /pi-extensions from $HOME/.bun.init when empty or .reinit marker present
# - syncs pi-web config from $HOME/.pi-web.init when missing
# - syncs ssh keys from $REPO_ROOT/.ssh if present
# - starts pi-web agent with -p $HTTP_PORT -H $IP_ADDR --no-open
#
# The runtime uses BUN_INSTALL and PI_CODING_AGENT_DIR env vars (set via
# Dockerfile ENV) alongside an unconditional ~/.bun symlink to the
# /pi-extensions volume for bun's runtime injection to work.
set -euo pipefail

source $HOME/.bashrc

# ---------------------------------------------------------------------------
# Colours (only if stdout is a TTY)
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

# The volumes — can be overridden but defaults match Dockerfile ENV
PICONFIG_VOL=${PI_CODING_AGENT_DIR:-/pi-config}
PIEXT_VOL=${BUN_INSTALL:-/pi-extensions}

# ---------------------------------------------------------------------------
# 0) Env var checks: show value, warn if empty, error if missing
# ---------------------------------------------------------------------------
ENV_VARS=(PI_WEB_ALLOWED_HOSTS PI_CODING_AGENT_DIR PI_WEB_CONFIG REPO_ROOT BUN_INSTALL)
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
# 1) Required dirs / files checks
# ---------------------------------------------------------------------------
info "Required dirs checks..."
REQUIRED_DIRS=(
  $PICONFIG_VOL
  $PIEXT_VOL
  $REPO_ROOT
  $HOME/.pi.init/agent
  $HOME/.bun.init
  $HOME/.pi-web.init
)
MISSING=0
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        error "** Required directory '$dir' does not exist."
        MISSING=1
    fi
done
info "Required files checks..."
REQUIRED_FILES=(
  $HOME/.pi-web.init/config.json
  $HOME/.pi.init/agent/settings.json
)
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        error "** Required file '$file' is missing."
        MISSING=1
    fi
done
if [ "$MISSING" -ne 0 ]; then
    error "** One or more required files or directories are missing. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2) Initialize /pi-config from image defaults
# ---------------------------------------------------------------------------
init_piconfig() {
  warn "!!! Reinitializing $PICONFIG_VOL from image defaults !!!"
  rm -rf $PICONFIG_VOL/* $PICONFIG_VOL/.* 2>/dev/null || true
  cp -a $HOME/.pi.init/agent/. $PICONFIG_VOL/.
  info ".. pi-config: copied defaults from '$HOME/.pi.init/agent' to '$PICONFIG_VOL'"
}

info "Checking $PICONFIG_VOL initialization state"
if [ -f $PICONFIG_VOL/.reinit ]; then
  warn "!!! .reinit marker found in $PICONFIG_VOL !!!"
  rm -f $PICONFIG_VOL/.reinit
  init_piconfig
elif [ ! -f $PICONFIG_VOL/settings.json ]; then
  warn ".. $PICONFIG_VOL: missing settings.json — initializing from image defaults"
  init_piconfig
fi

# ---------------------------------------------------------------------------
# 3) Initialize /pi-extensions from image defaults
# ---------------------------------------------------------------------------
init_piextensions() {
  warn "!!! Reinitializing $PIEXT_VOL from image defaults !!!"
  rm -rf $PIEXT_VOL/bin $PIEXT_VOL/install $PIEXT_VOL/.bun 2>/dev/null || true
  cp -a $HOME/.bun.init/. $PIEXT_VOL/.
  info ".. pi-extensions: copied defaults from '$HOME/.bun.init' to '$PIEXT_VOL'"
}

info "Checking $PIEXT_VOL initialization state"
if [ -f $PIEXT_VOL/.reinit ]; then
  warn "!!! .reinit marker found in $PIEXT_VOL !!!"
  rm -f $PIEXT_VOL/.reinit
  init_piextensions
elif [ ! -f $PIEXT_VOL/bin/bun ]; then
  warn ".. $PIEXT_VOL: missing bun binary — initializing from image defaults"
  init_piextensions
fi

# ---------------------------------------------------------------------------
# 4) Copy pi-web config when missing
# ---------------------------------------------------------------------------
info "Checking $PICONFIG_VOL/.pi-web initialization state"
if [ ! -f $PICONFIG_VOL/.pi-web/config.json ]; then
    mkdir -p $PICONFIG_VOL/.pi-web
    cp $HOME/.pi-web.init/config.json $PICONFIG_VOL/.pi-web/config.json
    warn ".. pi-web: copied '$HOME/.pi-web.init/config.json' to '$PICONFIG_VOL/.pi-web'"
fi

# ---------------------------------------------------------------------------
# 5) Unconditional symlink: ~/.bun → /pi-extensions
#     Bun requires ~/.bun to exist (as a symlink to its install directory) for
#     its runtime injection to work in 'bun x' (or 'bunx') when the target
#     script has a #!/usr/bin/env node shebang. Without it, bun defers to the
#     system node interpreter which isn't installed in this container.
# ---------------------------------------------------------------------------
info "Creating ~/.bun symlink to $PIEXT_VOL"
rm -rf $HOME/.bun
ln -sfn $PIEXT_VOL $HOME/.bun

# ---------------------------------------------------------------------------
# 6) Ensure required tooling is on PATH (safety net — ENV /.bashrc already set)
# ---------------------------------------------------------------------------
add_to_path() {
    local dir="$1"
    if [ -d "$dir" ]; then
        PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -Fxv "$dir" | paste -sd: -)
        PATH="$dir:$PATH"
        export PATH
    else
        warn "'$dir' is missing; cannot add $dir to PATH."
    fi
}

add_to_path $PIEXT_VOL/bin
add_to_path $HOME/.cargo/bin
add_to_path $HOME/.local/bin

# ---------------------------------------------------------------------------
# 7) Copy ssh keys from $REPO_ROOT if a .ssh folder exists
# ---------------------------------------------------------------------------
info "Checking .ssh keys in $REPO_ROOT"
if [ -d $REPO_ROOT/.ssh ]; then
  info "  found .ssh folder, will sync contents"
  cp --update=none -v $REPO_ROOT/.ssh/* ~/.ssh/.
fi

# ---------------------------------------------------------------------------
# 8) Start pi-web agent
# ---------------------------------------------------------------------------
info "All checks passed. Starting pi-web agent..."
info " --- "
info "Running as $(whoami)"
info "bun is $(which bun) / PATH is $PATH"
info "Port is set to ${HTTP_PORT:-8080} and address is bound to ${IP_ADDR:-127.0.0.1}"
info "cd'ing to $REPO_ROOT and launch pi-web"
cd $REPO_ROOT
pi-web -H ${IP_ADDR:-127.0.0.0} -p ${HTTP_PORT:-8080} --no-open