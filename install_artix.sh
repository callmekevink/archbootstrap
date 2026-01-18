#!/usr/bin/env bash
set -euo pipefail

echo "=== Artix Bootstrap (runit) ==="

# ---------------------------
# 0. User input
# ---------------------------
read -p "Enter Git branch [default: main]: " branch_choice
branch_choice=${branch_choice:-main}
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

PACMAN_CONF="/etc/pacman.conf"


echo "Installing Artix Arch support..."
sudo pacman -S --needed --noconfirm artix-archlinux-support dbus-runit
sudo pacman-key --populate archlinux

# Enable Arch extra repo if missing
if ! grep -q "^\[extra\]" "$PACMAN_CONF"; then
    echo -e "\n[extra]\nInclude = /etc/pacman.d/mirrorlist-arch" | sudo tee -a "$PACMAN_CONF"
fi

# ---------------------------
# 1. Install core tools
# ---------------------------
sudo pacman -Syu --needed --noconfirm base-devel git rsync

# ---------------------------
# 2. Clone repo
# ---------------------------
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
git clone -b "$branch_choice" --single-branch "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# ---------------------------
# 3. microcoed
# ---------------------------
[[ "$ucode_choice" == "amd" ]] && sudo pacman -S --needed --noconfirm amd-ucode
[[ "$ucode_choice" == "intel" ]] && sudo pacman -S --needed --noconfirm intel-ucode

# ---------------------------
# 4. Vulkan
# ---------------------------
case "$vulkan_choice" in
    intel) sudo pacman -S --needed --noconfirm vulkan-intel vulkan-icd-loader ;;
    amd)
        sudo pacman -R --noconfirm amdvlk || true
        sudo pacman -S --needed --noconfirm vulkan-radeon vulkan-icd-loader
        ;;
esac

# ---------------------------
# 5. Discord
# ---------------------------
if [[ "$discord_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed --noconfirm --ignore pacman,glibc,lib32-glibc,mesa discord || true
fi


sudo mkinitcpio -P

# ---------------------------
# 7. yay 
# ---------------------------
if ! command -v yay &>/dev/null; then
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tempdir"
fi

# ---------------------------
# 8. Install packages from artix.txt and pacman.txt
# ---------------------------
if [ -f "packages/artix.txt" ]; then
    echo "Installing packages from packages/artix.txt..."
    sudo pacman -S --needed --noconfirm - < packages/artix.txt
fi

if [ -f "packages/pacman.txt" ]; then
    echo "Installing packages from packages/pacman.txt..."
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt
fi


if [ -f "packages/aur.txt" ]; then
    yay -S --needed --noconfirm - < packages/aur.txt
fi

# ---------------------------
# 9. deply configs etc isr
# ---------------------------
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "$HOME/"

# ---------------------------
# 10. cache
# ---------------------------
[ -d "$HOME/.local/share/fonts" ] && fc-cache -fv >/dev/null
[ -d "$HOME/.local/share/applications" ] && update-desktop-database "$HOME/.local/share/applications"

# wallpaper
if command -v awww &>/dev/null; then
    pgrep awww-daemon >/dev/null || awww-daemon &
    sleep 4
    WP_FILE="$HOME/.local/share/wallpapers/Hades.png"
    [ -f "$WP_FILE" ] && awww img "$WP_FILE" &
fi

# ---------------------------
# 11. runit function
# ---------------------------
enable_runit_service() {
    local service_name=$1
    if [ -d "/etc/runit/sv/$service_name" ]; then
        echo "Enabling $service_name..."
        sudo ln -sf "/etc/runit/sv/$service_name" "/run/runit/service/"
    else
        echo "Service $service_name not found, skipping."
    fi
}

# ---------------------------
# 12. runit enable
# ---------------------------
ESSENTIAL_SERVICES=(
    dbus-runit
    elogind-runit
    networkmanager-runit
    ly-runit
    ufw-runit
    bluez-runit
)

for svc in "${ESSENTIAL_SERVICES[@]}"; do
    enable_runit_service "$svc"
done

# ---------------------------
# 13. Fish shell
# ---------------------------
if [[ "$fish_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --noconfirm fish
    # Change shell for the actual user, not root
    sudo chsh -s /usr/bin/fish "${SUDO_USER:-$USER}"
fi

# ---------------------------
# 14. Cleanup
# ---------------------------
cd "$HOME"
rm -rf "$CLONE_DIR"
echo "Done."

# Reboot prompt
read -p "Reboot now? [y/N]: " confirm_reboot
[[ "$confirm_reboot" =~ ^[Yy]$ ]] && sudo reboot || echo "Reboot recommended."
