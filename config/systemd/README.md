# HyprWhspr Systemd Services

This directory contains systemd user services for HyprWhspr integration with Hyprland.

## Services

### hyprwhspr.service
The main HyprWhspr voice dictation service. This service:
- Waits for the Hyprland Wayland session to be ready
- Includes a 2-second startup delay for proper initialization
- Automatically restarts on failure
- Uses proper Wayland session targets

### ydotool.service
The ydotool daemon service for text injection. This service:
- Provides text input automation capabilities
- Waits for the Hyprland Wayland session to be ready
- Includes startup delay and proper error handling
- Required for text injection functionality

## Installation

### Automatic Installation
Run the installation script:
```bash
./scripts/install-services.sh
```

### Manual Installation
1. Copy service files to your user systemd directory:
   ```bash
   cp config/systemd/*.service ~/.config/systemd/user/
   ```

2. Reload systemd configuration:
   ```bash
   systemctl --user daemon-reload
   ```

3. Enable services:
   ```bash
   systemctl --user enable hyprwhspr
   systemctl --user enable ydotool
   ```

## Usage

### Start Services
```bash
systemctl --user start hyprwhspr
systemctl --user start ydotool
```

### Check Status
```bash
systemctl --user status hyprwhspr
systemctl --user status ydotool
```

### Stop Services
```bash
systemctl --user stop hyprwhspr
systemctl --user stop ydotool
```

### View Logs
```bash
journalctl --user -u hyprwhspr -f
journalctl --user -u ydotool -f
```

## Configuration

The services are configured to:
- Start automatically when you log into your Hyprland session
- Wait for the Wayland session to be fully ready
- Include proper startup delays for system initialization
- Restart automatically on failure

## Troubleshooting

If services fail to start:
1. Check if Hyprland is running: `systemctl --user status wayland-session@hyprland.desktop.target`
2. Verify ydotool is installed: `which ydotool`
3. Check service logs: `journalctl --user -u <service-name> -n 50`
4. Ensure the binary paths in the services are correct for your system

## Dependencies

- Hyprland running with Wayland
- ydotool package installed
- Proper binary paths configured in service files
