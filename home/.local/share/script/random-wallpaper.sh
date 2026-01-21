#!/bin/bash

PATH="/usr/local/bin:/usr/bin:/bin:/home/kevin/.local/bin:$PATH"

WALLPAPER_DIR="$HOME/.local/share/wallpapers"
 

# 4. The logic
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" \) | shuf -n 1)

# 5. Call your command
if [ -n "$WALLPAPER" ]; then
    awww img "$WALLPAPER" \
      --transition-type wave \
      --transition-fps 120 \
      --transition-duration 3.0
fi
