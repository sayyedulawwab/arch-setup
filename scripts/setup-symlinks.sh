#!/usr/bin/env bash
set -euo pipefail

########################################
# Configuration
########################################
REPO_DIR="${HOME}/github/arch-setup"
CONFIG_DIR="${REPO_DIR}/config"
HOME_DIR="${REPO_DIR}/home"

########################################
# Functions
########################################
info() {
    echo -e "\e[32m==>\e[0m $1"
}

link_file() {
    local src="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    ln -sf "$src" "$dest"
    echo "Linked $dest → $src"
}

########################################
# Symlink home dotfiles
########################################
info "Linking home dotfiles..."
for file in "$HOME_DIR"/.*; do
    filename="$(basename "$file")"
    # skip . and ..
    [[ "$filename" == "." || "$filename" == ".." ]] && continue
    # skip .git if present
    [[ "$filename" == ".git" ]] && continue
    link_file "$file" "$HOME/$filename"
done

########################################
# Symlink .config folders
########################################
info "Linking .config folders..."
for folder in "$CONFIG_DIR"/*; do
    foldername="$(basename "$folder")"
    link_file "$folder" "$HOME/.config/$foldername"
done

info "All symlinks created successfully!"
