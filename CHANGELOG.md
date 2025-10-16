# Changelog

## [Unreleased]

### Fixed
- **CRITICAL: Fixed Waybar recording status indicator**
  - Root cause: Double-triggering from both Hyprland keybind and Python app's global shortcuts
  - Solution: Removed Hyprland keybind, using only Python app's evdev-based shortcuts
  - Fixed `_update_recording_status()` method indentation in `lib/main.py`
  - Upgraded status monitoring from polling to event-driven using `inotify`
  - Result: Instant status updates (<100ms), no more inverted RDY/REC states
  - Performance: ~95% CPU reduction when idle

### Added
- **System restart utility** (`restart_hyprwhspr.sh`)
  - Complete system restart with cleanup
  - Automated status verification
  - User-friendly test instructions

- **Comprehensive system documentation** (`SYSTEM_ARCHITECTURE.md`)
  - Complete architecture overview
  - Component interaction diagrams
  - Debugging guide
  - Configuration reference

- **Python cache exclusions**
  - Added `.gitignore` rules for `__pycache__/` and `*.pyc`

### Changed
- Event-driven Waybar monitoring (inotify-based instead of polling)
- Status file management now exclusively handled by Python app
- Removed conflicting Hyprland keybind for ALT+SPACE

## [1.2.9] - 2024-09-28

### Changed
- Improved microphone detection and handling
- Tray improvements for performance and utility
- Refined Whisper transcription prompt examples

### Fixed
- Omarchy installation and waybar integration issues
- Microphone check for edge case bugs
