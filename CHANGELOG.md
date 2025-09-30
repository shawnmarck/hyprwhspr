# Changelog

## [Unreleased]

### Added
- **SPACE key support** in keybind configuration
  - Now supports special keys: SPACE, ENTER, TAB, ESC, BACKSPACE
  - Enables `ALT+SPACE` and other space-based shortcuts
  - Updated `lib/src/global_shortcuts.py` with `special_key_map`

- **Instant waybar status updates** 
  - New continuous monitoring script: `config/hyprland/hyprwhspr-tray-watch.sh`
  - Event-driven updates (no polling interval)
  - Performance: ~95% less CPU usage when idle, <100ms status transitions
  - Adaptive sleep: 100ms during recording, 500ms when idle

### Changed
- Waybar integration now uses continuous monitoring instead of 1-second polling
- Updated `config/waybar/hyprwhspr-module.jsonc` to remove `interval` parameter

### Fixed
- Fixed ydotool service conflicts (use system `ydotool.service` instead of custom `ydotoold.service`)
- Fixed waybar module name mismatch (`custom/hyprwhspr` vs `hyprwhspr`)
- Removed aggressive health checking that caused false ERR states
- Fixed path inconsistencies in tray scripts

## [1.2.9] - 2024-09-28

### Changed
- Improved microphone detection and handling
- Tray improvements for performance and utility
- Refined Whisper transcription prompt examples

### Fixed
- Omarchy installation and waybar integration issues
- Microphone check for edge case bugs
