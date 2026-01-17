#!/usr/bin/env bash
set -euo pipefail

echo "=== Artix (dinit) + Arch extra Bootstrap ==="

# 0. User input
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

# 0.5 Backup and add Arch extra repo
PACMAN_CONF="/etc/pacman.conf"
sudo cp "$PACMAN_CONF" "$PACMAN_CONF.bak"

# Append Arch extra repo if not already present
if ! grep -q "^\[extra\]" "$PACMAN_CONF"; then
    echo -e "\n[extra]\nServer = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" | sudo tee -a "$PACMAN_CONF"
fi

# 1. Install core tools
sudo pacman -Syu --needed --noconfirm base-devel git rsync

# 2. Clone repo
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
git clone "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# 3. Install microcode
[[ "$ucode_choice" == "amd" ]] && sudo pacman -S --needed --noconfirm amd-ucode
[[ "$ucode_choice" == "intel" ]] && sudo pacman -S --needed --noconfirm intel-ucode

# 4. Vulkan
case "$vulkan_choice" in
    intel) sudo pacman -S --needed --noconfirm vulkan-intel vulkan-icd-loader ;;
    amd) sudo pacman -R --noconfirm amdvlk || true
         sudo pacman -S --needed --noconfirm vulkan-radeon vulkan-icd-loader ;;
esac

# 5. Discord (from Arch extra repo)
if [[ "$discord_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed --noconfirm discord || true
fi

sudo mkinitcpio -P

# 6. yay (AUR helper)
if ! command -v yay &>/dev/null; then
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tempdir"
fi

# 7. Install packages
[ -f "packages/pacman.txt" ] && sudo pacman -S --needed --noconfirm - < packages/pacman.txt
[ -f "packages/aur.txt" ] && yay -S --needed --noconfirm - < packages/aur.txt

# 8. Deploy config files
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "$HOME/"

# 9. Update system caches
[ -d "$HOME/.local/share/fonts" ] && fc-cache -fv >/dev/null
[ -d "$HOME/.local/share/applications" ] && update-desktop-database "$HOME/.local/share/applications"

if command -v awww &>/dev/null; then
    pgrep awww-daemon >/dev/null || awww-daemon &
    sleep 4
    WP_DIR="$HOME/.local/share/wallpapers"
    if [ -d "$WP_DIR" ] && [ "$(ls -A "$WP_DIR")" ]; then
        awww img "$WP_DIR/"* &
    fi
fi

# 10. Display manager, firewall, Fish
if pacman -Qs ly >/dev/null; then
    sudo ln -sf /etc/runit/sv/ly /run/runit/service || true
fi

if command -v ufw &>/dev/null; then
    sudo dinitctl start ufw || true
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    echo "y" | sudo ufw enable || true
fi

if [[ "$fish_choice" =~ ^[Yy]$ ]]; then
    if ! command -v fish &>/dev/null; then
        sudo pacman -S --noconfirm fish
    fi
    sudo chsh -s /usr/bin/fish "$USER"
fi

# 11. Cleanup / permissions
sudo chown -R "$USER:$USER" "$HOME"

cd "$HOME"
rm -rf "$CLONE_DIR"
echo "Done."

read -p "Reboot now? [y/N]: " confirm_reboot
if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot recommended."
fi
