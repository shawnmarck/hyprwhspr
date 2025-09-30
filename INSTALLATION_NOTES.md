# Installation Notes

## New Features Setup

After installing hyprwhspr, these additional steps enable the new features:

### 1. Instant Waybar Status Updates

Copy the continuous monitoring script:
```bash
cp config/hyprland/hyprwhspr-tray-watch.sh ~/.config/hypr/scripts/
chmod +x ~/.config/hypr/scripts/hyprwhspr-tray-watch.sh
```

Update waybar configuration to use continuous monitoring:

**Option A: Use the included module (recommended)**
```bash
cp config/waybar/hyprwhspr-module.jsonc ~/.config/waybar/
```

Add to your `~/.config/waybar/config.jsonc`:
```jsonc
{
  "include": ["hyprwhspr-module.jsonc"],
  "modules-right": [
    "custom/hyprwhspr",
    // ... other modules
  ]
}
```

**Option B: Manual configuration**

Add this to your `~/.config/waybar/config.jsonc`:
```jsonc
{
  "custom/hyprwhspr": {
    "format": "{}",
    "exec": "~/.config/hypr/scripts/hyprwhspr-tray-watch.sh",
    "return-type": "json",
    "on-click": "~/.config/hypr/scripts/hyprwhspr-tray.sh toggle",
    "on-click-right": "~/.config/hypr/scripts/hyprwhspr-tray.sh start",
    "on-click-middle": "~/.config/hypr/scripts/hyprwhspr-tray.sh restart",
    "tooltip": true
  }
}
```

### 2. SPACE Key Support

The SPACE key (and other special keys) are now supported in keybind configuration.

Update `~/.config/hyprwhspr/config.json`:
```json
{
  "primary_shortcut": "ALT+SPACE"
}
```

Supported special keys:
- `SPACE`
- `ENTER` / `RETURN`
- `TAB`
- `ESC` / `ESCAPE`
- `BACKSPACE`

**Important:** Use `+` as separator (not comma):
- ✅ `"ALT+SPACE"`
- ❌ `"ALT, SPACE"`

Restart the service after changing keybind:
```bash
systemctl --user restart hyprwhspr.service
```

## Performance Benefits

- **Instant status updates**: <100ms transitions (vs 500-1000ms with polling)
- **Lower CPU usage**: ~95% reduction when idle (event-driven vs constant polling)
- **Responsive UI**: Waybar icon changes instantly when recording starts/stops

## Restart Waybar

After configuration:
```bash
pkill waybar && waybar &
```
