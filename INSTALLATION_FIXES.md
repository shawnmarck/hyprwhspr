# Installation Fixes for Omarchy/Arch Linux

## Post-Installation Steps Required

After running the standard installation script, perform these additional steps to ensure proper functionality:

### 1. Fix ydotool Service Conflicts

The installation creates a conflicting ydotool service. Fix this:

```bash
# Disable the conflicting ydotoold service
systemctl --user disable ydotoold.service

# Ensure the system ydotool service is running
systemctl --user enable --now ydotool.service
```

### 2. Fix Waybar Configuration

The waybar integration needs corrections:

**In `~/.config/waybar/config.jsonc`:**
```jsonc
{
  "modules-right": [
    "custom/hyprwhspr",  // Change from "hyprwhspr" to "custom/hyprwhspr"
    "tray",
    // ... other modules
  ],

  "custom/hyprwhspr": {
    "exec": "~/.config/hypr/scripts/hyprwhspr-tray.sh status",
    "interval": 1,  // Reduced from 2 for better responsiveness
    "return-type": "json",
    "exec-on-event": true,
    "format": "{}",
    "on-click": "~/.config/hypr/scripts/hyprwhspr-tray.sh toggle",
    "on-click-right": "~/.config/hypr/scripts/hyprwhspr-tray.sh start",
    "on-click-middle": "~/.config/hypr/scripts/hyprwhspr-tray.sh restart",
    "tooltip": true
  }
}
```

### 3. Remove Conflicting Hyprland Keybind

**Important**: Do NOT add a Hyprland keybind for SUPER+ALT+D. The service handles this internally.

If you added one, comment it out in your Hyprland config:
```
# hyprwhspr - Speech to Text (handled internally by service)
# bindd = SUPER ALT, D, hyprwhspr Voice, exec, ~/.config/hypr/scripts/hyprwhspr-tray.sh toggle
```

### 4. Restart Services

```bash
# Restart waybar to apply changes
pkill waybar && waybar &

# Reload Hyprland config
hyprctl reload

# Restart hyprwhspr service
systemctl --user restart hyprwhspr.service
```

## Verification

After applying these fixes:

1. **Service Status**: `systemctl --user status hyprwhspr.service` should show "active (running)"
2. **Waybar Icon**: Should show "RDY" in green
3. **Recording**: Press SUPER+ALT+D to hear beep and see "REC" state
4. **Transcription**: Press SUPER+ALT+D again to stop recording, transcribe, and paste text

## Troubleshooting

If you experience issues:

1. **Check for multiple processes**: `ps aux | grep hyprwhspr | grep -v grep`
2. **Kill any manual processes**: Keep only the systemd-managed one
3. **Check logs**: `journalctl --user -u hyprwhspr.service -f`
4. **Verify no conflicting services**: `systemctl --user list-units | grep ydotool`

## Why These Fixes Are Needed

- **ydotool conflict**: Installation script creates both system and user ydotool services
- **Waybar module name**: Template uses incorrect module reference
- **Keybind conflict**: External and internal keyboard handling interfere
- **Health check aggression**: Tray script restarts service unnecessarily
- **Path inconsistencies**: Mixed references to /opt and ~/.config locations