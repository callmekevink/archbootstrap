#!/usr/bin/env bash
set -euo pipefail

echo "=== Arch Bootstrap Installer ==="

# 1. Install git
echo "[1/11] Installing git..."
sudo pacman -Syu --noconfirm git

# 2. Install yay (AUR helper)
if ! command -v yay &>/dev/null; then
    echo "[2/11] Installing yay..."
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay"
    makepkg -si --noconfirm
    popd
    rm -rf "$tempdir"
else
    echo "yay already installed."
fi

# 3. Install pacman packages
if [ -f packages/pacman.txt ]; then
    echo "[3/11] Installing pacman packages..."
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt
fi

# 4. Install AUR packages
if [ -f packages/aur.txt ]; then
    echo "[4/11] Installing AUR packages..."
    yay -S --needed --noconfirm - < packages/aur.txt
fi

# 5. Deploy dotfiles via Stow
if ! command -v stow &>/dev/null; then
    echo "[5/11] Installing GNU Stow..."
    sudo pacman -S --noconfirm stow
fi
echo "[5/11] Deploying dotfiles..."
cd dotfiles
for dir in *; do
    stow "$dir"
done
cd ..

# 6. Deploy /etc configs (includes niri-session config)
if [ -d etc ]; then
    echo "[6/11] Deploying /etc configs..."
    sudo rsync -a --info=progress2 etc/ /etc/
fi

# 7. Enable Ly login manager
echo "[7/11] Enabling Ly login manager..."
sudo systemctl enable ly.service

# 7b. Disable default getty on tty2
echo "[7b/11] Disabling default getty on tty2..."
sudo systemctl disable getty@tty2.service || true

# 8. Enable UFW firewall
if ! command -v ufw &>/dev/null; then
    echo "[8/11] Installing UFW firewall..."
    sudo pacman -S --noconfirm ufw
fi
echo "[8/11] Enabling UFW..."
sudo systemctl enable ufw
sudo systemctl start ufw
sudo ufw enable

# 9. Deploy wallpapers and run awww
if [ -d wallpapers ]; then
    echo "[9/11] Deploying wallpapers..."
    mkdir -p ~/.local/share/wallpapers
    rsync -a wallpapers/ ~/.local/share/wallpapers/

    if [ -f ~/.config/awww/config ]; then
        source ~/.config/awww/config
    else
        MODE=stretch
        INTERVAL=0
    fi
    echo "[9/11] Starting awww..."
    awww --mode "$MODE" --interval "$INTERVAL" ~/.local/share/wallpapers/* &
fi

# 10. Deploy .local files
if [ -d local ]; then
    echo "[10/11] Deploying .local files..."
    mkdir -p ~/.local
    rsync -a local/ ~/.local/

    if [ -d ~/.local/share/fonts ]; then
        fc-cache -fv
    fi
    if [ -d ~/.local/share/applications ]; then
        update-desktop-database ~/.local/share/applications
    fi
fi

# 11. Clean up repo
echo "[11/11] Cleaning up repository..."
cd ..
repo_name=$(basename "$PWD")
rm -rf "$repo_name"

echo "=== Installation complete! ==="
