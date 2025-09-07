#!/bin/bash
# hyprwhspr Omarchy/Arch Installation Script
# Works in two modes:
#   • Omarchy/local: INSTALL_DIR=/opt/hyprwhspr, venv & whisper.cpp under /opt (your original behavior)
#   • AUR: INSTALL_DIR=/usr/lib/hyprwhspr (read-only). venv & whisper.cpp live in user-space:
#       VENV_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv"
#       USER_WC_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/whisper.cpp"
#   Mode is detected by HYPRWHSPR_AUR_INSTALL=1 (set by /usr/bin/hyprwhspr-setup)

set -euo pipefail

# ----------------------- Colors & logging -----------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ----------------------- Configuration -------------------------
PACKAGE_NAME="hyprwhspr"
INSTALL_DIR="/opt/hyprwhspr"   # default for Omarchy/local
SERVICE_NAME="hyprwhspr.service"

is_aur() { [[ "${HYPRWHSPR_AUR_INSTALL:-}" == "1" ]]; }
if is_aur; then
  INSTALL_DIR="/usr/lib/hyprwhspr"
fi

USER_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr"
VENV_DIR="$USER_BASE/venv"
USER_WC_DIR="$USER_BASE/whisper.cpp"
USER_MODELS_DIR="$USER_WC_DIR/models"
USER_BIN_DIR="$HOME/.local/bin"

# In local/Omarchy mode, keep legacy layout
if ! is_aur; then
  VENV_DIR="$INSTALL_DIR/venv"
  USER_WC_DIR="$INSTALL_DIR/whisper.cpp"
  USER_MODELS_DIR="$INSTALL_DIR/whisper.cpp/models"
fi

# ----------------------- Detect actual user --------------------
if [ "$EUID" -eq 0 ]; then
  if [ -n "${SUDO_USER:-}" ]; then ACTUAL_USER="$SUDO_USER"
  else ACTUAL_USER=$(stat -c '%U' /home 2>/dev/null | head -1 || echo "root")
  fi
else
  ACTUAL_USER="$USER"
fi
USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
USER_CONFIG_DIR="$USER_HOME/.config/hyprwhspr"

# ----------------------- Preconditions -------------------------
command -v pacman >/dev/null 2>&1 || { log_error "Arch Linux required."; exit 1; }
log_info "Setting up hyprwhspr for user: $ACTUAL_USER"
log_info "Mode: $(is_aur && echo AUR || echo Omarchy/local)"
log_info "INSTALL_DIR=$INSTALL_DIR"
log_info "VENV_DIR=$VENV_DIR"
log_info "USER_WC_DIR=$USER_WC_DIR"

# ----------------------- Helpers -------------------------------
have_system_whisper() { command -v whisper-cli >/dev/null 2>&1; }

ensure_path_contains_local_bin() {
  # Add ~/.local/bin to PATH for current shell session
  case ":$PATH:" in
    *":$USER_BIN_DIR:"*) : ;;
    *) export PATH="$USER_BIN_DIR:$PATH" ;;
  esac
}

