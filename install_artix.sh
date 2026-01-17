#!/usr/bin/env bash
set -euo pipefail

echo "=== Artix Bootstrap ==="

# 0. User input
read -p "Enter Git branch [default: main]: " branch_choice
branch_choice=${branch_choice:-main}
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

PACMAN_CONF="/etc/pacman.conf"

# 0.1 Artix / Arch extra support (elogind-based)
echo "Installing Artix Arch support..."
sudo pacman -S --needed --noconfirm artix-archlinux-support dbus-dinit
sudo pacman-key --populate archlinux

# Enable Arch extra repo if missing
if ! grep -q "^\[extra\]" "$PACMAN_CONF"; then
    echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" | sudo tee -a "$PACMAN_CONF"
fi

# 1. Install core tools
sudo pacman -Syu --needed --noconfirm base-devel git rsync

# 2. Clone repo
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
git clone -b "$branch_choice" --single-branch "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# 3. Microcode
[[ "$ucode_choice" == "amd" ]] && sudo pacman -S --needed --noconfirm amd-ucode
[[ "$ucode_choice" == "intel" ]] && sudo pacman -S --needed --noconfirm intel-ucode

# 4. Vulkan
case "$vulkan_choice" in
    intel) sudo pacman -S --needed --noconfirm vulkan-intel vulkan-icd-loader ;;
    amd)
        sudo pacman -R --noconfirm amdvlk || true
        sudo pacman -S --needed --noconfirm vulkan-radeon vulkan-icd-loader
        ;;
esac

# 5. Discord
if [[ "$discord_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed --noconfirm --ignore pacman,glibc,lib32-glibc,mesa discord || true
fi

# 6. Re-generate initramfs
sudo mkinitcpio -P

# 7. yay
if ! command -v yay &>/dev/null; then
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tempdir"
fi

# 8. Install packages
[ -f "packages/pacman.txt" ] && sudo pacman -S --needed --noconfirm - < packages/pacman.txt
[ -f "packages/aur.txt" ] && yay -S --needed --noconfirm - < packages/aur.txt

# 9. Deploy configuration files
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "$HOME/"

# 10. Update caches
[ -d "$HOME/.local/share/fonts" ] && fc-cache -fv >/dev/null
[ -d "$HOME/.local/share/applications" ] && update-desktop-database "$HOME/.local/share/applications"

# Wallpaper
if command -v awww &>/dev/null; then
    pgrep awww-daemon >/dev/null || awww-daemon &
    sleep 4
    WP_DIR="$HOME/.local/share/wallpapers"
    [ -d "$WP_DIR" ] && [ "$(ls -A "$WP_DIR")" ] && awww img "$WP_DIR/"* &
fi

# 11. Display manager (ly)
if pacman -Qs ly >/dev/null; then
    sudo pacman -S --needed --noconfirm ly-dinit || true
    [ -f "/etc/dinit.d/ly" ] && sudo sed -i 's|/usr/bin/ly|/usr/bin/ly-dm|g' /etc/dinit.d/ly
    sudo dinitctl enable ly || true
fi

# 12. Firewall (UFW)
if command -v ufw &>/dev/null; then
    sudo dinitctl start ufw || true
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    sudo ufw --force enable
fi

# 13. Fish shell
if [[ "$fish_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --noconfirm fish
    sudo chsh -s /usr/bin/fish "$USER"
fi

# 14. Cleanup
cd "$HOME"
rm -rf "$CLONE_DIR"
echo "Done."

# Reboot prompt
read -p "Reboot now? [y/N]: " confirm_reboot
[[ "$confirm_reboot" =~ ^[Yy]$ ]] && sudo reboot || echo "Reboot recommended."
