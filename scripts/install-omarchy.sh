#!/bin/bash
# hyprwhspr Omarchy/Arch Installation Script
# Modes:
#   • Omarchy/local: INSTALL_DIR=/opt/hyprwhspr, venv & whisper.cpp under /opt
#   • AUR:           INSTALL_DIR=/usr/lib/hyprwhspr (read-only)
#       VENV_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv"
#       USER_WC_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/whisper.cpp"
#   AUR mode is detected by HYPRWHSPR_AUR_INSTALL=1 (set by /usr/bin/hyprwhspr-setup)

set -euo pipefail

# ----------------------- Colors & logging -----------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Legacy shorthands used in a few places
ok()   { log_success "$@"; }
warn() { log_warning "$@"; }
err()  { log_error "$@"; }

# ----------------------- Configuration -------------------------
PACKAGE_NAME="hyprwhspr"
INSTALL_DIR="/opt/hyprwhspr"   # default for Omarchy/local
SERVICE_NAME="hyprwhspr.service"
YDOTOOL_UNIT="ydotoold.service"

is_aur() { [[ "${HYPRWHSPR_AUR_INSTALL:-}" == "1" ]]; }
if is_aur; then
  INSTALL_DIR="/usr/lib/hyprwhspr"
fi

USER_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr"
VENV_DIR="$USER_BASE/venv"
USER_WC_DIR="$USER_BASE/whisper.cpp"
USER_MODELS_DIR="$USER_WC_DIR/models"
USER_BIN_DIR="$HOME/.local/bin"
LAUNCHER="$USER_BASE/run.sh"               # venv-aware launcher used by systemd unit

# In Omarchy mode, legacy layout under /opt
if ! is_aur; then
  VENV_DIR="$INSTALL_DIR/venv"
  USER_WC_DIR="$INSTALL_DIR/whisper.cpp"
  USER_MODELS_DIR="$INSTALL_DIR/whisper.cpp/models"
  LAUNCHER="$INSTALL_DIR/run.sh"
fi

# ----------------------- Detect actual user --------------------
if [ "$EUID" -eq 0 ]; then
  if [ -n "${SUDO_USER:-}" ]; then
    ACTUAL_USER="$SUDO_USER"
  else
    ACTUAL_USER=$(stat -c '%U' /home 2>/dev/null | head -1 || echo "root")
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
  case ":$PATH:" in *":$USER_BIN_DIR:"*) ;; *) export PATH="$USER_BIN_DIR:$PATH" ;; esac
}

detect_cuda_host_compiler() {
  # Allow explicit override
  if [[ -n "${HYPRWHSPR_CUDA_HOST:-}" && -x "$HYPRWHSPR_CUDA_HOST" ]]; then
    echo "$HYPRWHSPR_CUDA_HOST"; return 0
  fi
  local gcc_major
  gcc_major=$(gcc -dumpfullversion 2>/dev/null | cut -d. -f1 || echo 0)
  # If GCC >= 15, prefer gcc14 if present (nvcc header compat)
  if [[ "$gcc_major" -ge 15 ]] && command -v g++-14 >/dev/null 2>&1; then
    echo "/usr/bin/g++-14"; return 0
  fi
  if command -v g++ >/dev/null 2>&1; then
    command -v g++; return 0
  fi
  echo ""
}

