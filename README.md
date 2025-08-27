# HyprWhspr 🎤

**Native speech-to-text for Omarchy** - Fast, accurate, easy and fully integrated.

---

- **Optimized for Omarchy** - Seamless integration with Omarchy/Hyprland & Waybar
- **Whisper-powered** - State-of-the-art speech recognition via Whisper
- **NVIDIA GPU support** - Automatic CUDA detection and acceleration
- **Zero-config audio** - Auto-detects PipeWire/ALSA devices
- **Audio feedback** - Optional sound notifications for recording start/stop
- **Word overrides** - Customize transcriptions and corrections
- **Systemd integration** - Starts automatically on login
- **No root** - Runs in user space

## Quick start

### Prerequisites
- **Omarchy**
- **NVIDIA GPU** (optional, for acceleration)

### Installation

```bash
# Clone the repository
git clone https://github.com/goodroot/hyprwhspr.git
cd hyprwhisper

# Run the automated installer
./scripts/install-omarchy.sh
```

**The installer will:**
1. ✅ Install system dependencies (ydotoold, etc.)
2. ✅ Clone and build whisper.cpp (with CUDA if GPU available)
3. ✅ Download base Whisper models
4. ✅ Set up systemd services for omarchy-whisper & ydotoolds
5. ✅ Configure Hyprland integration
6. ✅ Test everything works

### First use

1. **Log out and back in** (for group permissions)
2. **Press `Super+Alt+D`** to start dictation
3. **Speak naturally** - text appears instantly
4. **Press `Super+Alt+D`** again to stop dictation

x. **Check system tray** for status indicators

**Note:** Audio feedback is disabled by default. If you want sound notifications when starting/stopping dictation, enable it in the configuration section below.

If you heard the audio cue but did not see your text appear...

Ensure your microphone of choice is available in audio settings, input.

## Usage

### Toggle-able global hotkey

- **`Super+Alt+D`** - Toggle dictation on/off

### Status icons

Minimal waybar feedback.

- **󰍬** - Ready to record (Hyprwhspr running, ydotool working)
- **󰍯** - Currently recording (actively processing audio)
- **󰆉** - Issue detected (Hyprwhspr not running or ydotool not working)s

_Inspired by Whispertux._

### Audio feedback

Enable custom sound notifications for recording start/stop:

```json
{
    "audio_feedback": true,
    "start_sound_volume": 0.3,
    "stop_sound_volume": 0.3,
    "start_sound_path": "custom-start.ogg",  # Optional: custom start sound
    "stop_sound_path": "custom-stop.ogg"     # Optional: custom stop sound
}
```

## Configuration

Edit `~/.config/hyprwhspr/config.json`:

**Minimal config** - only 2 essential options:

```json
{
    "primary_shortcut": "SUPER+ALT+D",
    "model": "base.en"
}
```

**Model options**:

- **Default**: `"base.en"` (automatically resolves to `/opt/hyprwhspr/whisper.cpp/models/ggml-base.en.bin`)
- **Tiny (fastest)**: `"tiny.en"`
- **Small (better)**: `"small.en"`
- **Medium (high accuracy)**: `"medium.en"`
- **Large (best accuracy)**: `"large"` ⚠️ **GPU required**
- **Large-v3 (latest)**: `"large-v3"` ⚠️ **GPU required**

**Word overrides** - optional sound notifications:

```json
{
    "word_overrides": {
        "hyperwhisper": "HyprWhspr",
        "omarchie": "Omarchy"
    }
}
```

**Audio feedback** - optional sound notifications:

```json
{
    "audio_feedback": true,            # Enable audio feedback (default: false)
    "start_sound_volume": 0.3,        # Start recording sound volume (0.1 to 1.0)
    "stop_sound_volume": 0.3,         # Stop recording sound volume (0.1 to 1.0)
    "start_sound_path": "custom-start.ogg",  # Custom start sound (relative to assets)
    "stop_sound_path": "custom-stop.ogg"     # Custom stop sound (relative to assets)
}
```

**Default sounds included:**
- **Start recording**: `ping-up.ogg` (ascending tone)
- **Stop recording**: `ping-down.ogg` (descending tone)

**Custom sounds:**
- **Supported formats**: `.ogg`, `.wav`, `.mp3`
- **Fallback**: Uses defaults if custom files don't exist

### Waybar integration

**Enhanced JSON output with dynamic tooltips and CSS animations**

Add to your `~/.config/waybar/config`:

```json
{
    "custom/hyprwhspr": {
        "exec": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh status",
        "interval": 2,
        "return-type": "json",
        "exec-on-event": true,
        "format": "{}",
        "on-click": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh toggle",
        "on-click-right": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh start",
        "on-click-middle": "/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh restart",
        "tooltip": true
    }
}
```

**Add CSS styling** to your `~/.config/waybar/style.css`:

```css
@import "/opt/hyprwhspr/config/waybar/hyprwhspr-style.css";
```

**Features:**
- **Dynamic tooltips** that change based on current state
- **Smooth animations** for recording, error, and ready states
- **JSON output** with CSS classes for styling
- **Real-time updates** with `exec-on-event: true`

**Icon states:**

- **󰍬** - Ready to record (Hyprwhspr running, ydotool working)
- **󰍯** - Currently recording (actively processing audio)
- **󰆉** - Issue detected (Hyprwhspr not running or ydotool not working)

**Click interactions:**

