#!/bin/bash

# Function to install inotify-tools
install_inotify_tools() {
  echo "Checking for inotify-tools..."
  if ! command -v inotifywait &> /dev/null; then
    echo "inotifywait is not installed. Attempting to install inotify-tools..."
    if command -v apt &> /dev/null; then
      sudo apt update && sudo apt install -y inotify-tools
    elif command -v dnf &> /dev/null; then
      sudo dnf install -y inotify-tools
    elif command -v pacman &> /dev/null; then
      sudo pacman -Sy --noconfirm inotify-tools
    elif command -v zypper &> /dev/null; then
      sudo zypper install -y inotify-tools
    else
      echo "Error: Could not detect package manager. Please install inotify-tools manually."
      exit 1
    fi

    if ! command -v inotifywait &> /dev/null; then
      echo "Error: Failed to install inotify-tools. Please install it manually."
      exit 1
    fi

    echo "inotify-tools installed successfully."
  else
    echo "inotify-tools is already installed."
  fi
}

# Install inotify-tools if not already installed
install_inotify_tools

# Detect if the system is running Wayland
#is_wayland() {
#  if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
#    return 0
#  else
#    return 1
#  fi
#}

# Prompt user for GNOME notifications preference
echo "Do you want to receive GNOME notifications for patched Steam desktop files? [Y/n]"
read -r enable_notifications
enable_notifications=${enable_notifications:-Y}
echo "Do you want to hide games in the app menu? [Y/n]"
read -r hide_icons
hide_icons=${hide_icons:-Y}

# Create necessary directories
echo "Creating necessary directories..."
mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user

# Create the fix_steam_desktops.sh script
echo "Creating the fix_steam_desktops.sh script..."
cat << EOF > ~/.local/bin/fix_steam_desktops.sh
#!/bin/bash

APP_DIR="\$HOME/.local/share/applications"

# Function to update window title on Wayland
update_wayland_window_title() {
  local game_id="\$1"
  local desktop_name="\$2"
  local window_title="steam_app_\${game_id}"

  # Use xdg-activation or other Wayland-compatible tools to update the title
  echo "Wayland detected. Updating window title for \$window_title to \$desktop_name"
  # Placeholder for Wayland-specific title update logic
  # Feature implementation would depend on the specific Wayland compositor and tools available if needed...
}

# Watch for new or modified .desktop files
while inotifywait -q -e create,modify "\$APP_DIR"; do
  find "\$APP_DIR" -type f -name "*.desktop" | while read -r f; do
    # Skip files that already have a StartupWMClass field
    grep -q '^StartupWMClass=' "\$f" && continue

    WM_CLASS=""
    SOURCE=""

    # Detect Steam .desktop files
    if grep -q '^Icon=steam_icon_' "\$f"; then
      GAME_ID=\$(grep '^Icon=steam_icon_' "\$f" | head -1 | sed 's/Icon=steam_icon_//')
      WM_CLASS="steam_app_\${GAME_ID}"
      SOURCE="Steam"

    # Detect Lutris .desktop files
    elif grep -q 'lutris' "\$f" && grep -q '^Exec=.*lutris' "\$f"; then
      GAME_ID=\$(grep '^Exec=' "\$f" | head -1 | grep -oP 'rungameid/\K[0-9]+')
      if [ -n "\$GAME_ID" ]; then
        WM_CLASS="lutris-\${GAME_ID}"
      else
        WM_CLASS=\$(basename "\$f" .desktop)
      fi
      SOURCE="Lutris"

    # Detect Heroic .desktop files
    elif grep -q '^Exec=.*heroic' "\$f" || basename "\$f" | grep -q 'heroicgameslauncher'; then
      WM_CLASS=\$(basename "\$f" .desktop)
      SOURCE="Heroic"
    fi

    # Skip if no supported launcher detected
    [ -z "\$WM_CLASS" ] && continue

    DESKTOP_NAME=\$(basename "\$f" .desktop)

    # Add the StartupWMClass field
    echo "Patching \$f (\$SOURCE) with StartupWMClass=\$WM_CLASS"
    echo "StartupWMClass=\$WM_CLASS" >> "\$f"

    # Handle Wayland-specific window title updates
    #if [ "\$XDG_SESSION_TYPE" = "wayland" ]; then
    #  update_wayland_window_title "\$GAME_ID" "\$DESKTOP_NAME"
    #fi

EOF

if [[ $hide_icons =~ ^[Yy]$ ]]; then
  cat << 'EOF' >> ~/.local/bin/fix_steam_desktops.sh
    # Hide icons in App menu
    echo "NoDisplay=true" >> "$f"
EOF
fi

if [[ $enable_notifications =~ ^[Yy]$ ]]; then
  cat << 'EOF' >> ~/.local/bin/fix_steam_desktops.sh
    # GNOME notification
    notify-send "Steam Desktop File Patched" "Patched $f with StartupWMClass=$WM_CLASS"
EOF
fi

cat << 'EOF' >> ~/.local/bin/fix_steam_desktops.sh
  done
done
EOF

# Make the script executable
chmod +x ~/.local/bin/fix_steam_desktops.sh

# Create the systemd path unit file
echo "Creating systemd path unit..."
cat << 'EOF' > ~/.config/systemd/user/fix-steam-desktops.path
[Unit]
Description=Watch for new or modified game .desktop files and fix StartupWMClass

[Path]
PathModified=%h/.local/share/applications/
PathChanged=%h/.local/share/applications/

[Install]
WantedBy=default.target
EOF

# Create the systemd service unit file
echo "Creating systemd service unit..."
cat << 'EOF' > ~/.config/systemd/user/fix-steam-desktops.service
[Unit]
Description=Fix game launcher .desktop files with missing StartupWMClass

[Service]
Type=oneshot
ExecStart=%h/.local/bin/fix_steam_desktops.sh
EOF

# Reload and restart systemd configurations
echo "Reloading and restarting systemd configurations..."
systemctl --user daemon-reload
systemctl --user enable --now fix-steam-desktops.path
systemctl --user restart fix-steam-desktops.path

# Notify user of successful setup if notifications are enabled
if [[ "$enable_notifications" =~ ^[Yy]$ ]]; then
  notify-send "Setup Complete" "The system is now set up to automatically fix Steam desktop files as they are created or modified."
fi

# Done
echo "Setup complete. The system is now set up to automatically fix Steam desktop files as they are created or modified."