ensure_user_bin_symlink() {
  mkdir -p "$USER_BIN_DIR"
  if [ -x "$USER_WC_DIR/build/bin/whisper-cli" ] && [ ! -e "$USER_BIN_DIR/whisper-cli" ]; then
    ln -s "$USER_WC_DIR/build/bin/whisper-cli" "$USER_BIN_DIR/whisper-cli" || true
    log_info "Linked whisper-cli → $USER_BIN_DIR/whisper-cli"
  fi
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

# ----------------------- NVIDIA support -----------------------
setup_nvidia_support() {
  log_info "GPU check…"
  if command -v nvidia-smi >/dev/null 2>&1; then
    log_success "NVIDIA GPU detected"
    # nvcc path (prefer canonical CUDA location)
    if [ -x /opt/cuda/bin/nvcc ] || command -v nvcc >/dev/null 2>&1; then
      export PATH="/opt/cuda/bin:$PATH"
      export CUDACXX="${CUDACXX:-/opt/cuda/bin/nvcc}"
      log_success "CUDA toolkit present"
    else
      log_warning "CUDA toolkit not found; installing…"
      sudo pacman -S --needed --noconfirm cuda || true
      if [ -x /opt/cuda/bin/nvcc ]; then
        export PATH="/opt/cuda/bin:$PATH"
        export CUDACXX="/opt/cuda/bin/nvcc"
        log_success "CUDA installed"
      else
        log_warning "nvcc still not visible; will build CPU-only"
        return 0
      fi
    fi

    # Choose a host compiler for NVCC
    local hostc
    hostc="$(detect_cuda_host_compiler)"
    if [[ -n "$hostc" ]]; then
      export CUDAHOSTCXX="$hostc"
      log_info "CUDA host compiler: $CUDAHOSTCXX"
      if [[ "$hostc" == "/usr/bin/g++" ]]; then
        local gcc_major
        gcc_major=$(gcc -dumpfullversion 2>/dev/null | cut -d. -f1 || echo 0)
        if [[ "$gcc_major" -ge 15 ]]; then
          log_warning "GCC $gcc_major with NVCC can fail; consider:"
          log_warning "  yay -S gcc14 gcc14-libs"
          log_warning "  HYPRWHSPR_CUDA_HOST=/usr/bin/g++-14 hyprwhspr-setup"
        fi
      fi
    else
      log_warning "No suitable host compiler found; will build CPU-only"
    fi
  else
    log_info "No NVIDIA GPU detected (CPU mode)"
  fi
}

# ----------------------- whisper.cpp build ---------------------
setup_whisper() {
  log_info "Setting up whisper.cpp…"

  # ---------- choose build location ----------
  if is_aur; then
    mkdir -p "$USER_WC_DIR"
    cd "$USER_WC_DIR"
  else
    mkdir -p "$INSTALL_DIR/whisper.cpp"
    cd "$INSTALL_DIR/whisper.cpp"
  fi

  # ---------- clone or update ----------
  if [ ! -d ".git" ]; then
    log_info "Cloning whisper.cpp → $PWD"
    git clone https://github.com/ggml-org/whisper.cpp.git .
  else
    git pull --ff-only || true
  fi

  # ---------- CUDA availability ----------
  if [ -z "${CUDACXX:-}" ] && [ -x /opt/cuda/bin/nvcc ]; then
    export CUDACXX="/opt/cuda/bin/nvcc"
    export PATH="/opt/cuda/bin:$PATH"
  fi

  local use_cuda=false
  if [[ -n "${CUDACXX:-}" && -x "${CUDACXX}" ]]; then
    if [ -z "${CUDAHOSTCXX:-}" ]; then
      CUDAHOSTCXX="$(detect_cuda_host_compiler)"; export CUDAHOSTCXX
    fi
    if [[ -n "${CUDAHOSTCXX:-}" && -x "${CUDAHOSTCXX}" ]]; then
      use_cuda=true
      log_info "CUDA detected: building with GPU support (host: $CUDAHOSTCXX)"
    else
      log_warning "CUDA present but no suitable host compiler; building CPU-only"
    fi
  else
    log_info "Building CPU-only"
  fi

  # ---------- configure & build ----------
  local build_success=false
  local cuda_build_failed=false
  
  if [[ "$use_cuda" == true ]]; then
    log_info "Attempting CUDA build..."
    if timeout 300 cmake -B build \
      -DGGML_CUDA=ON \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_HOST_COMPILER="${CUDAHOSTCXX}" 2>/dev/null; then
      
      log_info "CUDA configuration successful, building..."
      if timeout 800 cmake --build build -j --config Release 2>/dev/null; then
        # Verify CUDA binary was built correctly
        if [ -x "build/bin/whisper-cli" ] && ldd build/bin/whisper-cli | grep -qi cuda; then
          log_success "CUDA build completed successfully"
          build_success=true
        else
          log_warning "CUDA build completed but binary not CUDA-linked"
          cuda_build_failed=true
        fi
      else
        log_warning "CUDA build timed out or failed"
        cuda_build_failed=true
      fi
    else
      log_warning "CUDA configuration failed"
      cuda_build_failed=true
    fi
  fi
  
  # Fallback to CPU-only build if CUDA failed or wasn't requested
  if [[ "$build_success" != true ]]; then
    if [[ "$cuda_build_failed" == true ]]; then
      log_info "Falling back to CPU-only build due to CUDA issues..."
      log_info "This is common with older NVIDIA cards (RTX 20xx series) and newer CUDA toolchains"
    else
      log_info "Building CPU-only (no CUDA requested)"
    fi
    
    rm -rf build
    cmake -B build \
      -DGGML_CUDA=OFF \
      -DCMAKE_BUILD_TYPE=Release
    
    if cmake --build build -j --config Release; then
      log_success "CPU-only build completed successfully"
      build_success=true
    else
      log_error "CPU-only build failed"
      build_success=false
    fi
  fi

  # ---------- verify binary ----------
  if [[ "$build_success" != true ]] || [ ! -x "build/bin/whisper-cli" ]; then
    err "whisper.cpp build failed"
    exit 1
  fi

  # ---------- link into ~/.local/bin for PATH ----------
  ensure_path_contains_local_bin
  ensure_user_bin_symlink

  ok "whisper.cpp ready"
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

  # Create a venv-aware launcher the unit will ExecStart
  mkdir -p "$(dirname "$LAUNCHER")"
  cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
set -e
VENV="$VENV_DIR"
APP_DIR="$INSTALL_DIR"
# shellcheck disable=SC1091
source "\$VENV/bin/activate"
exec "\$APP_DIR/bin/hyprwhspr" "\$@"
EOF
  chmod +x "$LAUNCHER"

  mkdir -p "$USER_HOME/.config/systemd/user"

  # Copy packaged (opinionated) units
  if [ -f "$INSTALL_DIR/config/systemd/$SERVICE_NAME" ]; then
    cp "$INSTALL_DIR/config/systemd/$SERVICE_NAME" "$USER_HOME/.config/systemd/user/" || true
  fi
  if [ -f "$INSTALL_DIR/config/systemd/$YDOTOOL_UNIT" ]; then
    cp "$INSTALL_DIR/config/systemd/$YDOTOOL_UNIT" "$USER_HOME/.config/systemd/user/" || true
  fi

  # Always ensure the user unit ExecStart points at our launcher (AUR & Omarchy)
  # and rewrite /opt path if coming from AUR payload.
  if [ -f "$USER_HOME/.config/systemd/user/$SERVICE_NAME" ]; then
    # Replace any ExecStart line with our launcher
    sed -i 's|^ExecStart=.*|ExecStart='"$LAUNCHER"'|g' "$USER_HOME/.config/systemd/user/$SERVICE_NAME"
    # Normalize WorkingDirectory
    if grep -q '^WorkingDirectory=' "$USER_HOME/.config/systemd/user/$SERVICE_NAME"; then
      sed -i 's|^WorkingDirectory=.*|WorkingDirectory='"$INSTALL_DIR"'|g' "$USER_HOME/.config/systemd/user/$SERVICE_NAME"
    else
      sed -i '/^\[Service\]/a WorkingDirectory='"$INSTALL_DIR" "$USER_HOME/.config/systemd/user/$SERVICE_NAME"
    fi
    # Standardize logs to journal
    sed -i '/^\[Service\]/,$!b;/^\[Service\]/,/\[/{/StandardOutput=/d;/StandardError=/d}' "$USER_HOME/.config/systemd/user/$SERVICE_NAME"
    sed -i '/^\[Service\]/a StandardOutput=journal\nStandardError=journal' "$USER_HOME/.config/systemd/user/$SERVICE_NAME"
  fi

  # Rewrite any remaining hardcoded /opt paths (e.g., in ydotoold unit)
  if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
    sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$USER_HOME/.config/systemd/user/$SERVICE_NAME" 2>/dev/null || true
    sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$USER_HOME/.config/systemd/user/$YDOTOOL_UNIT" 2>/dev/null || true
  fi

  systemctl --user daemon-reload
  # As requested: same behavior as before → enable & start automatically in all modes
  systemctl --user enable --now "$YDOTOOL_UNIT" 2>/dev/null || true
  systemctl --user enable --now "$SERVICE_NAME"

  log_success "Systemd user services enabled and started"
}

# ----------------------- Hyprland integration ------------------
setup_hyprland_integration() {
  log_info "Setting up Hyprland integration…"
  mkdir -p "$USER_HOME/.config/hypr/scripts"
  if [ -f "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh" ]; then
    cp "$INSTALL_DIR/config/hyprland/hyprwhspr-tray.sh" "$USER_HOME/.config/hypr/scripts/"
    chmod +x "$USER_HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
    if [ "$INSTALL_DIR" != "/opt/hyprwhspr" ]; then
      sed -i "s|/opt/hyprwhspr|$INSTALL_DIR|g" "$USER_HOME/.config/hypr/scripts/hyprwhspr-tray.sh"
    fi
  fi
  log_success "Hyprland integration configured"
}

# ----------------------- Waybar integration --------------------
setup_waybar_integration() {
  log_info "Waybar integration…"
  
  # Check if waybar is installed (should be required dependency now)
  if ! command -v waybar >/dev/null 2>&1; then
    log_error "Waybar not found - this should be installed as a dependency"
    log_info "Please install waybar: yay -S waybar"
    return 1
  fi

  local waybar_config="$USER_HOME/.config/waybar/config.jsonc"
  if [ ! -f "$waybar_config" ]; then
    log_warning "Waybar config not found ($waybar_config)"
    log_info "Creating basic Waybar config with hyprwhspr integration..."
    
    # Create basic waybar config
    mkdir -p "$USER_HOME/.config/waybar"
    cat > "$waybar_config" <<'WAYBAR_CONFIG'
{
  "layer": "top",
  "position": "top",
  "height": 30,
  "modules-left": ["hyprland/workspaces"],
  "modules-center": ["hyprland/window"],
  "modules-right": ["custom/hyprwhspr", "clock", "tray"],
  "include": ["hyprwhspr-module.jsonc"]
}
WAYBAR_CONFIG
    log_success "Created basic Waybar config"
  fi

  mkdir -p "$USER_HOME/.config/waybar"
  cat > "$USER_HOME/.config/waybar/hyprwhspr-module.jsonc" <<EOF
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
      if [ -n "$end_line" ]; then
        awk -v end="$end_line" 'NR==end {print; print "  \"include\": [\"hyprwhspr-module.jsonc\"],"; next} {print}' "$waybar_config" > "$waybar_config.tmp" && mv "$waybar_config.tmp" "$waybar_config"
      fi
    fi
  fi

  # Add the module to modules-right array if not already present
  if ! grep -q '"custom/hyprwhspr"' "$waybar_config"; then
    log_info "Adding hyprwhspr module as first entry in modules-right array..."
    local modules_right_line
    modules_right_line=$(grep -n '"modules-right"' "$waybar_config" | head -1 | cut -d: -f1 || true)
    if [ -n "$modules_right_line" ]; then
      # Find the opening bracket of modules-right array
      local open_line
      open_line=$(awk -v start="$modules_right_line" 'NR>=start && /\[/ {print NR; exit}' "$waybar_config")
      if [ -n "$open_line" ]; then
        # Add the module right after the opening bracket
        awk -v open="$open_line" 'NR==open {print; print "    \"custom/hyprwhspr\","; next} {print}' "$waybar_config" > "$waybar_config.tmp" && mv "$waybar_config.tmp" "$waybar_config"
        log_success "✓ Added hyprwhspr module as first entry in modules-right array"
      else
        log_warning "Could not find opening bracket of modules-right array"
      fi
    else
      log_warning "Could not find modules-right array in waybar config"
    fi
  else
    log_info "hyprwhspr module already present in modules-right array"
  fi

  if [ -f "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" ]; then
    log_info "Copying waybar CSS file to user config..."
    if cp "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" "$USER_HOME/.config/waybar/"; then
      log_success "✓ Waybar CSS file copied to user config"
    else
      log_error "✗ Failed to copy waybar CSS file to user config"
      return 1
    fi
    
    local waybar_style="$USER_HOME/.config/waybar/style.css"
    if [ -f "$waybar_style" ] && ! grep -q "hyprwhspr-style.css" "$waybar_style"; then
      log_info "Adding CSS import to waybar style.css..."
      if grep -q "^@import" "$waybar_style"; then
        awk '/^@import/ { print; last_import = NR } !/^@import/ { if (last_import && NR == last_import + 1) { print "@import \"hyprwhspr-style.css\";"; } print }' "$waybar_style" > "$waybar_style.tmp" && mv "$waybar_style.tmp" "$waybar_style"
      else
        echo -e "@import \"hyprwhspr-style.css\";\n$(cat "$waybar_style")" > "$waybar_style.tmp" && mv "$waybar_style.tmp" "$waybar_style"
      fi
      log_success "✓ CSS import added to waybar style.css"
    elif [ -f "$waybar_style" ]; then
      log_info "CSS import already present in waybar style.css"
    else
      log_warning "No waybar style.css found - user will need to add CSS import manually"
    fi
  else
    log_error "✗ Waybar CSS file not found at $INSTALL_DIR/config/waybar/hyprwhspr-style.css"
    return 1
  fi

  log_success "Waybar integration updated"
}

# ----------------------- User config ---------------------------
setup_user_config() {
  log_info "User config…"
  mkdir -p "$USER_CONFIG_DIR"
  if [ ! -f "$USER_CONFIG_DIR/config.json" ]; then
    cat > "$USER_CONFIG_DIR/config.json" <<'CFG'
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
    sudo tee /etc/udev/rules.d/99-uinput.rules > /dev/null <<'RULE'
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
  local all_ok=true

  if [ -e "/dev/uinput" ] && [ -r "/dev/uinput" ] && [ -w "/dev/uinput" ]; then
    log_success "✓ /dev/uinput accessible"
  else
    log_error "✗ /dev/uinput not accessible"; all_ok=false
  fi

  groups "$ACTUAL_USER" | grep -q "\binput\b"  && log_success "✓ user in 'input'"  || { log_error "✗ user NOT in 'input'"; all_ok=false; }
  groups "$ACTUAL_USER" | grep -q "\baudio\b"  && log_success "✓ user in 'audio'"  || { log_error "✗ user NOT in 'audio'"; all_ok=false; }

  command -v ydotool >/dev/null && timeout 5s ydotool help >/dev/null 2>&1 \
    && log_success "✓ ydotool responds" || { log_error "✗ ydotool problem"; all_ok=false; }

  command -v pactl >/dev/null && pactl list short sources | grep -q input \
    && log_success "✓ audio inputs present" || log_warning "⚠ no audio inputs detected"

  if have_system_whisper || [ -x "$USER_WC_DIR/build/bin/whisper-cli" ]; then
    timeout 10s whisper-cli --help >/dev/null 2>&1 \
      && log_success "✓ whisper-cli responds" || { log_error "✗ whisper-cli not responding"; all_ok=false; }
  fi

  if [ -x "$VENV_DIR/bin/python" ]; then
    timeout 5s "$VENV_DIR/bin/python" -c "import sounddevice" >/dev/null 2>&1 \
      && log_success "✓ Python audio libs present" || { log_error "✗ Python audio libs missing"; all_ok=false; }
  fi

  $all_ok && return 0 || return 1
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
    
    # Verify critical files were copied
    if [ -f "$INSTALL_DIR/config/waybar/hyprwhspr-style.css" ]; then
      log_success "✓ Waybar CSS file copied successfully"
    else
      log_error "✗ Waybar CSS file missing after copy operation"
      exit 1
    fi
    
    if [ -d "$INSTALL_DIR/share/assets" ]; then
      log_success "✓ Assets directory copied successfully"
    else
      log_error "✗ Assets directory missing after copy operation"
      exit 1
    fi
  else
    log_info "AUR mode: payload already at $INSTALL_DIR"
  fi

  install_system_dependencies
  setup_python_environment
  setup_nvidia_support
  setup_whisper
  download_models
  setup_systemd_service   # <— auto-enable & start (all modes)
  setup_hyprland_integration
  setup_user_config
  setup_permissions
  setup_audio_devices
  validate_installation
  verify_permissions_and_functionality
  test_installation
  setup_waybar_integration

  log_success "hyprwhspr installation completed!"
  log_info "Services active:"
  log_info "  systemctl --user status $YDOTOOL_UNIT $SERVICE_NAME"
  log_info "Logs:"
  log_info "  journalctl --user -u $SERVICE_NAME"
}

main "$@"