- **Left-click**: Toggle Hyprwhspr on/off
- **Right-click**: Start Hyprwhspr (if not running)
- **Middle-click**: Restart Hyprwhspr


## Advanced Setup

### NVIDIA GPU Acceleration

Use if adding GPU after GPU-less installation

```bash
# Build with CUDA support (if NVIDIA detected)
/opt/hyprwhspr/scripts/build-whisper-nvidia.sh

# Test GPU acceleration
/opt/hyprwhspr/scripts/build-whisper-nvidia.sh --test
```

### Whisper Models

**Default model included:** `ggml-base.en.bin` (CPU-optimized, ~1GB)

**Available models to download:**

```bash
cd /opt/hyprwhspr/whisper.cpp

# Tiny models (fastest, least accurate)
sh ./models/download-ggml-model.sh tiny.en      # ~39MB
sh ./models/download-ggml-model.sh tiny         # ~39MB

# Base models (good balance)
sh ./models/download-ggml-model.sh base.en      # ~1GB (default)
sh ./models/download-ggml-model.sh base         # ~1GB

# Small models (better accuracy)
sh ./models/download-ggml-model.sh small.en     # ~244MB
sh ./models/download-ggml-model.sh small        # ~244MB

# Medium models (high accuracy)
sh ./models/download-ggml-model.sh medium.en    # ~769MB
sh ./models/download-ggml-model.sh medium       # ~769MB

# Large models (best accuracy, requires GPU)
sh ./models/download-ggml-model.sh large        # ~1.5GB
sh ./models/download-ggml-model.sh large-v3     # ~1.5GB (latest)
```

**⚠️ GPU Acceleration Required:**

Models `large` and `large-v3` require NVIDIA GPU acceleration for reasonable performance. 

Without a GPU, these models will be extremely slow (10-30 seconds per transcription).

**Model selection guide:**
- **`tiny.en`** - Fastest, good for real-time dictation
- **`base.en`** - Best balance of speed/accuracy (recommended)
- **`small.en`** - Better accuracy, still fast
- **`medium.en`** - High accuracy, slower processing
- **`large`** - Best accuracy, **requires GPU acceleration** for reasonable speed
- **`large-v3`** - Latest large model, **requires GPU acceleration** for reasonable speed

**Update your config after downloading:**

```json
{
    "model": "small.en"
}
```

**Other DEs:**

Gnome, KDE, etc might work.

Untested.

### Manual Permissions Fix

```bash
# If you encounter permission issues
/opt/hyprwhspr/scripts/fix-uinput-permissions.sh
```

## Architecture

**HyprWhspr is designed as a system package:**

- **`/opt/hyprwhspr/`** - Main installation directory
- **`/opt/hyprwhspr/lib/`** - Python application
- **`/opt/hyprwhspr/whisper.cpp/`** - Speech recognition engine
- **`~/.config/hyprwhspr/`** - User configuration
- **`~/.config/systemd/user/`** - Systemd service

### Systemd integration

**HyprWhspr uses systemd for reliable service management:**

- **`hyprwhspr.service`** - Main application service with auto-restart
- **`ydotool.service`** - Input injection daemon service
- **Tray integration** - All tray operations use systemd commands
- **Process management** - No manual process killing or starting
- **Service dependencies** - Proper startup/shutdown ordering

## Troubleshooting

### Common issues

**I heard the sound spoke, but don't see text!** 

It's fairly common in Arch and other distros for the microphone to need to be plugged in and set each time you log in and out of your session, including during a restart. Within sound options, ensure that the microphone is indeed set. The sound utility will show feedback from the microphone if it is.

**Hotkey not working:**

```bash
# Check service status
systemctl --user status hyprwhspr.service

# Check logs
journalctl --user -u hyprwhspr.service -f
```

**Permission denied:**

```bash
# Fix uinput permissions
/opt/hyprwhspr/scripts/fix-uinput-permissions.sh

# Log out and back in
```

**No audio input:**

```bash
# Check audio devices
pactl list short sources

# Restart PipeWire
systemctl --user restart pipewire
```

**Audio feedback not working:**

```bash
# Check if audio feedback is enabled in config
cat ~/.config/hyprwhspr/config.json | grep audio_feedback

# Verify sound files exist
ls -la /opt/hyprwhspr/assets/

# Check if ffplay/aplay/paplay is available
which ffplay aplay paplay
```

**Model not found:**

```bash
# Check if model exists
ls -la /opt/hyprwhspr/whisper.cpp/models/

# Download a different model
cd /opt/hyprwhspr/whisper.cpp
sh ./models/download-ggml-model.sh tiny.en

# Verify model path in config
cat ~/.config/hyprwhspr/config.json | grep model
```

**Stuck recording state:**

```bash
# Check service health and auto-recover
/opt/hyprwhspr/config/hyprland/hyprwhspr-tray.sh health

# Manual restart if needed
systemctl --user restart hyprwhspr.service

# Check service status
systemctl --user status hyprwhspr.service
```

### Getting help

1. **Check logs**: `journalctl --user -u hyprwhspr.service`
2. **Verify permissions**: Run the permissions fix script
3. **Test components**: Check ydotool, audio devices, whisper.cpp
4. **Report issues**: Include logs and system information

## Updates

Run `git pull` in `/opt/hyprwhspr/`

## License

MIT License - see [LICENSE](LICENSE) file.

## Contributing

Create an issue, happy to help!  

For pull requests, also best to start with an issue.

---

**Built with ❤️ for the Omarchy community**

*Integrated and natural speech-to-text.*
