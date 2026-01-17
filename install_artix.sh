#!/usr/bin/env bash
set -euo pipefail

echo "=== Universal Bootstrap (Arch/Artix) ==="

# 0. User input
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

# 1. detect if on artix
IS_ARTIX=false
if [ -f /etc/artix-release ]; then
    IS_ARTIX=true
    echo "Artix Linux detected. Configuring Repositories..."

    # Step A: Fix System Clock
    sudo hwclock --systohc || true

    # Step B: Sync base Artix system
    sudo pacman -Sy --noconfirm

    # Step C: Install Arch compatibility layer
    sudo pacman -S --needed --noconfirm artix-archlinux-support

    # Step D: Install Arch mirrorlist
    sudo pacman -S --needed --noconfirm archlinux-mirrorlist

    # Step E: Sanitize Arch mirrors (prevents 404s)
    sudo sed -i '/^Server = http:/d' /etc/pacman.d/mirrorlist-arch
    sudo sed -i '/^#/d' /etc/pacman.d/mirrorlist-arch
    sudo sed -i '1i Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
        /etc/pacman.d/mirrorlist-arch

    # Step F: Add Arch repositories (append-only, safe)
    if ! grep -q '^\[extra\]' /etc/pacman.conf; then
        sudo bash -c 'cat <<EOF >> /etc/pacman.conf

# Arch Linux repositories
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF'
    fi

    # Step G: Initialize Keyrings
    sudo pacman-key --init
    sudo pacman-key --populate artix archlinux

    # Step H: Full resync
    sudo pacman -Syy --noconfirm
fi

# 2. Clone repo
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
rm -rf "$CLONE_DIR"
git clone "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# 3. install questions
[[ "$ucode_choice" == "amd" ]] && sudo pacman -S --needed --noconfirm amd-ucode
[[ "$ucode_choice" == "intel" ]] && sudo pacman -S --needed --noconfirm intel-ucode

case "$vulkan_choice" in
    intel)
        sudo pacman -S --needed --noconfirm vulkan-intel vulkan-icd-loader
        ;;
    amd)
        sudo pacman -R --noconfirm amdvlk || true
        sudo pacman -S --needed --noconfirm vulkan-radeon vulkan-icd-loader
        ;;
esac

if [[ "$discord_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed --noconfirm discord
fi

sudo mkinitcpio -P

# 4. yay
if ! command -v yay &>/dev/null; then
    tempdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tempdir/yay"
    pushd "$tempdir/yay" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tempdir"
fi

# 5. Packages Install
if [ "$IS_ARTIX" = true ] && [ -f "packages/artix.txt" ]; then
    sudo pacman -S --needed --noconfirm - < packages/artix.txt
elif [ -f "packages/pacman.txt" ]; then
    sudo pacman -S --needed --noconfirm - < packages/pacman.txt
fi

[ -f "packages/aur.txt" ] && yay -S --needed --noconfirm - < packages/aur.txt

# 6. Deploy files
[ -d "etc" ] && sudo rsync -a etc/ /etc/
[ -d "usr" ] && sudo rsync -a usr/ /usr/
[ -d "home" ] && rsync -a home/ "$HOME/"

# 7. Update system caches
[ -d "$HOME/.local/share/fonts" ] && fc-cache -fv >/dev/null
[ -d "$HOME/.local/share/applications" ] && update-desktop-database "$HOME/.local/share/applications"

# 8. services
echo "Configuring Init Services..."

if [ "$IS_ARTIX" = true ]; then
    if pacman -Qs ly-dinit >/dev/null; then
        sudo ln -sf /usr/lib/dinit.d/ly /etc/dinit.d/boot.d/ly
    fi
    if command -v ufw &>/dev/null; then
        pacman -Qs ufw-dinit >/dev/null || sudo pacman -S --noconfirm ufw-dinit
        sudo ln -sf /usr/lib/dinit.d/ufw /etc/dinit.d/boot.d/ufw
    fi
else
    if pacman -Qs ly >/dev/null; then
        sudo systemctl enable ly@tty2.service
        sudo systemctl disable getty@tty2.service || true
    fi
    if command -v ufw &>/dev/null; then
        sudo systemctl enable --now ufw
    fi
fi

if command -v ufw &>/dev/null; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw allow http
    sudo ufw allow https
    echo "y" | sudo ufw enable || true
fi

if [[ "$fish_choice" =~ ^[Yy]$ ]]; then
    sudo pacman -S --needed --noconfirm fish
    sudo chsh -s /usr/bin/fish "$USER"
fi

# 9. Cleanup
sudo chown -R "$USER:$USER" "$HOME"
rm -rf "$CLONE_DIR"

echo "=== Setup Complete ==="
read -p "Reboot now? [y/N]: " confirm_reboot
if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
    sudo reboot
fi
