#!/bin/bash
# HyprWhspr Omarchy/Arch Installation Script
# Automated installation for Hyprland + Arch Linux environments

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# Logging
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Config
PACKAGE_NAME="hyprwhspr"
INSTALL_DIR="/opt/hyprwhspr"   # default for Omarchy/manual

# Modes: AUR vs Omarchy
# AUR wrapper exports HYPRWHSPR_AUR_INSTALL=1
# Omarchy bootstrap can export HYPRWHSPR_OMARCHY=1
is_aur()      { [[ "$HYPRWHSPR_AUR_INSTALL" == "1" ]]; }
is_omarchy()  { [[ "$HYPRWHSPR_OMARCHY" == "1" ]]; }

# Decide whether to edit Waybar automatically
should_edit_waybar() {
  # explicit override wins
  if [[ "$HYPRWHSPR_WAYBAR_AUTO" == "1" ]]; then return 0; fi
  if [[ "$HYPRWHSPR_WAYBAR_AUTO" == "0" ]]; then return 1; fi
  # default: Omarchy=yes, AUR=no
  if is_omarchy; then return 0; fi
  return 1
}

# Safe backup helper
backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a -- "$f" "${f}.bak.${ts}"
  log_info "Backup created: ${f}.bak.${ts}"
}

# AUR mode operates in-place under /usr/lib
if is_aur; then
  INSTALL_DIR="/usr/lib/hyprwhspr"
fi

# Detect the actual user (handle sudo/root)
if [ "$EUID" -eq 0 ]; then
  if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
  else
    ACTUAL_USER=$(stat -c '%U' /home 2>/dev/null | head -1)
    [[ -z "$ACTUAL_USER" ]] && ACTUAL_USER="root"
  fi
else
  ACTUAL_USER="$USER"
fi

USER_CONFIG_DIR="/home/$ACTUAL_USER/.config/hyprwhspr"
SERVICE_NAME="hyprwhspr.service"

log_info "Setting up HyprWhspr for user: $ACTUAL_USER"

# Arch check
if ! command -v pacman &> /dev/null; then
  log_error "This script is designed for Arch Linux systems."
  exit 1
fi

log_info "Starting HyprWhspr installation..."

