#!/usr/bin/env bash

PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
WALLPAPER_DIR="$DATA_HOME/wallpapers"


[ -d "$WALLPAPER_DIR" ] || exit 0

WALLPAPER="$(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | shuf -n 1)"

if [ -n "$WALLPAPER" ] && command -v awww >/dev/null 2>&1; then
    awww img "$WALLPAPER" \
        --transition-type wave \
        --transition-fps 120 \
        --transition-duration 3.0
fi
