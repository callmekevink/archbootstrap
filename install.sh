#!/usr/bin/env bash
set -euo pipefail

echo "=== Arch Bootstrap ==="

# 0. Questions
read -p "Ucode? [amd/intel]: " ucode_choice
read -p "Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Fish shell? [y/N]: " fish_choice

# 1. Base Tools
sudo pacman -Syu --needed --noconfirm base-devel git rsync

# 2. Repo Setup
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
git clone "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# 3. Drivers
[[ "$ucode_choice" == "amd" ]] && sudo pacman -S --needed --noconfirm amd-ucode
[[ "$ucode_choice" == "intel" ]] && sudo pacman -S --needed --noconfirm intel-ucode

case "$vulkan_choice" in
    intel) sudo pacman -S --needed --noconfirm vulkan-intel vulkan-icd-loader ;;
    amd) sudo pacman -R --noconfirm amdvlk || true
         sudo pacman -S --needed --noconfirm vulkan-radeon vulkan-icd-loader ;;
esac

# 4. Yay
if ! command -v yay &>/dev/null; then
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tempdir"
fi

# 5. Packages
[ -f "packages/pacman.txt" ] && sudo pacman -S --needed --noconfirm - < packages/pacman.txt
[ -f "packages/aur.txt" ] && yay -S --needed --noconfirm - < packages/aur.txt

# 6. File Deployment
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "$HOME/"

# 7. Caches & Wallpaper
[ -d "$HOME/.local/share/fonts" ] && fc-cache -fv >/dev/null
[ -d "$HOME/.local/share/applications" ] && update-desktop-database "$HOME/.local/share/applications"

if command -v awww &>/dev/null; then
    awww-daemon & sleep 1
    awww img "$HOME/.local/share/wallpapers/"* &
fi

# 8. Services & Shell
if pacman -Qs ly >/dev/null; then
    sudo systemctl enable ly@tty2.service
    sudo systemctl disable getty@tty2.service || true
fi

if command -v ufw &>/dev/null; then
    sudo ufw default deny incoming
    sudo ufw allow ssh
    sudo systemctl enable --now ufw
    sudo ufw enable || true
fi

if [[ "$fish_choice" =~ ^[Yy]$ ]]; then
    ! command -v fish &>/dev/null && sudo pacman -S --noconfirm fish
    sudo chsh -s /usr/bin/fish "$USER"
fi

# 9. Cleanup
cd "$HOME"
rm -rf "$CLONE_DIR"
echo "Done. Reboot recommended."