# --- Dependencies ---
install_system_dependencies() {
  log_info "Installing system dependencies..."
  local packages_to_install=()

  for pkg in cmake make git base-devel; do
    if ! pacman -Q "$pkg" &>/dev/null; then packages_to_install+=("$pkg"); else log_info "$pkg already installed"; fi
  done
  for pkg in python; do
    if ! pacman -Q "$pkg" &>/dev/null; then packages_to_install+=("$pkg"); else log_info "$pkg already installed"; fi
  done
  log_info "python-pip not required - using venv's pip"
  for pkg in pipewire pipewire-alsa pipewire-pulse pipewire-jack; do
    if ! pacman -Q "$pkg" &>/dev/null; then packages_to_install+=("$pkg"); else log_info "$pkg already installed"; fi
  done
  if ! pacman -Q ydotool &>/dev/null; then packages_to_install+=("ydotool"); else log_info "ydotool already installed"; fi

  if [ ${#packages_to_install[@]} -gt 0 ]; then
    log_info "Installing missing packages: ${packages_to_install[*]}"
    sudo pacman -S --needed --noconfirm "${packages_to_install[@]}"
    log_success "System dependencies installed"
  else
    log_success "All system dependencies already installed"
  fi
}

# --- Python venv ---
setup_python_environment() {
  log_info "Setting up Python virtual environment..."
  if [ ! -d "$INSTALL_DIR/venv" ]; then
    log_info "Creating Python virtual environment..."
    python -m venv "$INSTALL_DIR/venv"
    log_success "Python virtual environment created"
  else
    log_info "Python virtual environment already exists"
  fi

  log_info "Activating virtual environment and installing dependencies..."
  # shellcheck disable=SC1091
  source "$INSTALL_DIR/venv/bin/activate"
  pip install --upgrade pip
  pip install -r "$INSTALL_DIR/requirements.txt"
  log_success "Python dependencies installed"
}

# --- whisper.cpp build ---
setup_whisper() {
  log_info "Setting up whisper.cpp..."
  cd "$INSTALL_DIR"

  if [ ! -d "whisper.cpp" ]; then
    log_info "Cloning whisper.cpp repository..."
    git clone https://github.com/ggml-org/whisper.cpp.git
    log_success "whisper.cpp cloned successfully"
  else
    log_info "whisper.cpp directory already exists"
  fi

  cd "whisper.cpp"

  local use_cuda=false
  if command -v nvidia-smi &> /dev/null && command -v nvcc &> /dev/null; then
    log_info "NVIDIA GPU and CUDA toolkit detected - building with GPU acceleration"
    use_cuda=true
  else
    log_info "Building whisper.cpp with CPU-only support"
  fi

  log_info "Building whisper.cpp with CMake..."
  cmake -B build
  if [ "$use_cuda" = true ]; then
    log_info "Configuring with CUDA support..."
    cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
  fi
  cmake --build build -j --config Release

  if [ ! -f "build/bin/whisper-cli" ]; then
    log_error "Failed to build whisper.cpp binary"
    exit 1
  fi

  if [ "$use_cuda" = true ]; then
    if ldd build/bin/whisper-cli | grep -q cuda; then
      log_success "whisper.cpp built successfully with CUDA support"
    else
      log_warning "CUDA requested but not detected in binary - falling back to CPU"
    fi
  else
    log_success "whisper.cpp built successfully (CPU-only)"
  fi
}

# --- Models ---
download_models() {
  log_info "Downloading default Whisper models..."
  cd "$INSTALL_DIR/whisper.cpp"

  if [ ! -f "models/ggml-base.en.bin" ]; then
    log_info "Downloading base.en model..."
    sh ./models/download-ggml-model.sh base.en
    log_success "Base model downloaded"
  else
    log_info "Base model already exists"
  fi

  if [ ! -f "models/ggml-base.en.bin" ] && [ ! -f "models/base.en.bin" ]; then
    log_error "Failed to download model."
    exit 1
  fi

  log_success "Models verified and ready"
}

# --- systemd (user) ---
setup_systemd_service() {
  log_info "Setting up systemd user services..."
  mkdir -p "$HOME/.config/systemd/user"

  cp "$INSTALL_DIR/config/systemd/$SERVICE_NAME" "$HOME/.config/systemd/user/"

  if [ -f "$INSTALL_DIR/config/systemd/ydotoold.service" ]; then
    cp "$INSTALL_DIR/config/systemd/ydotoold.service" "$HOME/.config/systemd/user/"
    log_info "ydotoold.service copied"
  fi

  if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
    log_info "Updating service paths for local installation..."
    sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$HOME/.config/systemd/user/$SERVICE_NAME"
    if [ -f "$HOME/.config/systemd/user/ydotoold.service" ]; then
      sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$HOME/.config/systemd/user/ydotoold.service"
    fi
    log_success "Service paths updated"
  fi

  systemctl --user daemon-reload
  if is_aur; then
    log_info "AUR mode: not enabling services automatically."
    log_info "To enable: systemctl --user enable --now $SERVICE_NAME"
    if [ -f "$HOME/.config/systemd/user/ydotoold.service" ]; then
      log_info "To enable ydotoold: systemctl --user enable --now ydotoold.service"
    fi
  else
    systemctl --user enable "$SERVICE_NAME"
    if [ -f "$HOME/.config/systemd/user/ydotoold.service" ]; then
      systemctl --user enable ydotoold.service
      log_info "ydotoold.service enabled"
    fi
  fi

  log_success "Systemd services configured"
}

# --- Hyprland ---
setup_hyprland_integration() {
  log_info "Setting up Hyprland integration..."
  mkdir -p "$HOME/.config/hypr/scripts"

  cp "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh" "$HOME/.config/hypr/scripts/"
  chmod +x "$HOME/.config/hypr/scripts/hyprwhspr-tray.sh"

  if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
    log_info "Updating tray script paths for local installation..."
    sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
    log_success "Tray script paths updated"
  fi

  log_success "Hyprland integration configured"
}

# --- Waybar (opinionated in Omarchy; opt-in in AUR) ---
setup_waybar_integration() {
  log_info "Setting up Waybar integration..."

  if ! should_edit_waybar; then
    log_info "Skipping automatic Waybar edits (AUR or user opted out)."
    log_info "Manual enable:"
    log_info "  • Module JSON/CSS samples (if shipped by you): /usr/share/waybar/hyprwhspr/"
    log_info "  • Tray script: $INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh"
    log_info "To auto-configure later: HYPRWHSPR_WAYBAR_AUTO=1 hyprwhspr-setup"
    return 0
  fi

  local waybar_config="$HOME/.config/waybar/config.jsonc"
  if [ ! -f "$waybar_config" ]; then
    log_warning "Waybar config not found at $waybar_config"
    log_info "You'll need to add the module manually."
    return 0
  fi

  backup_file "$waybar_config"

  # Ensure module present
  if ! grep -q "custom/hyprwhspr" "$waybar_config"; then
    sed -i '/"modules-right": \[/a\    "custom/hyprwhspr",' "$waybar_config"
  fi

  # Create/update module JSON
  mkdir -p "$HOME/.config/waybar"
  cat > "$HOME/.config/waybar/hyprwhspr-module.jsonc" << EOF
{
  "custom/hyprwhspr": {
    "format": "{}",
    "exec": "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh status",
    "interval": 1,
    "return-type": "json",
    "exec-on-event": true,
    "on-click": "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh toggle",
    "on-click-right": "$INSTALL_DIR/config/hyprwhspr-tray.sh start",
    "on-click-middle": "$INSTALL_DIR/config/hyprwhspr-tray.sh restart",
    "tooltip": true
  }
}
EOF

  # Include module JSON if not already referenced
  if ! grep -q "hyprwhspr-module.jsonc" "$waybar_config"; then
    local line_num end_line
    line_num=$(grep -n '"modules-right"' "$waybar_config" | head -1 | cut -d: -f1 || true)
    if [ -n "$line_num" ]; then
      end_line=$(awk -v start="$line_num" 'NR>=start && /\]/ {print NR; exit}' "$waybar_config")
      if [ -n "$end_line" ]; then
        awk -v end="$end_line" 'NR==end {print; print "  \"include\": [\"hyprwhspr-module.jsonc\"],"; next} {print}' "$waybar_config" > "$waybar_config.tmp" && mv "$waybar_config.tmp" "$waybar_config"
      fi
    fi
  fi

  # CSS import (optional)
  if [ -f "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" ]; then
    cp "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" "$HOME/.config/waybar/" || true
    local waybar_style="$HOME/.config/waybar/style.css"
    if [ -f "$waybar_style" ] && ! grep -q "hyprwhspr-style.css" "$waybar_style"; then
      if grep -q "^@import" "$waybar_style"; then
        awk '/^@import/ { print; last_import = NR } !/^@import/ { if (last_import && NR == last_import + 1) { print "@import \"hyprwhspr-style.css\";"; print ""; } print }' "$waybar_style" > "$waybar_style.tmp" && mv "$waybar_style.tmp" "$waybar_style"
      else
        echo -e "@import \"hyprwhspr-style.css\";\n$(cat "$waybar_style")" > "$waybar_style.tmp" && mv "$waybar_style.tmp" "$waybar_style"
      fi
    fi
  fi

  log_success "Waybar integration updated"
}

# --- User config ---
setup_user_config() {
  log_info "Setting up user configuration..."
  mkdir -p "$USER_CONFIG_DIR"

  local MODEL_PATH=""
  if [ -f "$INSTALL_DIR/whisper.cpp/models/ggml-base.en.bin" ]; then
    MODEL_PATH="$INSTALL_DIR/whisper.cpp/models/ggml-base.en.bin"
  elif [ -f "$INSTALL_DIR/whisper.cpp/models/base.en.bin" ]; then
    MODEL_PATH="$INSTALL_DIR/whisper.cpp/models/base.en.bin"
  else
    log_error "No Whisper model found. Cannot create configuration."
    return 1
  fi

  if [ ! -f "$USER_CONFIG_DIR/config.json" ]; then
    cat > "$USER_CONFIG_DIR/config.json" << 'INNEREOF'
{
  "primary_shortcut": "SUPER+ALT+D",
  "model": "base.en",
  "audio_feedback": true,
  "start_sound_volume": 0.5,
  "stop_sound_volume": 0.5,
  "start_sound_path": "ping-up.ogg",
  "stop_sound_path": "ping-down.ogg",
  "word_overrides": {}
}
INNEREOF
    log_success "Default configuration created"
  else
    log_info "Updating existing configuration with short model name and audio feedback..."
    sed -i 's|"model": "[^"]*"|"model": "base.en"|' "$USER_CONFIG_DIR/config.json"
    if ! grep -q "\"audio_feedback\"" "$USER_CONFIG_DIR/config.json"; then
      sed -i 's|"word_overrides": {}|"audio_feedback": true,\n    "start_sound_volume": 0.5,\n    "stop_sound_volume": 0.5,\n    "start_sound_path": "ping-up.ogg",\n    "stop_sound_path": "ping-down.ogg",\n    "word_overrides": {}|' "$USER_CONFIG_DIR/config.json"
    fi
    log_success "Configuration updated"
  fi
}

# --- Permissions ---
setup_permissions() {
  log_info "Setting up user permissions..."
  usermod -a -G input,audio "$ACTUAL_USER"

  if [ ! -f "/etc/udev/rules.d/99-uinput.rules" ]; then
    log_info "Creating uinput udev rule..."
    sudo tee /etc/udev/rules.d/99-uinput.rules > /dev/null << 'INNEREOF'
# Allow members of the input group to access uinput device
KERNEL=="uinput", GROUP="input", MODE="0660"
INNEREOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=uinput
    log_success "uinput udev rule created and activated"
  else
    log_info "uinput udev rule already exists"
  fi

  if [ ! -e "/dev/uinput" ]; then
    log_info "Loading uinput kernel module..."
    sudo modprobe uinput
    log_success "uinput module loaded"
  fi

  log_warning "You may need to log out and back in for group changes to take effect"
}

# --- NVIDIA ---
setup_nvidia_support() {
  log_info "Checking for NVIDIA GPU support..."
  if command -v nvidia-smi &> /dev/null; then
    log_success "NVIDIA GPU detected!"
    log_info "GPU Info:"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits

    if command -v nvcc &> /dev/null; then
      log_success "CUDA toolkit found - GPU acceleration will be available"
      log_info "You can rebuild with CUDA using:"
      log_info "  $INSTALL_DIR/scripts/build-whisper-nvidia.sh"
    else
      log_warning "CUDA toolkit not found. Installing..."
      sudo pacman -S --needed --noconfirm cuda
      log_success "CUDA toolkit installed"
    fi
  else
    log_info "No NVIDIA GPU detected - CPU-only mode will be used"
  fi
}

# --- Audio ---
setup_audio_devices() {
  log_info "Setting up audio device configuration..."
  if systemctl --user is-active --quiet pipewire; then
    log_success "PipeWire is running"
  else
    log_warning "PipeWire not running. Starting..."
    systemctl --user start pipewire
    systemctl --user start pipewire-pulse
    log_success "PipeWire started"
  fi

  log_info "Available audio input devices:"
  pactl list short sources | grep input || log_warning "No audio input devices found"
  log_success "Audio setup completed"
}

# --- Validate ---
validate_installation() {
  log_info "Validating installation..."

  if [ ! -f "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" ]; then
    log_error "whisper.cpp binary not found. Installation incomplete."
    return 1
  fi

  if ldd "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" | grep -q cuda; then
    log_success "whisper.cpp built with CUDA support"
  else
    log_info "whisper.cpp built without CUDA"
  fi

  if [ ! -f "$INSTALL_DIR/whisper.cpp/models/ggml-base.en.bin" ] && [ ! -f "$INSTALL_DIR/whisper.cpp/models/base.en.bin" ]; then
    log_error "Whisper model not found. Installation incomplete."
    return 1
  fi

  if [ ! -f "$INSTALL_DIR/venv/bin/python" ]; then
    log_error "Python virtual environment not found. Installation incomplete."
    return 1
  fi

  if [ ! -f "$INSTALL_DIR/lib/main.py" ]; then
    log_error "Main application not found. Installation incomplete."
    return 1
  fi

  log_success "Installation validation passed"
}

# --- Test ---
test_installation() {
  log_info "Testing installation..."
  if ! validate_installation; then
    log_error "Validation failed. Cannot proceed with testing."
    return 1
  fi

  if systemctl --user start "$SERVICE_NAME"; then
    log_success "Service started successfully"
    systemctl --user stop "$SERVICE_NAME"
  else
    log_error "Failed to start service"; return 1
  fi

  if "$HOME/.config/hypr/scripts/hyprwhspr-tray.sh" status > /dev/null 2>&1; then
    log_success "Tray script working"
  else
    log_error "Tray script not working"; return 1
  fi

  log_success "Installation test passed"
}

# --- Verify perms & core ---
verify_permissions_and_functionality() {
  log_info "Verifying permissions and core functionality..."
  local all_tests_passed=true

  log_info "Testing uinput device access..."
  if [ -e "/dev/uinput" ]; then
    if [ -r "/dev/uinput" ] && [ -w "/dev/uinput" ]; then
      log_success "✓ uinput device accessible (read/write)"
    else
      log_error "✗ uinput exists but not accessible"; all_tests_passed=false
    fi
  else
    log_error "✗ /dev/uinput not found"; all_tests_passed=false
  fi

  log_info "Testing user group membership..."
  if groups "$ACTUAL_USER" | grep -q "\binput\b"; then
    log_success "✓ User in 'input' group"
  else
    log_error "✗ User NOT in 'input' group"; all_tests_passed=false
  fi
  if groups "$USER" | grep -q "\baudio\b"; then
    log_success "✓ User in 'audio' group"
  else
    log_error "✗ User NOT in 'audio' group"; all_tests_passed=false
  fi

  log_info "Testing ydotool..."
  if command -v ydotool &> /dev/null; then
    if timeout 5s ydotool help > /dev/null 2>&1; then
      log_success "✓ ydotool responds"
    else
      log_error "✗ ydotool installed but not responding"; all_tests_passed=false
    fi
  else
    log_error "✗ ydotool not installed"; all_tests_passed=false
  fi

  log_info "Testing audio devices..."
  if command -v pactl &> /dev/null; then
    if pactl list short sources | grep -q input; then
      log_success "✓ Audio input devices detected"
    else
      log_warning "⚠ No audio input devices found"
    fi
  else
    log_warning "⚠ pactl not available - cannot verify audio devices"
  fi

  log_info "Testing whisper.cpp binary..."
  if [ -f "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" ]; then
    if timeout 10s "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" --help > /dev/null 2>&1; then
      log_success "✓ whisper.cpp binary functional"
    else
      log_error "✗ whisper.cpp binary not responding"; all_tests_passed=false
    fi
  else
    log_error "✗ whisper.cpp binary not found"; all_tests_passed=false
  fi

  log_info "Testing Python environment..."
  if [ -f "$INSTALL_DIR/venv/bin/python" ]; then
    if timeout 5s "$INSTALL_DIR/venv/bin/python" -c "import sounddevice; print('Audio libraries OK')" > /dev/null 2>&1; then
      log_success "✓ Python environment with audio libs"
    else
      log_error "✗ Python environment missing audio libraries"; all_tests_passed=false
    fi
  else
    log_error "✗ Python virtual environment not found"; all_tests_passed=false
  fi

  log_info "Testing user services capability..."
  if systemctl --user is-enabled --quiet user.slice; then
    log_success "✓ User systemd services enabled"
  else
    log_warning "⚠ User systemd services may not be enabled"
  fi

  if [ "$all_tests_passed" = true ]; then
    log_success "All permission and functionality tests passed!"
    return 0
  else
    log_error "Some permission and functionality tests failed!"
    log_warning "HyprWhspr may not work correctly. Please check the errors above."
    return 1
  fi
}

# --- Main ---
main() {
  log_info "Installing HyprWhspr to $INSTALL_DIR"

  if [ -d "$INSTALL_DIR" ]; then
    log_warning "HyprWhspr appears to be already installed at $INSTALL_DIR"
    if is_aur; then
      log_info "AUR mode: continuing with setup..."
    else
      read -p "Do you want to continue with installation? (y/N): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"; exit 0
      fi
    fi
  fi

  # Create/copy payload: skip in AUR mode (package already installed files)
  if ! is_aur; then
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$USER" "$INSTALL_DIR"
    log_info "Copying application files..."
    sudo cp -r . "$INSTALL_DIR/"
    sudo chown -R "$USER:$USER" "$INSTALL_DIR"
  else
    log_info "AUR mode: files already present in $INSTALL_DIR; skipping copy."
  fi

  install_system_dependencies
  setup_python_environment
  setup_whisper
  download_models
  setup_systemd_service
  setup_hyprland_integration
  setup_user_config
  setup_permissions
  setup_nvidia_support
  setup_audio_devices
  validate_installation
  verify_permissions_and_functionality
  test_installation
  setup_waybar_integration

  log_success "HyprWhspr installation completed successfully!"

  if ldd "$INSTALL_DIR/whisper.cpp/build/bin/whisper-cli" | grep -q cuda; then
    log_success "✅ GPU acceleration is ENABLED - NVIDIA CUDA support active"
  else
    log_info "ℹ️  GPU acceleration is DISABLED - CPU-only mode"
    if command -v nvidia-smi &> /dev/null; then
      log_info "💡 NVIDIA GPU detected - you can rebuild with GPU support using:"
      log_info "   $INSTALL_DIR/scripts/build-whisper-nvidia.sh"
    fi
  fi

  log_info ""
  log_info "Next steps:"
  log_info "1. Log out and back in (or reboot) for group changes to take effect"
  log_info "2. Use Super+Alt+D to start dictation"
  log_info "3. Check system tray for status"
  log_info ""
  log_info "Troubleshooting:"
  log_info "• If you encounter permission issues, run: $INSTALL_DIR/scripts/fix-uinput-permissions.sh"
  log_info "• If GPU acceleration isn't working, run: $INSTALL_DIR/scripts/build-whisper-nvidia.sh"
  log_info "• Check logs: journalctl --user -u hyprwhspr.service"
  log_info "• Try restarting the service: systemctl --user restart hyprwhspr.service"
}

main "$@"
