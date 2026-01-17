#!/usr/bin/env bash
set -euo pipefail

echo "=== Artix (dinit) Bootstrap (Safe Arch extra for Discord) ==="

# 0. User input
read -p "Enter Branch Name [default: main]: " branch_choice
branch_choice=${branch_choice:-main}
read -p "New Username to create: " new_user
read -sp "Password for $new_user: " user_pass
echo ""
read -p "System Language (e.g., en_US.UTF-8): " sys_lang
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

PACMAN_CONF="/etc/pacman.conf"

# 0.1 Prepare Arch Support (Provides the missing mirrorlist-arch)
echo "Installing Arch Linux support packages..."
sudo pacman -S --needed --noconfirm artix-archlinux-support

# Initialize Arch keys
sudo pacman-key --populate archlinux

# 0.5 Permanently enable Arch extra repo
if ! grep -q "^\[extra\]" "$PACMAN_CONF"; then
    echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" | sudo tee -a "$PACMAN_CONF"
fi

# 1. Update and install core tools
sudo pacman -Syu --needed --noconfirm base-devel git rsync

# 1.5 Create User and Home Directory
if ! id "$new_user" &>/dev/null; then
    echo "Creating user $new_user..."
    sudo useradd -m -G wheel,audio,video,storage -s /bin/bash "$new_user"
    echo "$new_user:$user_pass" | sudo chpasswd
fi

# 1.6 Set Language (Locale)
echo "Setting system language to $sys_lang..."
sudo sed -i "s/^#$sys_lang/$sys_lang/" /etc/locale.gen
sudo locale-gen
echo "LANG=$sys_lang" | sudo tee /etc/locale.conf

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
if [ -f "/etc/artix-release" ]; then
    echo "Artix system detected. Adding artix.txt packages..."
    [ -f "packages/artix.txt" ] && sudo pacman -S --needed --noconfirm - < packages/artix.txt
fi

[ -f "packages/pacman.txt" ] && sudo pacman -S --needed --noconfirm - < packages/pacman.txt
[ -f "packages/aur.txt" ] && yay -S --needed --noconfirm - < packages/aur.txt

# 9. Deploy configuration files
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "/home/$new_user/" 

# 11. Display manager, firewall, Fish shell
if pacman -Qs ly >/dev/null; then
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
    sudo pacman -S --noconfirm fish
    sudo chsh -s /usr/bin/fish "$new_user"
fi

# 12. Cleanup
cd "$HOME"
rm -rf "$CLONE_DIR"
echo "Done. Arch extra enabled and user $new_user created."

# Prompt reboot
read -p "Reboot now? [y/N]: " confirm_reboot
if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Reboot recommended."
fi
