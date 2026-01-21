#!/bin/bash

# 1. Manually set the PATH so the script can find 'awww' and 'swww'
PATH="/usr/local/bin:/usr/bin:/bin:/home/kevin/.local/bin:$PATH"

# 2. Use the full path for your wallpaper dir to be safe
WALLPAPER_DIR="$HOME/.local/share/wallpapers"

# 3. Wait for the background daemon
sleep 1 

# 4. The logic
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" \) | shuf -n 1)

# 5. Call your command
if [ -n "$WALLPAPER" ]; then
    awww img "$WALLPAPER" \
      --transition-type wave \
      --transition-fps 120 \
      --transition-duration 3.0
fi
