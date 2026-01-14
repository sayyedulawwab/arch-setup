#!/usr/bin/env bash
set -euo pipefail

########################################
# Configuration
########################################
REPO_DIR="${HOME}/github/arch-setup"
CONFIG_DIR="${REPO_DIR}/config"
HOME_DIR="${REPO_DIR}/home"

########################################
# Colors & logging
########################################
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

info() {
    echo -e "${GREEN}==>${RESET} $1"
}

warn() {
    echo -e "${YELLOW}WARNING:${RESET} $1"
}

########################################
# Safe symlink function
########################################
link() {
    local src="$1"
    local dest="$2"

    # If destination exists and is not a symlink, back it up
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        warn "Backing up existing $dest → $dest.bak"
        mv "$dest" "$dest.bak"
    fi

    ln -sfnT "$src" "$dest"
    echo "Linked $dest → $src"
}

########################################
# Sanity checks
########################################
info "Checking repository structure..."

[ -d "$CONFIG_DIR" ] || { echo "Missing config directory"; exit 1; }
[ -d "$HOME_DIR" ]   || { echo "Missing home directory"; exit 1; }

########################################
# Link home dotfiles
########################################
info "Linking home dotfiles..."

for file in "$HOME_DIR"/.*; do
    name="$(basename "$file")"

    # Skip special entries
    [[ "$name" == "." || "$name" == ".." || "$name" == ".git" ]] && continue

    link "$file" "$HOME/$name"
done

########################################
# Link .config directories
########################################
info "Linking ~/.config directories..."

mkdir -p "$HOME/.config"

for dir in "$CONFIG_DIR"/*; do
    name="$(basename "$dir")"
    link "$dir" "$HOME/.config/$name"
done

########################################
# Done
########################################
info "All dotfiles successfully linked!"

