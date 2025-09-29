# Hyprwhspr Installation & Configuration Fixes

## Issues Fixed

### 1. **ydotool Service Configuration**
**Problem**: Installation script created conflicting ydotool services
- System `ydotool.service` was running
- Hyprwhspr-specific `ydotoold.service` was failing due to socket conflict

**Fix**:
- Disabled conflicting `ydotoold.service`
- Updated tray script to check `ydotool.service` instead of `ydotoold.service`

### 2. **Missing Hyprland Keybind Configuration**
**Problem**: Install script didn't add SUPER+ALT+D keybind to Hyprland config
- Keybind was not configured in `/home/techno/.config/hypr/bindings.conf`

**Fix**:
- Initially added Hyprland keybind
- Later removed it to let service handle internally (see issue #4)

### 3. **Waybar Integration Issues**
**Problem**: Waybar module name mismatch
- Config referenced `"hyprwhspr"` but module was defined as `"custom/hyprwhspr"`

**Fix**:
- Corrected waybar config to use `"custom/hyprwhspr"`
- Fixed tray script paths to use user config location
- Reduced polling interval from 2s to 1s for more responsive updates

### 4. **Tray Script Aggressive Health Checking**
**Problem**: Tray script was restarting service during normal operation
- `check_service_health()` restarted service when in "activating" state
- Toggle function controlled systemd service instead of recording state
- Created false ERR states during transcription

**Fix**:
- Removed aggressive health check from status monitoring
- Removed Hyprland keybind to let service handle SUPER+ALT+D internally
- Service now uses internal evdev keyboard detection without external interference

### 5. **Process Conflicts**
**Problem**: Multiple hyprwhspr processes running simultaneously
- Manual test processes conflicted with systemd service
- Caused service restart loops

**Fix**:
- Identified and killed conflicting processes
- Ensured only systemd-managed service runs

## Files Modified

### 1. `/home/techno/.config/hypr/bindings.conf`
```diff
# hyprwhspr - Speech to Text (handled internally by service)
# bindd = SUPER ALT, D, hyprwhspr Voice, exec, ~/.config/hypr/scripts/hyprwhspr-tray.sh toggle
```

### 2. `/home/techno/.config/waybar/config.jsonc`
```diff
  "modules-right": [
-   "hyprwhspr",
+   "custom/hyprwhspr",
    "tray",
  ],

  "custom/hyprwhspr": {
-   "exec": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh status",
-   "interval": 2,
+   "exec": "~/.config/hypr/scripts/hyprwhspr-tray.sh status",
+   "interval": 1,
    "return-type": "json",
    "exec-on-event": true,
    "format": "{}",
-   "on-click": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh toggle",
-   "on-click-right": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh start",
-   "on-click-middle": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh restart",
+   "on-click": "~/.config/hypr/scripts/hyprwhspr-tray.sh toggle",
+   "on-click-right": "~/.config/hypr/scripts/hyprwhspr-tray.sh start",
+   "on-click-middle": "~/.config/hypr/scripts/hyprwhspr-tray.sh restart",
    "tooltip": true,
  },
```

### 3. `/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh`
```diff
 is_ydotoold_running() {
     # Check if service is active
-    if systemctl --user is-active --quiet ydotoold.service; then
+    if systemctl --user is-active --quiet ydotool.service; then
         # Test if ydotool actually works by using a simple command
         timeout 1s ydotool help > /dev/null 2>&1
         return $?
     fi
     return 1
 }

 start_ydotoold() {
     if ! is_ydotoold_running; then
         echo "Starting ydotoold..."
-        systemctl --user start ydotoold.service
+        systemctl --user start ydotool.service
         sleep 1

 get_current_state() {
     local reason=""

-    # Check service health first
-    check_service_health
-
     # Check if service is running
     if ! systemctl --user is-active --quiet hyprwhspr.service; then
```

### 4. System Service Management
```bash
# Disabled conflicting service
systemctl --user disable ydotoold.service

# Ensured correct service is running
systemctl --user enable --now ydotool.service
```

## Installation Script Improvements Needed

To make these fixes permanent, the following should be updated in the installation script:

1. **Check for existing ydotool service** before creating ydotoold.service
2. **Add proper Hyprland keybind configuration** (or document that service handles internally)
3. **Fix waybar module name** in generated config
4. **Remove aggressive health checking** from tray script
5. **Use correct service names** in tray script

## Current Working State

- ✅ **Voice recording**: SUPER+ALT+D starts/stops recording with audio feedback
- ✅ **Transcription**: Speech converted to text accurately
- ✅ **Text injection**: Transcribed text pasted automatically
- ✅ **Waybar integration**: Shows RDY/REC states correctly without false ERR states
- ✅ **Service stability**: No more restart loops or conflicts

## Next Steps

1. Apply these fixes to the source repository
2. Update installation script to prevent these issues
3. Test on fresh installation to ensure fixes work universally