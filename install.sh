#!/usr/bin/env bash
set -euo pipefail

echo "=== Arch Bootstrap Installer ==="

# -----------------------------
# 0. Update system
# -----------------------------
echo "[0/13] Updating system..."
sudo pacman -Syu --noconfirm

# -----------------------------
# 1. Install Git
# -----------------------------
echo "[1/13] Installing Git..."
sudo pacman -S --needed --noconfirm git

# -----------------------------
# 2. Clone your bootstrap repo
# -----------------------------
REPO_URL="git@github.com:callmekevink/archbootstrap.git"
CLONE_DIR="$HOME/arch-setup"

if [ ! -d "$CLONE_DIR" ]; then
    echo "[2/13] Cloning bootstrap repository..."
    git clone "$REPO_URL" "$CLONE_DIR"
else
    echo "[2/13] Repository already exists, pulling latest..."
    git -C "$CLONE_DIR" pull
fi

cd "$CLONE_DIR"

# -----------------------------
# 3. Install yay (AUR helper)
# -----------------------------
if ! command -v yay &>/dev/null; then
    echo "[3/13] Installing yay..."
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay"
    makepkg -si --noconfirm
    popd
    rm -rf "$tempdir"
else
    echo "yay already installed."
fi

# -----------------------------
# 4. Install pacman packages
# -----------------------------
if [ -f packages/pacman.txt ]; then
    echo "[4/13] Installing pacman packages..."
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt
fi

# -----------------------------
# 5. Install AUR packages
# -----------------------------
if [ -f packages/aur.txt ]; then
    echo "[5/13] Installing AUR packages..."
    yay -S --needed --noconfirm - < packages/aur.txt
fi

# -----------------------------
# 6. Deploy dotfiles via GNU Stow
# -----------------------------
if ! command -v stow &>/dev/null; then
    echo "[6/13] Installing GNU Stow..."
    sudo pacman -S --noconfirm stow
fi

echo "[6/13] Deploying dotfiles..."
cd dotfiles
for dir in *; do
    stow "$dir"
done
cd ..

# -----------------------------
# 7. Deploy /etc configs (includes niri-session config)
# -----------------------------
if [ -d etc ]; then
    echo "[7/13] Deploying /etc configs..."
    sudo rsync -a --info=progress2 etc/ /etc/
fi

# -----------------------------
# 8. Enable Ly login manager
# -----------------------------
echo "[8/13] Enabling Ly login manager..."
sudo systemctl enable ly.service

# 8b. Disable default getty on tty2
echo "[8b/13] Disabling default getty on tty2..."
sudo systemctl disable getty@tty2.service || true

# -----------------------------
# 9. Enable UFW firewall
# -----------------------------
if ! command -v ufw &>/dev/null; then
    echo "[9/13] Installing UFW firewall..."
    sudo pacman -S --noconfirm ufw
fi

echo "[9/13] Enabling UFW..."
sudo systemctl enable ufw
sudo systemctl start ufw
sudo ufw enable

# -----------------------------
# 10. Deploy wallpapers and run awww
# -----------------------------
if [ -d wallpapers ]; then
    echo "[10/13] Deploying wallpapers..."
    mkdir -p ~/.local/share/wallpapers
    rsync -a wallpapers/ ~/.local/share/wallpapers/

    if [ -f ~/.config/awww/config ]; then
        source ~/.config/awww/config
    else
        MODE=stretch
        INTERVAL=0
    fi

    echo "[10/13] Starting awww..."
    awww --mode "$MODE" --interval "$INTERVAL" ~/.local/share/wallpapers/* &
fi

# -----------------------------
# 11. Deploy .local files
# -----------------------------
if [ -d local ]; then
    echo "[11/13] Deploying .local files..."
    mkdir -p ~/.local
    rsync -a local/ ~/.local/

    if [ -d ~/.local/share/fonts ]; then
        fc-cache -fv
    fi
    if [ -d ~/.local/share/applications ]; then
        update-desktop-database ~/.local/share/applications
    fi
fi

# -----------------------------
# 12. Optional: Pull updates for dotfiles or configs (already handled at start)
# -----------------------------
# git pull already updates the repo

# -----------------------------
# 13. Clean up repo
# -----------------------------
echo "[13/13] Cleaning up repository..."
cd ~
rm -rf "$CLONE_DIR"

echo "=== Installation complete! ==="