# ----------------------- Install dependencies ------------------
install_system_dependencies() {
  log_info "Ensuring system dependencies..."
  local pkgs=(cmake make git base-devel python pipewire pipewire-alsa pipewire-pulse pipewire-jack ydotool curl)
  local to_install=()
  for p in "${pkgs[@]}"; do pacman -Q "$p" &>/dev/null || to_install+=("$p"); done
  if ((${#to_install[@]})); then
    log_info "Installing: ${to_install[*]}"
    sudo pacman -S --needed --noconfirm "${to_install[@]}"
  fi
  log_info "python-pip not required (venv pip used)"
  log_success "Dependencies ready"
}

# ----------------------- Python environment --------------------
setup_python_environment() {
  log_info "Setting up Python virtual environment…"
  if [ ! -d "$VENV_DIR" ]; then
    log_info "Creating venv at $VENV_DIR"
    mkdir -p "$(dirname "$VENV_DIR")"
    python -m venv "$VENV_DIR"
  else
    log_info "Venv already exists at $VENV_DIR"
  fi
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip wheel
  pip install -r "$INSTALL_DIR/requirements.txt"
  log_success "Python dependencies installed"
}

# ----------------------- whisper.cpp build ---------------------
ensure_user_bin_symlink() {
  mkdir -p "$USER_BIN_DIR"
  if [ -x "$USER_WC_DIR/build/bin/whisper-cli" ] && [ ! -e "$USER_BIN_DIR/whisper-cli" ]; then
    ln -s "$USER_WC_DIR/build/bin/whisper-cli" "$USER_BIN_DIR/whisper-cli" || true
    log_info "Linked whisper-cli → $USER_BIN_DIR/whisper-cli"
  fi
}

setup_whisper() {
  log_info "Setting up whisper.cpp…"
  ensure_path_contains_local_bin

  if is_aur; then
    if have_system_whisper; then
      log_success "Using system whisper-cli: $(command -v whisper-cli)"
      return 0
    fi
    mkdir -p "$USER_WC_DIR"
    cd "$USER_WC_DIR"
  else
    mkdir -p "$USER_WC_DIR"
    cd "$USER_WC_DIR"
  fi

  if [ ! -d ".git" ]; then
    log_info "Cloning whisper.cpp → $PWD"
    git clone https://github.com/ggml-org/whisper.cpp.git .
  else
    log_info "Updating whisper.cpp"
    git pull --ff-only || true
  fi

  local use_cuda=false
  if command -v nvidia-smi &>/dev/null && command -v nvcc &>/dev/null; then
    use_cuda=true; log_info "CUDA detected: enabling GPU build"
  else
    log_info "Building CPU-only"
  fi

  cmake -B build
  $use_cuda && cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j --config Release

  [ -x "build/bin/whisper-cli" ] || { log_error "whisper-cli build failed"; exit 1; }
  $use_cuda && ldd build/bin/whisper-cli | grep -qi cuda && log_success "Built with CUDA"

  ensure_user_bin_symlink
  log_success "whisper.cpp ready"
}

# ----------------------- Models --------------------------------
download_models() {
  log_info "Downloading Whisper base model…"
  mkdir -p "$USER_MODELS_DIR"
  if [ -f "$USER_MODELS_DIR/ggml-base.en.bin" ] || [ -f "$USER_MODELS_DIR/base.en.bin" ]; then
    log_info "Model already present"
    return 0
  fi
  local url="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
  curl -L --fail -o "$USER_MODELS_DIR/ggml-base.en.bin" "$url"
  log_success "Model downloaded"
}

# ----------------------- Systemd (user) ------------------------
setup_systemd_service() {
  log_info "Configuring systemd user services…"
  mkdir -p "$USER_HOME/.config/systemd/user"

  # Copy your opinionated units if bundled
  if [ -f "$INSTALL_DIR/config/systemd/$SERVICE_NAME" ]; then
    cp "$INSTALL_DIR/config/systemd/$SERVICE_NAME" "$USER_HOME/.config/systemd/user/" || true
  fi
  if [ -f "$INSTALL_DIR/config/systemd/ydotoold.service" ]; then
    cp "$INSTALL_DIR/config/systemd/ydotoold.service" "$USER_HOME/.config/systemd/user/" || true
  fi

  # Replace /opt paths if running from AUR payload
  if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
    sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$USER_HOME/.config/systemd/user/$SERVICE_NAME" 2>/dev/null || true
    sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$USER_HOME/.config/systemd/user/ydotoold.service" 2>/dev/null || true
  fi

  systemctl --user daemon-reload

  if is_aur; then
    log_info "AUR mode: not auto-enabling. Use:"
    log_info "  systemctl --user enable --now ydotoold.service"
    log_info "  systemctl --user enable --now hyprwhspr.service"
  else
    systemctl --user enable "$SERVICE_NAME" || true
    [ -f "$USER_HOME/.config/systemd/user/ydotoold.service" ] && systemctl --user enable ydotoold.service || true
  fi

  log_success "Systemd user services ready"
}

# ----------------------- Hyprland integration ------------------
setup_hyprland_integration() {
  log_info "Setting up Hyprland integration…"
  mkdir -p "$USER_HOME/.config/hypr/scripts"
  if [ -f "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh" ]; then
    cp "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh" "$USER_HOME/.config/hypr/scripts/"
    chmod +x "$USER_HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
    [ "$INSTALL_DIR" != "/opt/hyprwhspr" ] && sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$USER_HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
  fi
  log_success "Hyprland integration configured"
}

# ----------------------- Waybar integration --------------------
setup_waybar_integration() {
  log_info "Waybar integration…"
  # In AUR mode, do not auto-edit unless explicitly asked
  if is_aur && [[ "${HYPRWHSPR_WAYBAR_AUTO:-}" != "1" ]]; then
    log_info "AUR mode: skipping auto Waybar edits (opt-in: HYPRWHSPR_WAYBAR_AUTO=1 hyprwhspr-setup)"
    return 0
  fi

  local waybar_config="$USER_HOME/.config/waybar/config.jsonc"
  [ -f "$waybar_config" ] || { log_warning "Waybar config not found ($waybar_config)"; return 0; }

  mkdir -p "$USER_HOME/.config/waybar"
  cat > "$USER_HOME/.config/waybar/hyprwhspr-module.jsonc" << EOF
{
  "custom/hyprwhspr": {
    "format": "{}",
    "exec": "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh status",
    "interval": 1,
    "return-type": "json",
    "exec-on-event": true,
    "on-click": "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh toggle",
    "on-click-right": "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh start",
    "on-click-middle": "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh restart",
    "tooltip": true
  }
}
EOF

  if ! grep -q "hyprwhspr-module.jsonc" "$waybar_config"; then
    local line_num end_line
    line_num=$(grep -n '"modules-right"' "$waybar_config" | head -1 | cut -d: -f1 || true)
    if [ -n "$line_num" ]; then
      end_line=$(awk -v start="$line_num" 'NR>=start && /\]/ {print NR; exit}' "$waybar_config")
      [ -n "$end_line" ] && awk -v end="$end_line" 'NR==end {print; print "  \"include\": [\"hyprwhspr-module.jsonc\"],"; next} {print}' "$waybar_config" > "$waybar_config.tmp" && mv "$waybar_config.tmp" "$waybar_config"
    fi
  fi

  if [ -f "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" ]; then
    cp "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" "$USER_HOME/.config/waybar/" || true
    local waybar_style="$USER_HOME/.config/waybar/style.css"
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

# ----------------------- User config ---------------------------
setup_user_config() {
  log_info "User config…"
  mkdir -p "$USER_CONFIG_DIR"
  if [ ! -f "$USER_CONFIG_DIR/config.json" ]; then
    cat > "$USER_CONFIG_DIR/config.json" << 'CFG'
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
CFG
    log_success "Created $USER_CONFIG_DIR/config.json"
  else
    sed -i 's|"model": "[^"]*"|"model": "base.en"|' "$USER_CONFIG_DIR/config.json"
    if ! grep -q "\"audio_feedback\"" "$USER_CONFIG_DIR/config.json"; then
      sed -i 's|"word_overrides": {}|"audio_feedback": true,\n    "start_sound_volume": 0.5,\n    "stop_sound_volume": 0.5,\n    "start_sound_path": "ping-up.ogg",\n    "stop_sound_path": "ping-down.ogg",\n    "word_overrides": {}|' "$USER_CONFIG_DIR/config.json"
    fi
    log_success "Updated existing config"
  fi
}

# ----------------------- Permissions & uinput ------------------
setup_permissions() {
  log_info "Permissions & uinput…"
  sudo usermod -a -G input,audio "$ACTUAL_USER" || true

  if [ ! -f "/etc/udev/rules.d/99-uinput.rules" ]; then
    log_info "Creating /etc/udev/rules.d/99-uinput.rules"
    sudo tee /etc/udev/rules.d/99-uinput.rules > /dev/null << 'RULE'
KERNEL=="uinput", GROUP="input", MODE="0660"
RULE
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=uinput
  else
    log_info "udev rule for uinput already present"
  fi

  [ -e "/dev/uinput" ] || { log_info "Loading uinput module"; sudo modprobe uinput || true; }
  log_warning "You may need to log out/in for new group memberships to apply"
}

# ----------------------- NVIDIA support -----------------------
setup_nvidia_support() {
  log_info "GPU check…"
  if command -v nvidia-smi &>/dev/null; then
    log_success "NVIDIA GPU detected"
    if command -v nvcc &>/dev/null; then
      log_success "CUDA toolkit present"
    else
      log_warning "CUDA toolkit not found; installing…"
      sudo pacman -S --needed --noconfirm cuda
    fi
  else
    log_info "No NVIDIA GPU (CPU mode)"
  fi
}

# ----------------------- Audio devices ------------------------
setup_audio_devices() {
  log_info "Audio devices…"
  systemctl --user is-active --quiet pipewire || { systemctl --user start pipewire; systemctl --user start pipewire-pulse; }
  log_info "Available audio input devices:"
  pactl list short sources | grep input || log_warning "No audio input devices found"
}

# ----------------------- Validation ---------------------------
validate_installation() {
  log_info "Validating installation…"

  if have_system_whisper; then
    log_success "whisper-cli on PATH: $(command -v whisper-cli)"
  elif [ -x "$USER_WC_DIR/build/bin/whisper-cli" ]; then
    log_success "whisper-cli present at $USER_WC_DIR/build/bin/whisper-cli"
  else
    log_error "whisper-cli missing"
    return 1
  fi

  if [ ! -f "$USER_MODELS_DIR/ggml-base.en.bin" ] && [ ! -f "$USER_MODELS_DIR/base.en.bin" ]; then
    log_error "Model missing (${USER_MODELS_DIR})"
    return 1
  fi

  [ -x "$VENV_DIR/bin/python" ] || { log_error "Venv missing ($VENV_DIR)"; return 1; }
  [ -f "$INSTALL_DIR/lib/main.py" ] || { log_error "App missing ($INSTALL_DIR/lib/main.py)"; return 1; }

  log_success "Validation passed"
}

# ----------------------- Functional checks --------------------
verify_permissions_and_functionality() {
  log_info "Verifying permissions & functionality…"
  local ok=true

  if [ -e "/dev/uinput" ] && [ -r "/dev/uinput" ] && [ -w "/dev/uinput" ]; then
    log_success "✓ /dev/uinput accessible"
  else
    log_error "✗ /dev/uinput not accessible"; ok=false
  fi

  groups "$ACTUAL_USER" | grep -q "\binput\b"  && log_success "✓ user in 'input'"  || { log_error "✗ user NOT in 'input'"; ok=false; }
  groups "$ACTUAL_USER" | grep -q "\baudio\b"  && log_success "✓ user in 'audio'"  || { log_error "✗ user NOT in 'audio'"; ok=false; }

  command -v ydotool >/dev/null && timeout 5s ydotool help >/dev/null 2>&1 \
    && log_success "✓ ydotool responds" || { log_error "✗ ydotool problem"; ok=false; }

  command -v pactl >/dev/null && pactl list short sources | grep -q input \
    && log_success "✓ audio inputs present" || log_warning "⚠ no audio inputs detected"

  if have_system_whisper || [ -x "$USER_WC_DIR/build/bin/whisper-cli" ]; then
    timeout 10s whisper-cli --help >/dev/null 2>&1 \
      && log_success "✓ whisper-cli responds" || { log_error "✗ whisper-cli not responding"; ok=false; }
  fi

  if [ -x "$VENV_DIR/bin/python" ]; then
    timeout 5s "$VENV_DIR/bin/python" -c "import sounddevice" >/dev/null 2>&1 \
      && log_success "✓ Python audio libs present" || { log_error "✗ Python audio libs missing"; ok=false; }
  fi

  $ok && return 0 || return 1
}

# ----------------------- Smoke test ---------------------------
test_installation() {
  log_info "Testing service start…"
  validate_installation || { log_error "Validation failed"; return 1; }

  if systemctl --user start "$SERVICE_NAME"; then
    log_success "Service started"
    systemctl --user stop "$SERVICE_NAME"
  else
    log_error "Failed to start service"
    return 1
  fi

  if "$USER_HOME/.config/hypr/scripts/hyprwhspr-tray.sh" status >/dev/null 2>&1; then
    log_success "Tray script working"
  else
    log_warning "Tray script not found or not executable (ok if Hyprland not configured)"
  fi

  log_success "Installation test passed"
}

# ----------------------- Main ---------------------------------
main() {
  log_info "Installing to $INSTALL_DIR"

  if ! is_aur; then
    sudo mkdir -p "$INSTALL_DIR"; sudo chown "$ACTUAL_USER:$ACTUAL_USER" "$INSTALL_DIR"
    log_info "Copying application files…"
    sudo cp -r . "$INSTALL_DIR/"; sudo chown -R "$ACTUAL_USER:$ACTUAL_USER" "$INSTALL_DIR"
  else
    log_info "AUR mode: payload already at $INSTALL_DIR"
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

  log_success "hyprwhspr installation completed!"
  log_info "Enable services:"
  log_info "  systemctl --user enable --now ydotoold.service hyprwhspr.service"
  log_info "Logs:"
  log_info "  journalctl --user -u hyprwhspr.service"
}

main "$@"
