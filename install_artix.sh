#!/usr/bin/env bash
set -euo pipefail

echo "=== Artix (dinit) Bootstrap (Safe Arch extra for Discord) ==="

# 0. User input
read -p "Enter Branch Name [default: main]: " branch_choice
branch_choice=${branch_choice:-main}
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

PACMAN_CONF="/etc/pacman.conf"

# 0.5 Permanently enable Arch extra repo
# This is appended to the bottom so your Artix repos remain the priority
if ! grep -q "^\[extra\]" "$PACMAN_CONF"; then
    echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" | sudo tee -a "$PACMAN_CONF"
fi

# 1. Update and install core tools
sudo pacman -Syu --needed --noconfirm base-devel git rsync

# 2. Clone repo
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
git clone -b "$branch_choice" --single-branch "$REPO_URL" "$CLONE_DIR"
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

# 5. Install Discord
if [[ "$discord_choice" =~ ^[Yy]$ ]]; then
    # --ignore prevents the Arch repo from replacing Artix core system libraries
    sudo pacman -S --needed --noconfirm --ignore pacman,glibc,lib32-glibc,mesa discord || true
fi

# 6. Re-generate initramfs
sudo mkinitcpio -P

# 7. yay (AUR helper)
if ! command -v yay &>/dev/null; then
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tempdir"
fi

# 8. Install additional packages
# Specific check: install artix.txt IN ADDITION to other lists if on Artix
if [ -f "/etc/artix-release" ]; then
    echo "Artix system detected. Adding artix.txt packages..."
    [ -f "packages/artix.txt" ] && sudo pacman -S --needed --noconfirm - < packages/artix.txt
fi

# Standard package lists
[ -f "packages/pacman.txt" ] && sudo pacman -S --needed --noconfirm - < packages/pacman.txt
[ -f "packages/aur.txt" ] && yay -S --needed --noconfirm - < packages/aur.txt

# 9. Deploy configuration files
# Standard rsync as requested (no excludes)
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "$HOME/"

# 10. Update system caches
[ -d "$HOME/.local/share/fonts" ] && fc-cache -fv >/dev/null
[ -d "$HOME/.local/share/applications" ] && update-desktop-database "$HOME/.local/share/applications"

# 11. Display manager, firewall, Fish shell
# Correct dinit service handling for ly
if pacman -Qs ly >/dev/null; then
    echo "Configuring ly for dinit..."
    sudo pacman -S --needed --noconfirm ly-dinit || true
    sudo dinitctl enable ly || true
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

# 12. Cleanup
cd "$HOME"
rm -rf "$CLONE_DIR"
echo "Done."

# Prompt reboot
read -p "Reboot now? [y/N]: " confirm_reboot
if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot recommended."
fi
