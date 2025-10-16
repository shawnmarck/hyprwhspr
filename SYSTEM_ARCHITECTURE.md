# hyprwhspr System Architecture

## 🎯 Complete System Overview

### Components

1. **Hyprwhspr Service** (`systemd`)
   - Location: `~/.config/systemd/user/hyprwhspr.service`
   - Binary: `/opt/hyprwhspr/lib/main.py`
   - Status: Must be running for recording to work

2. **Waybar Integration**
   - Config: `~/.config/waybar/hyprwhspr-module.jsonc`
   - Monitor: `/home/techno/.config/hypr/scripts/hyprwhspr-tray-watch.sh`
   - Controller: `/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh`

3. **Hyprland Keybind**
   - Config: `~/.config/hypr/hyprland.conf`
   - Keybind: `ALT+SPACE`
   - Command: `keybind-toggle`

## 🔄 How It Works

### Recording Flow

```
User Press ALT+SPACE
    ↓
Hyprland Keybind Triggered
    ↓
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh keybind-toggle
    ↓
Creates/Removes: ~/.config/hyprwhspr/recording_status
    ↓
inotify detects file change (instant)
    ↓
hyprwhspr-tray-watch.sh outputs new status
    ↓
Waybar updates icon: RDY ↔ REC
```

### Status File System

- **File**: `~/.config/hyprwhspr/recording_status`
- **Content when recording**: `"recording"`
- **When not recording**: File doesn't exist

### Event-Driven Monitoring

The `hyprwhspr-tray-watch.sh` uses `inotify` to watch for file changes:
- No polling delays
- Instant status updates
- Low CPU usage

## 🎛️ Commands Available

### Tray Script Commands

```bash
# Show current status (JSON output)
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh status

# Toggle recording (for Waybar click)
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh record

# Toggle recording (for keybind - no JSON output)
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh keybind-toggle

# Service management
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh start
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh stop
/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh restart
```

### Service Management

```bash
# Check service status
systemctl --user status hyprwhspr.service

# Restart service
systemctl --user restart hyprwhspr.service

# View logs
journalctl --user -u hyprwhspr.service -f
```

### Complete System Restart

```bash
/home/techno/projects/hyprwhspr/restart_hyprwhspr.sh
```

## 🧪 Testing

### Manual Testing

1. **Test keybind**:
   - Press `ALT+SPACE` → Icon should turn RED "REC"
   - Press `ALT+SPACE` → Icon should turn GREEN "RDY"

2. **Test Waybar click**:
   - Left-click icon → Toggle recording
   - Right-click icon → Start service
   - Middle-click icon → Restart service

3. **Test status file**:
   ```bash
   # Create status file (should show REC)
   echo "recording" > ~/.config/hyprwhspr/recording_status
   
   # Remove status file (should show RDY)
   rm ~/.config/hyprwhspr/recording_status
   ```

### Debugging

1. **Check if keybind is working**:
   ```bash
   # Manually trigger keybind command
   /home/techno/.config/hypr/scripts/hyprwhspr-tray.sh keybind-toggle
   
   # Check if status file was created
   ls -la ~/.config/hyprwhspr/recording_status
   ```

2. **Check Waybar monitor**:
   ```bash
   # Check if monitor process is running
   ps aux | grep hyprwhspr-tray-watch
   
   # Test monitor output
   /home/techno/.config/hypr/scripts/hyprwhspr-tray-watch.sh
   ```

3. **Check service**:
   ```bash
   # Service status
   systemctl --user status hyprwhspr.service
   
   # Service logs
   journalctl --user -u hyprwhspr.service -n 50
   ```

## 🔧 Configuration Files

### Main Configuration
- **Waybar Module**: `~/.config/waybar/hyprwhspr-module.jsonc`
- **Waybar Style**: `~/.config/waybar/hyprwhspr-style.css`
- **Hyprland Config**: `~/.config/hypr/hyprland.conf`
- **App Config**: `~/.config/hyprwhspr/config.json`

### Scripts
- **Tray Controller**: `/home/techno/.config/hypr/scripts/hyprwhspr-tray.sh`
- **Tray Monitor**: `/home/techno/.config/hypr/scripts/hyprwhspr-tray-watch.sh`

### Status Files
- **Recording Status**: `~/.config/hyprwhspr/recording_status`

## 🚀 Quick Restart Guide

```bash
# Complete system restart
/home/techno/projects/hyprwhspr/restart_hyprwhspr.sh

# Or manually:
rm -f ~/.config/hyprwhspr/recording_status
systemctl --user restart hyprwhspr.service
killall waybar && waybar &
hyprctl reload
```

## ✅ Expected Behavior

### When Ready (RDY)
- Icon: Green 󰍬 RDY
- Status file: Does not exist
- Toast: "Ready to record"

### When Recording (REC)
- Icon: Red 󰍬 REC  
- Status file: Exists with content "recording"
- Toast: "Recording..."

### Transitions
- Should be **instant** (no delays)
- Icon and toast should **always match**
- No inverted behavior
