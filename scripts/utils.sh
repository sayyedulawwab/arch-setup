########################################
# Globals
########################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/arch-install.log"
DRY_RUN=false
########################################
# Argument parsing
########################################
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "⚠️  DRY-RUN MODE ENABLED — no changes will be made"
fi

########################################
# Logging
########################################
mkdir -p /var/log
exec > >(tee -a "$LOG_FILE") 2>&1


########################################
# Helpers
########################################


confirm() {
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

info() {
  echo -e "${GREEN}${BOLD}==>${NC} $1"
}

warn() {
  echo -e "${YELLOW}${BOLD}WARNING:${NC} $1"
}

error() {
  echo -e "${RED}${BOLD}ERROR:${NC} $1"
  exit 1
}