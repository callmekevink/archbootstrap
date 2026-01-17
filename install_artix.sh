#!/usr/bin/env bash
set -euo pipefail

echo "=== Universal Bootstrap (Arch/Artix) ==="

# 0. User input
read -p "AMD or Intel Ucode? [amd/intel]: " ucode_choice
read -p "Install Vulkan? [intel/amd/no]: " vulkan_choice
read -p "Use Fish shell? [y/N]: " fish_choice
read -p "Install Discord? [y/N]: " discord_choice

# 1. detetic if on artix
IS_ARTIX=false
if [ -f /etc/artix-release ]; then
    IS_ARTIX=true
    echo "Artix Linux detected. Configuring Repositories..."

    # Step A: Fix System Clock
    sudo hwclock --systohc || true

    # Step B: Clean up pacman.conf
    sudo sed -i '/^Include = \/etc\/pacman.d\/mirrorlist/d' /etc/pacman.conf

    # Step C: Rewrite base Artix structure
    sudo bash -c 'cat <<EOF > /etc/pacman.conf
[options]
HoldPkg     = pacman libc
Architecture = auto
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5

[system]
Include = /etc/pacman.d/mirrorlist

[world]
Include = /etc/pacman.d/mirrorlist

[galaxy]
Include = /etc/pacman.d/mirrorlist
EOF'

    # Step D: Inject your US Artix mirrors
    sudo bash -c 'cat <<EOF > /etc/pacman.d/mirrorlist
Server = https://artix.wheaton.edu/repos/\$repo/os/\$arch
Server = https://mirror.clarkson.edu/artix-linux/repos/\$repo/os/\$arch
Server = https://us-mirror.artixlinux.org/\$repo/os/\$arch
Server = http://www.nylxs.com/mirror/repos/\$repo/os/\$arch
Server = https://mirrors.nettek.us/artix-linux/\$repo/os/\$arch
EOF'

    # Step E: Sync Artix and install support
    sudo pacman -Sy --noconfirm
    sudo pacman -S --needed --noconfirm artix-archlinux-support

    # Step F: Install Arch mirrorlist (REQUIRED for extra/multilib)
    sudo pacman -S --needed --noconfirm archlinux-mirrorlist

    # Step F.1: Filter Arch mirrors to known-good HTTPS only (prevents 404s)
    sudo sed -i \
        -e '/^Server = http:/d' \
        -e '/tier =/d' \
        /etc/pacman.d/mirrorlist-arch

    # Step F.2: Force a known working Arch mirror to the top
    sudo sed -i '1i Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch' \
        /etc/pacman.d/mirrorlist-arch

    # Step F: Add Arch repositories to pacman.conf
    if ! grep -q "\[extra\]" /etc/pacman.conf; then
        sudo bash -c 'cat <<EOF >> /etc/pacman.conf

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF'
    fi

    # Step H: Initialize Keyrings
    echo "Initializing GPG Keyrings..."
    sudo pacman-key --init
    sudo pacman-key --populate artix archlinux

    # Final forced sync for everything
    sudo pacman -Syy --noconfirm
fi

# 2. Clone repo
REPO_URL="https://github.com/callmekevink/archbootstrap"
CLONE_DIR="$HOME/arch-setup"
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
git clone "$REPO_URL" "$CLONE_DIR"
cd "$CLONE_DIR"

# 3. install questions
[[ "$ucode_choice" == "amd" ]] && sudo pacman -S --needed --noconfirm amd-ucode
[[ "$ucode_choice" == "intel" ]] && sudo pacman -S --needed --noconfirm intel-ucode

case "$vulkan_choice" in
    intel) sudo pacman -S --needed --noconfirm vulkan-intel vulkan-icd-loader ;;
    amd) sudo pacman -R --noconfirm amdvlk || true
         sudo pacman -S --needed --noconfirm vulkan-radeon vulkan-icd-loader ;;
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

if command -v awww &>/dev/null; then # set wallpaper
    pgrep awww-daemon >/dev/null || awww-daemon &
    sleep 4
    WP_DIR="$HOME/.local/share/wallpapers"
    if [ -d "$WP_DIR" ] && [ "$(ls -A "$WP_DIR")" ]; then
        awww img "$WP_DIR/"* &
    fi
fi

# 8. services
echo "Configuring Init Services..."

if [ "$IS_ARTIX" = true ]; then
    if pacman -Qs ly-dinit >/dev/null; then
        sudo ln -s /usr/lib/dinit.d/ly /etc/dinit.d/boot.d/ || true
    fi
    if command -v ufw &>/dev/null; then
        sudo pacman -Sy
        pacman -Qs ufw-dinit >/dev/null || sudo pacman -S --noconfirm ufw-dinit
        sudo ln -s /usr/lib/dinit.d/ufw /etc/dinit.d/boot.d/ || true
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
    ! command -v fish &>/dev/null && sudo pacman -S --noconfirm fish
    sudo chsh -s /usr/bin/fish "$USER"
fi

# 9. Cleanup
sudo chown -R "$USER:$USER" "$HOME"
cd "$HOME"
rm -rf "$CLONE_DIR"

echo "=== Setup Complete ==="
read -p "Reboot now? [y/N]: " confirm_reboot
if [[ "$confirm_reboot" =~ ^[Yy]$ ]]; then
    sudo reboot
fi
